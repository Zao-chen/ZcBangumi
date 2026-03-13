import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../models/bangumi_web_session.dart';
import '../services/api_client.dart';
import '../services/bangumi_web_session_service.dart';
import '../services/storage_service.dart';
import '../services/webview_environment_service.dart';

class WebCookieLoginPage extends StatefulWidget {
  const WebCookieLoginPage({super.key});

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  @override
  State<WebCookieLoginPage> createState() => _WebCookieLoginPageState();
}

class _WebCookieLoginPageState extends State<WebCookieLoginPage> {
  final InAppWebViewSettings _settings = InAppWebViewSettings(
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: true,
    useShouldOverrideUrlLoading: false,
    useOnLoadResource: true,
    mediaPlaybackRequiresUserGesture: false,
  );

  InAppWebViewController? _controller;
  WebViewEnvironment? _webViewEnvironment;
  Timer? _capturePoller;
  bool _preparing = true;
  bool _loading = true;
  bool _capturing = false;
  String? _webViewError;
  String? _debugText;
  String _title = 'Bangumi 网页登录';
  int _reloadNonce = 0;

  BangumiWebSessionService get _sessionService => BangumiWebSessionService(
        storage: context.read<StorageService>(),
        api: context.read<ApiClient>(),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareLogin();
    });
  }

  @override
  void dispose() {
    _capturePoller?.cancel();
    super.dispose();
  }

  Future<void> _prepareLogin() async {
    if (!mounted) return;
    setState(() {
      _preparing = true;
      _loading = true;
      _webViewError = null;
    });

    try {
      _webViewEnvironment =
          await WebViewEnvironmentService.getSharedEnvironment();
      await _sessionService.clearPersistedSession();
      await _sessionService.clearBangumiCookies();
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _reloadNonce++;
        _debugText = '正在准备网页登录环境...';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _loading = false;
        _webViewError = '初始化网页登录页失败: $e';
      });
    }
  }

  Future<BangumiWebPageSignal> _readPageSignal(
    InAppWebViewController controller,
  ) async {
    try {
      final raw = await controller.evaluateJavascript(
        source: '''
(() => {
  const uid = typeof CHOBITS_UID !== 'undefined'
    ? Number.parseInt(CHOBITS_UID, 10) || 0
    : 0;
  const usernameFromVar = typeof CHOBITS_USERNAME !== 'undefined'
    ? String(CHOBITS_USERNAME || '').trim()
    : '';
  const profileLink = document.querySelector('a[href^="/user/"]');
  const profileHref = profileLink?.getAttribute('href') || '';
  const usernameFromHref = profileHref.startsWith('/user/')
    ? profileHref.replace('/user/', '').split(/[?#]/)[0]
    : '';
  const logoutLink = document.querySelector('a[href*="/logout"]');
  const signOutLink = document.querySelector('a[href*="logout"], a[href*="/signout"]');
  const chobitsUser = typeof window !== 'undefined' &&
    typeof window.CHOBITS_USER_UID !== 'undefined'
      ? Number.parseInt(window.CHOBITS_USER_UID, 10) || 0
      : 0;
  const username = usernameFromVar || usernameFromHref;
  const loggedIn = uid > 0 ||
    chobitsUser > 0 ||
    !!logoutLink ||
    !!signOutLink ||
    profileHref.startsWith('/user/');
  return {
    loggedIn,
    uid: uid > 0 ? uid : (chobitsUser > 0 ? chobitsUser : null),
    username: username || null,
  };
})()
''',
      );
      final normalized = _normalizeJsMap(raw);
      if (normalized != null) {
        return BangumiWebPageSignal(
          loggedIn: normalized['loggedIn'] == true,
          uid: (normalized['uid'] as num?)?.toInt(),
          username: (normalized['username'] as String?)?.trim(),
        );
      }
    } catch (_) {
      // Ignore transient JS evaluation failures while navigating.
    }
    return const BangumiWebPageSignal(loggedIn: false);
  }

  Map<String, dynamic>? _normalizeJsMap(dynamic raw) {
    if (raw is Map) {
      return raw.map((key, value) => MapEntry('$key', value));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry('$key', value));
        }
      } catch (_) {
        // Ignore non-JSON strings.
      }
    }
    return null;
  }

  Future<void> _maybeCaptureSession(InAppWebViewController controller) async {
    if (_capturing || !mounted) return;
    _capturing = true;
    try {
      final signal = await _readPageSignal(controller);
      final currentUrl = (await controller.getUrl())?.toString() ?? '';
      final onBangumiHome = currentUrl.startsWith('https://bgm.tv/') ||
          currentUrl.startsWith('http://bgm.tv/') ||
          currentUrl.startsWith('https://bangumi.tv/') ||
          currentUrl.startsWith('https://chii.in/');
      final inspection = await _sessionService.inspectSession(
        pageSignal: signal,
      );
      if (mounted) {
        final cookieNames = inspection.cookies
            .take(8)
            .map((cookie) => cookie.name)
            .join(', ');
        final requestCookieNames = inspection.requestCookieNames
            .take(8)
            .join(', ');
        setState(() {
          _debugText =
              '当前地址: $currentUrl\n'
              '页面登录态: ${signal.loggedIn} uid=${signal.uid ?? '-'} username=${signal.username ?? '-'}\n'
              '是否在 Bangumi 首页: $onBangumiHome cookies=${inspection.cookies.length} hasAuthCookie=${inspection.hasAuthCookie}\n'
              'Cookie 名称: ${cookieNames.isEmpty ? '-' : cookieNames}\n'
              '验真请求 Cookie: ${inspection.requestCookieCount} 个 ${requestCookieNames.isEmpty ? '-' : requestCookieNames}\n'
              '验真结果: ${inspection.validatedSession != null ? '@${inspection.validatedSession!.username}' : 'null'}\n'
              '检查错误: ${inspection.error ?? '-'}';
        });
      }
      if (!signal.loggedIn && !onBangumiHome && !inspection.hasAuthCookie) {
        return;
      }

      final session = await _sessionService.captureValidatedSession(
        pageSignal: signal,
        inspection: inspection,
      );
      if (!mounted || session == null) return;
      _capturePoller?.cancel();
      Navigator.of(context).pop(
        WebCookieLoginResult(session: session, validated: true),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _webViewError = '检测到已登录，但会话校验失败: $e';
      });
    } finally {
      _capturing = false;
    }
  }

  void _restartCapturePolling() {
    _capturePoller?.cancel();
    _capturePoller = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final controller = _controller;
      if (!mounted || controller == null) {
        timer.cancel();
        return;
      }
      await _maybeCaptureSession(controller);
    });
  }

  bool _shouldIgnoreWebError(
    WebResourceRequest request,
    WebResourceError error,
  ) {
    final requestUrl = request.url.toString();
    if (requestUrl == 'about:blank') return true;
    final description = error.description.toLowerCase();
    if (description.contains('connection was stopped')) return true;
    if (description.contains('operation was canceled')) return true;
    if (description.contains('navigation canceled')) return true;
    return error.type.toNativeValue() == -3;
  }

  @override
  Widget build(BuildContext context) {
    final showError = _webViewError != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_preparing || _loading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              onPressed: showError ? _prepareLogin : () => _controller?.reload(),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '登录成功后，应用会自动校验并保存 Bangumi 网页会话。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_debugText != null)
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: SelectableText(
                  _debugText!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'Consolas',
                      ),
                ),
              ),
            Expanded(
              child: _preparing
                  ? const Center(child: CircularProgressIndicator())
                  : showError
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _webViewError!,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : InAppWebView(
                          key: ValueKey(_reloadNonce),
                          webViewEnvironment: _webViewEnvironment,
                          initialUrlRequest: URLRequest(
                            url: WebUri('https://bgm.tv/login'),
                          ),
                          initialSettings: _settings,
                          onWebViewCreated: (controller) {
                            _controller = controller;
                            _restartCapturePolling();
                          },
                          onTitleChanged: (controller, title) {
                            if (!mounted) return;
                            setState(() {
                              _title = title?.trim().isNotEmpty == true
                                  ? title!.trim()
                                  : 'Bangumi 网页登录';
                            });
                          },
                          onLoadStart: (controller, url) {
                            if (!mounted) return;
                            setState(() {
                              _loading = true;
                            });
                          },
                          onLoadStop: (controller, url) async {
                            if (!mounted) return;
                            setState(() {
                              _loading = false;
                            });
                            await _maybeCaptureSession(controller);
                          },
                          onUpdateVisitedHistory: (controller, url, isReload) {
                            unawaited(_maybeCaptureSession(controller));
                          },
                          onProgressChanged: (controller, progress) {
                            if (!mounted) return;
                            setState(() {
                              _loading = progress < 100;
                            });
                            if (progress >= 100) {
                              unawaited(_maybeCaptureSession(controller));
                            }
                          },
                          onReceivedError: (controller, request, error) {
                            if (_shouldIgnoreWebError(request, error)) return;
                            if (!mounted) return;
                            setState(() {
                              _loading = false;
                              _webViewError = error.description;
                            });
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class WebCookieLoginResult {
  final BangumiWebSession session;
  final bool validated;

  const WebCookieLoginResult({
    required this.session,
    required this.validated,
  });

  String? get username => session.username.isEmpty ? null : session.username;
}
