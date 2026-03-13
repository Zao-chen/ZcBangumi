import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../pages/web_cookie_login_page.dart';
import '../providers/auth_provider.dart';
import '../providers/collection_provider.dart';
import '../services/api_client.dart';
import '../services/bangumi_web_session_service.dart';
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

  BangumiWebSessionService get _webSessionService => BangumiWebSessionService(
        storage: context.read<StorageService>(),
        api: context.read<ApiClient>(),
      );

  bool get _hasWebCookie {
    final storage = context.read<StorageService>();
    return storage.webSession?.isValid == true;
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
    final session = storage.webSession;

    if (session == null || !session.isValid) {
      if (!mounted) return;
      setState(() {
        _checkingWebCookie = false;
        _webCookieValidated = false;
        _webCookieUsername = null;
      });
      if (showMessage) {
        final message = storage.legacyWebSessionInvalidated
            ? '旧版网页登录状态已失效，请重新登录 Bangumi 网页'
            : '当前还没有可用的网页登录会话';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _checkingWebCookie = true;
      });
    }

    try {
      final sessionInfo = await _webSessionService.validateSession(session);
      if (!mounted) return;
      setState(() {
        _checkingWebCookie = false;
        _webCookieValidated = sessionInfo != null;
        _webCookieUsername = sessionInfo?.username ?? session.username;
      });
      if (showMessage) {
        final text = sessionInfo == null
            ? '网页登录会话已保存，但当前无法确认仍处于登录状态'
            : '网页登录会话校验成功，当前账号为 @${sessionInfo.username}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(text)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checkingWebCookie = false;
        _webCookieValidated = false;
        _webCookieUsername = null;
      });
      if (showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('网页登录会话校验失败: $e')),
        );
      }
    }
  }

  Future<void> _autoFetchWebCookie() async {
    if (!WebCookieLoginPage.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('自动登录当前仅支持 Android、iOS、Windows 和 macOS')),
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
        ? '已自动获取并保存 @${result.username} 的网页登录会话'
        : '已保存网页登录会话，但当前设备无法完成在线校验';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _clearWebCookie() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除网页登录会话'),
        content: const Text('清除后将无法使用网页登录发帖和回复功能。'),
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

    await _webSessionService.clearPersistedSession(clearLegacyInvalidated: false);
    if (!mounted) return;
    setState(() {
      _webCookieValidated = false;
      _webCookieUsername = null;
      _checkingWebCookie = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清除网页登录会话')),
    );
  }

  String _webCookieSubtitle() {
    final storage = context.read<StorageService>();
    if (!_hasWebCookie) {
      return storage.legacyWebSessionInvalidated
          ? '旧版网页登录状态已失效，请重新登录'
          : '未登录，超展开发帖和回复不可用';
    }
    if (_checkingWebCookie) {
      return '正在校验当前网页登录会话';
    }
    if (_webCookieValidated && _webCookieUsername != null) {
      return '已登录，当前网页登录账号为 @$_webCookieUsername';
    }
    return '网页登录会话已保存，但当前尚未通过在线校验';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
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
                    title: const Text('账号'),
                    subtitle: Text(
                      auth.user != null ? '@${auth.user!.username}' : '未登录',
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
                          title: const Text('Bangumi 网页登录'),
                          subtitle: Text(_webCookieSubtitle()),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: _autoFetchWebCookie,
                                icon: const Icon(Icons.login_rounded),
                                label: Text(_hasWebCookie ? '重新登录' : '自动登录'),
                              ),
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
                            '这份网页登录会话仅用于 Bangumi 网页侧的超展开回复和发帖，不影响 API Token 登录。',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
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
                      Text('退出登录'),
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
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认'),
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
