import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../widgets/scroll_aware_scaffold.dart';
import '../models/bangumi_mirror_session.dart';
import '../models/bangumi_mirror_settings.dart';
import '../models/bangumi_web_session.dart';
import '../services/bangumi_endpoint_service.dart';

bool get supportsBangumiMirrorVerification =>
    !kIsWeb &&
    const {
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }.contains(defaultTargetPlatform);

class BangumiMirrorVerificationPage extends StatefulWidget {
  const BangumiMirrorVerificationPage({
    super.key,
    required this.endpoints,
    required this.kind,
  });

  final BangumiEndpointService endpoints;
  final BangumiServiceKind kind;

  @override
  State<BangumiMirrorVerificationPage> createState() =>
      _BangumiMirrorVerificationPageState();
}

class _BangumiMirrorVerificationPageState
    extends State<BangumiMirrorVerificationPage> {
  late final Uri _uri;
  late final String _fingerprint;
  late final String _userAgent;
  InAppWebViewController? _controller;
  bool _checking = false;
  String? _error;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _uri = widget.endpoints.probeUri(widget.kind);
    _fingerprint = widget.endpoints.settings.fingerprint;
    _userAgent = widget.endpoints.userAgent(widget.kind);
  }

  Future<void> _finish() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      if (widget.endpoints.settings.fingerprint != _fingerprint) {
        throw StateError('镜像线路已变更，请返回后重新验证');
      }
      final captured = await CookieManager.instance().getCookies(
        url: WebUri.uri(_uri),
        webViewController: _controller,
      );
      final session = BangumiMirrorSession(
        fingerprint: _fingerprint,
        origin: _uri.origin,
        userAgent: _userAgent,
        cookies: captured
            .map(
              (cookie) => BangumiWebSessionCookie(
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain?.isNotEmpty == true
                    ? cookie.domain!
                    : _uri.host,
                path: cookie.path ?? '/',
                expiresDate: cookie.expiresDate,
                isSecure: cookie.isSecure ?? false,
                isHttpOnly: cookie.isHttpOnly ?? false,
              ),
            )
            .toList(),
      );
      await widget.endpoints.saveVerifiedSession(widget.kind, session);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : '无法读取或复用验证会话，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScrollAwareScaffold(
      appBar: AppBar(
        title: Text('${widget.kind.label}手动验证'),
        actions: [
          IconButton(
            tooltip: '重新加载',
            onPressed: _checking ? null : () => _controller?.reload(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '请在下方页面自行完成验证。完成后点击「验证完成，复测连接」。\n${_uri.origin}\n验证需要系统与应用使用兼容的网络出口，不会自动绕过验证。',
            ),
          ),
          if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: Builder(
              builder: (chromeContext) => InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri.uri(_uri)),
                initialSettings: InAppWebViewSettings(
                  userAgent: _userAgent,
                  useShouldOverrideUrlLoading: true,
                ),
                onWebViewCreated: (controller) => _controller = controller,
                shouldOverrideUrlLoading: (controller, action) async {
                  final target = action.request.url?.uriValue;
                  if (action.isForMainFrame &&
                      target != null &&
                      target.origin != _uri.origin) {
                    if (mounted) {
                      setState(() => _error = '已阻止跳转到其他站点，请在当前镜像内完成验证');
                    }
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
                onCreateWindow: (controller, action) async => false,
                onProgressChanged: (controller, progress) {
                  if (mounted) {
                    setState(() => _progress = progress.clamp(0, 100));
                  }
                },
                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame == true && mounted) {
                    setState(() => _error = '验证页面加载失败，请检查网络和系统代理');
                  }
                },
                onScrollChanged: (_, _, offset) {
                  if (chromeContext.mounted) {
                    ScrollAwareChrome.maybeOf(
                      chromeContext,
                    )?.handleNativeScroll(offset.toDouble());
                  }
                },
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: _checking ? null : _finish,
                icon: _checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_user_outlined),
                label: Text(_checking ? '正在复测客户端连接…' : '验证完成，复测连接'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
