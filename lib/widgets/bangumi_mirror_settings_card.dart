import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/bangumi_mirror_settings.dart';
import '../pages/bangumi_mirror_verification_page.dart';
import '../services/bangumi_endpoint_service.dart';
import '../services/bangumi_mirror_cookie_service.dart';

enum _MirrorSettingsAction { help, clearSessions }

class BangumiMirrorSettingsCard extends StatefulWidget {
  const BangumiMirrorSettingsCard({
    super.key,
    required this.endpoints,
    this.onVerify,
  });

  final BangumiEndpointService endpoints;
  final Future<void> Function(BuildContext, BangumiServiceKind)? onVerify;

  @override
  State<BangumiMirrorSettingsCard> createState() =>
      _BangumiMirrorSettingsCardState();
}

class _BangumiMirrorSettingsCardState extends State<BangumiMirrorSettingsCard> {
  late BangumiMirrorSource _source;
  final Map<BangumiServiceKind, TextEditingController> _controllers = {};
  bool _saving = false;
  bool _checking = false;
  bool _detailsExpanded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final settings = widget.endpoints.settings;
    _source = settings.source;
    final values = {
      BangumiServiceKind.web: settings.customWeb,
      BangumiServiceKind.api: settings.customApi,
      BangumiServiceKind.next: settings.customNext,
      BangumiServiceKind.lain: settings.customLain,
      BangumiServiceKind.fast: settings.customFast,
    };
    for (final kind in BangumiServiceKind.values) {
      _controllers[kind] = TextEditingController(text: values[kind]);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  BangumiMirrorSettings get _draft => BangumiMirrorSettings(
    source: _source,
    customWeb: _controllers[BangumiServiceKind.web]!.text,
    customApi: _controllers[BangumiServiceKind.api]!.text,
    customNext: _controllers[BangumiServiceKind.next]!.text,
    customLain: _controllers[BangumiServiceKind.lain]!.text,
    customFast: _controllers[BangumiServiceKind.fast]!.text,
  );

  Future<bool> _confirmRisk(BangumiMirrorSettings settings) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('第三方镜像安全风险'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '镜像运营者可能接触经过它的 Token、Cookie，以及在镜像网页内输入的账号密码。确认后，已有 Token 将用于此镜像的认证 API。官方及其他镜像的网页 Cookie 不会自动复制。请只使用你信任的镜像。',
                  ),
                  const SizedBox(height: 12),
                  for (final entry in settings.endpoints.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: SelectableText(
                        '${entry.key.label}：${entry.value.origin}',
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const ValueKey('mirror-confirm-risk'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('了解风险并使用'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _save() async {
    if (_saving || _checking) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final next = _draft;
      next.endpoints;
      var accepted = false;
      if (!widget.endpoints.hasConsent(next)) {
        accepted = await _confirmRisk(next);
        if (!accepted || !mounted) return;
      }
      await widget.endpoints.applySettings(next, acceptRisk: accepted);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('镜像设置已保存，新请求立即使用所选线路')));
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : '无法保存镜像设置，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await Future.wait(BangumiServiceKind.values.map(widget.endpoints.probe));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _verify(BangumiServiceKind kind) async {
    if (widget.onVerify != null) {
      await widget.onVerify!(context, kind);
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BangumiMirrorVerificationPage(
          endpoints: widget.endpoints,
          kind: kind,
        ),
      ),
    );
  }

  Future<void> _clearSessions() async {
    if (_saving || _checking) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final sessions = widget.endpoints.currentSessions;
      final nativeClear = supportsBangumiMirrorVerification
          ? BangumiMirrorCookieService().clear(widget.endpoints, sessions)
          : Future<void>.value();
      await nativeClear;
      await widget.endpoints.clearCurrentSessions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已清除当前镜像验证会话，Token 和官方登录保持不变')),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = '清除验证会话失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showHelp() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('镜像使用说明'),
      content: SingleChildScrollView(
        child: Text(
          '镜像仅影响 Bangumi，其他站点与代理设置保持独立。首次启用或更改服务地址时需要确认安全风险。\n\n'
          '检查连接不发送 Token 或登录 Cookie，结果仅代表本次连接。线路不会自动回退或切换。\n\n'
          '需要人机验证时，展开「连接详情」自行完成验证。客户端复测通过才保存会话，写操作不会自动重试。'
          '${kIsWeb
              ? '\n\n网页版受浏览器跨域限制，无法提取镜像验证会话。'
              : !supportsBangumiMirrorVerification
              ? '\n\n当前平台不支持应用内验证会话提取。'
              : ''}',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );

  String _connectionSummary() {
    if (_checking) return '正在检查…';
    final results = widget.endpoints.results.values;
    if (results.isEmpty) return '尚未检查';
    final available = results
        .where((result) => result.status == BangumiConnectionStatus.available)
        .length;
    if (available == BangumiServiceKind.values.length) return '全部可用';
    final issues = <String>[
      '可用 $available/${BangumiServiceKind.values.length}',
      for (final entry in const {
        BangumiConnectionStatus.challenge: '需验证',
        BangumiConnectionStatus.failed: '失败',
        BangumiConnectionStatus.corsRestricted: '受跨域限制',
      }.entries)
        if (results.any((result) => result.status == entry.key))
          '${results.where((result) => result.status == entry.key).length} 项${entry.value}',
    ];
    return issues.join(' · ');
  }

  Widget _buildConnectionResult(BangumiServiceKind kind, bool busy) {
    final result = widget.endpoints.results[kind];
    final colors = Theme.of(context).colorScheme;
    final (label, icon, color) = switch (result?.status) {
      BangumiConnectionStatus.available => (
        '可用',
        Icons.check_circle_outline,
        colors.primary,
      ),
      BangumiConnectionStatus.challenge => (
        '需要验证',
        Icons.verified_user_outlined,
        colors.tertiary,
      ),
      BangumiConnectionStatus.failed => (
        '失败',
        Icons.error_outline,
        colors.error,
      ),
      BangumiConnectionStatus.corsRestricted => (
        '受跨域限制',
        Icons.block_outlined,
        colors.error,
      ),
      null => ('尚未检查', Icons.help_outline, colors.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: Icon(icon, size: 20, color: color),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${kind.label} · $label'),
                SelectableText(
                  widget.endpoints.baseUri(kind).origin,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (result?.status == BangumiConnectionStatus.failed)
                  Text(
                    result!.message,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          if (!widget.endpoints.settings.isOfficial &&
              (supportsBangumiMirrorVerification || widget.onVerify != null) &&
              result?.status != BangumiConnectionStatus.available)
            TextButton(
              key: ValueKey('mirror-verify-${kind.name}'),
              onPressed: busy ? null : () => _verify(kind),
              child: const Text('验证'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.endpoints,
      builder: (context, child) {
        final active = widget.endpoints.settings;
        final busy = _saving || _checking;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.public_outlined, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bangumi 镜像站',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    PopupMenuButton<_MirrorSettingsAction>(
                      key: const ValueKey('mirror-more'),
                      tooltip: '更多选项',
                      enabled: !busy,
                      onSelected: (action) {
                        switch (action) {
                          case _MirrorSettingsAction.help:
                            _showHelp();
                          case _MirrorSettingsAction.clearSessions:
                            _clearSessions();
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: _MirrorSettingsAction.help,
                          child: Text('使用说明'),
                        ),
                        if (!active.isOfficial)
                          const PopupMenuItem(
                            value: _MirrorSettingsAction.clearSessions,
                            child: Text('清除验证会话'),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<BangumiMirrorSource>(
                  key: const ValueKey('mirror-source'),
                  initialValue: _source,
                  decoration: InputDecoration(
                    labelText: '线路',
                    helperText: '当前使用：${active.displayName}',
                    border: OutlineInputBorder(),
                  ),
                  items: BangumiMirrorSource.values
                      .map(
                        (source) => DropdownMenuItem(
                          value: source,
                          child: Text(
                            BangumiMirrorSettings(source: source).displayName,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: busy
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _source = value;
                              _error = null;
                            });
                          }
                        },
                ),
                if (_source == BangumiMirrorSource.custom) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('mirror-web-address'),
                    controller: _controllers[BangumiServiceKind.web],
                    enabled: !busy,
                    decoration: const InputDecoration(
                      labelText: '镜像主域名',
                      hintText: 'https://mirror.example.com',
                      helperText: 'HTTPS 根地址，可含端口',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  ExpansionTile(
                    key: const ValueKey('mirror-advanced'),
                    title: const Text('高级地址'),
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text('留空时自动生成子域名，不支持路径式反代。'),
                      ),
                      for (final kind in BangumiServiceKind.values)
                        if (kind != BangumiServiceKind.web)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: TextField(
                              key: ValueKey('mirror-${kind.name}-address'),
                              controller: _controllers[kind],
                              enabled: !busy,
                              decoration: InputDecoration(
                                labelText: '${kind.label} 地址',
                                hintText:
                                    'https://${kind.name}.mirror.example.com',
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                    ],
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('mirror-save'),
                      onPressed: busy ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_saving ? '正在保存…' : '保存线路'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('mirror-check'),
                      onPressed: busy ? null : _check,
                      icon: const Icon(Icons.network_check),
                      label: Text(_checking ? '正在检查…' : '检查连接'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  key: const ValueKey('mirror-connection-details'),
                  tilePadding: EdgeInsets.zero,
                  title: const Text('连接详情'),
                  subtitle: Text(_connectionSummary()),
                  onExpansionChanged: (expanded) {
                    setState(() => _detailsExpanded = expanded);
                  },
                  children: _detailsExpanded
                      ? [
                          for (final kind in BangumiServiceKind.values)
                            _buildConnectionResult(kind, busy),
                          if (!supportsBangumiMirrorVerification &&
                              widget.onVerify == null &&
                              !active.isOfficial)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text('当前平台不支持应用内验证'),
                            ),
                        ]
                      : const [],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
