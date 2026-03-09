import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/collection_provider.dart';
import '../pages/web_cookie_login_page.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../widgets/update_dialog.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _version = '';
  bool _checkingWebCookie = false;
  String? _webCookieUsername;
  bool _webCookieValidated = false;

  bool get _hasWebCookie {
    final storage = context.read<StorageService>();
    final cookie = storage.webCookie;
    return cookie != null && cookie.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _loadVersion();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshWebCookieStatus();
    });
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = 'v${packageInfo.version}';
    });
  }

  Future<void> _refreshWebCookieStatus({bool showMessage = false}) async {
    final storage = context.read<StorageService>();
    final api = context.read<ApiClient>();
    final cookie = storage.webCookie;

    if (cookie == null || cookie.isEmpty) {
      if (!mounted) return;
      setState(() {
        _checkingWebCookie = false;
        _webCookieValidated = false;
        _webCookieUsername = null;
      });
      if (showMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('还没有导入网页 Cookie')));
      }
      return;
    }

    setState(() {
      _checkingWebCookie = true;
    });

    try {
      final session = await api.getWebSessionInfo();
      if (!mounted) return;
      setState(() {
        _checkingWebCookie = false;
        _webCookieValidated = session != null;
        _webCookieUsername = session?.username;
      });
      if (showMessage) {
        final text = session == null
            ? 'Cookie 已保存，但当前没有识别到登录态'
            : 'Cookie 校验成功，当前会话为 @${session.username}';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checkingWebCookie = false;
        _webCookieValidated = false;
        _webCookieUsername = null;
      });
      if (showMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Cookie 校验失败: $e')));
      }
    }
  }

  Future<void> _editWebCookie() async {
    final storage = context.read<StorageService>();
    final api = context.read<ApiClient>();
    final controller = TextEditingController(text: storage.webCookie ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入网页 Cookie'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '从已登录的浏览器复制完整 Cookie 字符串，支持直接粘贴 “Cookie: ...” 请求头。',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 8,
                minLines: 5,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Cookie: chii_auth=...; chii_sec_id=...; ...',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (!mounted || result == null) return;

    final normalized = ApiClient.sanitizeWebCookie(result);
    if (normalized.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cookie 不能为空')));
      return;
    }

    await storage.setWebCookie(normalized);
    await storage.setWebCookieJar(null);
    api.setWebCookie(normalized);
    await _refreshWebCookieStatus(showMessage: true);
  }

  Future<void> _autoFetchWebCookie() async {
    if (!WebCookieLoginPage.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('自动获取目前只支持 Android、iOS 和 Windows')),
      );
      return;
    }

    final result = await Navigator.of(context).push<WebCookieLoginResult>(
      MaterialPageRoute(builder: (_) => const WebCookieLoginPage()),
    );

    if (!mounted || result == null) return;

    setState(() {
      _webCookieValidated = result.validated;
      _webCookieUsername = result.username;
      _checkingWebCookie = false;
    });

    final message = result.validated && result.username != null
        ? '已自动获取并保存 @${result.username} 的 Cookie'
        : '已自动获取并保存 Cookie，但当前设备无法完成在线校验';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _clearWebCookie() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除网页 Cookie'),
        content: const Text('清除后将无法使用网页发帖和回复能力。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final storage = context.read<StorageService>();
    final api = context.read<ApiClient>();
    await storage.setWebCookie(null);
    await storage.setWebCookieJar(null);
    if (!mounted) return;
    api.setWebCookie(null);
    setState(() {
      _webCookieValidated = false;
      _webCookieUsername = null;
      _checkingWebCookie = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清除网页 Cookie')));
  }

  String _webCookieSubtitle() {
    if (!_hasWebCookie) {
      return '未导入，超展开发帖和回复不可用';
    }
    if (_checkingWebCookie) {
      return '正在校验当前 Cookie 对应的网页会话';
    }
    if (_webCookieValidated && _webCookieUsername != null) {
      return '已导入，当前网页会话为 @$_webCookieUsername';
    }
    return '已导入，但当前设备未完成在线校验';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              'assets/images/bangumi_icon.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'ZC Bangumi',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Bangumi 番组计划第三方客户端',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _version,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Card(child: CheckUpdateButton()),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('Account'),
                    subtitle: Text(
                      auth.user != null
                          ? '@${auth.user!.username}'
                          : 'Not signed in',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            _webCookieValidated
                                ? Icons.verified_user_outlined
                                : Icons.cookie_outlined,
                          ),
                          title: const Text('Bangumi 网页 Cookie'),
                          subtitle: Text(_webCookieSubtitle()),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Row(
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: _autoFetchWebCookie,
                                icon: const Icon(Icons.login_rounded),
                                label: const Text('自动获取'),
                              ),
                              const SizedBox(width: 12),
                              FilledButton.tonalIcon(
                                onPressed: _editWebCookie,
                                icon: const Icon(Icons.edit_outlined),
                                label: Text(_hasWebCookie ? '编辑' : '导入'),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: _checkingWebCookie
                                    ? null
                                    : () => _refreshWebCookieStatus(
                                        showMessage: true,
                                      ),
                                icon: _checkingWebCookie
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.refresh_rounded),
                                label: const Text('校验'),
                              ),
                              const SizedBox(width: 12),
                              if (_hasWebCookie)
                                TextButton.icon(
                                  onPressed: _clearWebCookie,
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('清除'),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Text(
                            '这份 Cookie 只用于 Bangumi 网页侧的超展开回复和发帖，不影响 API Token 登录。',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (auth.isLoggedIn)
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () => _confirmLogout(context),
                  style: FilledButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.logout_rounded),
                      SizedBox(width: 8),
                      Text('Sign out'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<CollectionProvider>().clearAll();
      await auth.logout();
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}
