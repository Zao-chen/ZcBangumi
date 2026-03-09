import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
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
    useShouldOverrideUrlLoading: true,
    useOnLoadResource: true,
    mediaPlaybackRequiresUserGesture: false,
  );

  InAppWebViewController? _controller;
  _WindowsCookieLoginBrowser? _windowsBrowser;
  Timer? _windowsCookiePoller;
  bool _loading = true;
  bool _capturing = false;
  String? _webViewError;
  String _title = 'Bangumi 登录';

  bool get _useWindowsBrowser =>
      defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    if (_useWindowsBrowser) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openWindowsBrowser();
      });
    }
  }

  @override
  void dispose() {
    _windowsCookiePoller?.cancel();
    // 先尝试关闭浏览器，然后再 dispose
    final browser = _windowsBrowser;
    if (browser != null) {
      if (!browser._closing && (browser.isOpened() ?? false)) {
        browser._closing = true;
        browser.close().catchError((_) {});
      }
      browser.dispose();
    }
    super.dispose();
  }

  bool _shouldIgnoreWebError(WebResourceError error) {
    final description = error.description.toLowerCase();
    if (description.contains('connection was stopped')) {
      return true;
    }
    if (description.contains('operation was canceled')) {
      return true;
    }
    if (description.contains('navigation canceled')) {
      return true;
    }
    final typeValue = error.type.toNativeValue();
    if (typeValue == -3) {
      return true;
    }
    return false;
  }

  Future<WebCookieLoginResult?> _captureCookieResult({
    WebSessionInfo? pageSession,
  }) async {
    if (_capturing || !mounted) return null;
    _capturing = true;
    final api = context.read<ApiClient>();
    final storage = context.read<StorageService>();

    try {
      final environment = defaultTargetPlatform == TargetPlatform.windows
          ? await WebViewEnvironmentService.getSharedEnvironment()
          : null;
      final cookieManager = CookieManager.instance(
        webViewEnvironment: environment,
      );
      List<Cookie> cookies;
      try {
        cookies = await cookieManager.getAllCookies();
      } catch (_) {
        cookies = <Cookie>[];
      }
      if (cookies.isEmpty) {
        cookies = <Cookie>[];
        cookies.addAll(
          await cookieManager.getCookies(url: WebUri('https://bgm.tv/')),
        );
        cookies.addAll(
          await cookieManager.getCookies(url: WebUri('https://bangumi.tv/')),
        );
        cookies.addAll(
          await cookieManager.getCookies(url: WebUri('https://chii.in/')),
        );
      }

      final pairs = <String, String>{};
      for (final cookie in cookies) {
        if (cookie.name.isEmpty) continue;
        final domain = (cookie.domain ?? '').toLowerCase();
        if (domain.isNotEmpty &&
            !domain.endsWith('bgm.tv') &&
            !domain.endsWith('bangumi.tv') &&
            !domain.endsWith('chii.in')) {
          continue;
        }
        pairs[cookie.name] = cookie.value;
      }

      if (pairs.isEmpty) return null;

      final cookie = pairs.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('; ');

      final hasAuthCookie =
          pairs.containsKey('chii_auth') ||
          pairs.containsKey('chii_sec_id') ||
          pairs.containsKey('chii_sid');
      if (!hasAuthCookie) return null;

      var session = pageSession;
      if (session == null) {
        try {
          session = await api.getWebSessionInfo(cookie: cookie);
        } catch (_) {
          session = null;
        }
      }
      if (session == null) return null;

      await storage.setWebCookie(cookie);
      await storage.setWebCookieJar(
        cookies
            .where((cookie) {
              final domain = (cookie.domain ?? '').toLowerCase();
              return domain.isEmpty ||
                  domain.endsWith('bgm.tv') ||
                  domain.endsWith('bangumi.tv') ||
                  domain.endsWith('chii.in');
            })
            .map(
              (cookie) => <String, dynamic>{
                'name': cookie.name,
                'value': '${cookie.value}',
                'domain': cookie.domain,
                'path': cookie.path,
                'expiresDate': cookie.expiresDate,
                'isSecure': cookie.isSecure,
                'isHttpOnly': cookie.isHttpOnly,
              },
            )
            .toList(),
      );
      api.setWebCookie(cookie);
      return WebCookieLoginResult(
        cookie: cookie,
        username: session.username,
        validated: true,
      );
    } finally {
      _capturing = false;
    }
  }

  Future<WebSessionInfo?> _readWebSessionFromController(
    InAppWebViewController? controller,
  ) async {
    if (controller == null) return null;
    try {
      final raw = await controller.evaluateJavascript(
        source: '''
(() => {
  const uid = typeof CHOBITS_UID !== 'undefined'
    ? Number.parseInt(CHOBITS_UID, 10) || 0
    : 0;
  const username = typeof CHOBITS_USERNAME !== 'undefined'
    ? String(CHOBITS_USERNAME || '')
    : '';
  return { uid, username };
})()
''',
      );
      if (raw is Map) {
        final uid = (raw['uid'] as num?)?.toInt() ?? 0;
        final username = (raw['username'] as String?)?.trim() ?? '';
        if (uid > 0 && username.isNotEmpty) {
          return WebSessionInfo(uid: uid, username: username);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _openWindowsBrowser() async {
    if (!_useWindowsBrowser || !mounted) return;

    _windowsCookiePoller?.cancel();

    // 安全关闭和清理旧浏览器
    final oldBrowser = _windowsBrowser;
    if (oldBrowser != null) {
      if (!oldBrowser._closing && (oldBrowser.isOpened() ?? false)) {
        oldBrowser._closing = true;
        try {
          await oldBrowser.close();
        } catch (_) {}
      }
      oldBrowser.dispose();
      _windowsBrowser = null;
    }

    setState(() {
      _loading = true;
      _webViewError = null;
    });

    final environment = await WebViewEnvironmentService.getSharedEnvironment();
    final browser = _WindowsCookieLoginBrowser(
      webViewEnvironment: environment,
      handleTitleChanged: (title) {
        if (!mounted) return;
        setState(() {
          _title = title?.trim().isNotEmpty == true
              ? title!.trim()
              : 'Bangumi 登录';
        });
      },
      handleResult: (result) async {
        if (!mounted) return;
        Navigator.of(context).pop(result);
      },
      handleExitWithoutResult: () {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _webViewError = '登录窗口已关闭，尚未检测到有效 Cookie';
        });
      },
      handleError: (message) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _webViewError = message;
        });
      },
      captureResult: _captureCookieResult,
      captureSession: () =>
          _readWebSessionFromController(_windowsBrowser?.webViewController),
    );
    _windowsBrowser = browser;

    try {
      await browser.openUrlRequest(
        urlRequest: URLRequest(url: WebUri('https://bgm.tv/login')),
        settings: InAppBrowserClassSettings(
          browserSettings: InAppBrowserSettings(
            hidden: false,
            toolbarTopFixedTitle: 'Bangumi 登录',
          ),
        ),
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      _startWindowsCookiePolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _webViewError = '无法打开登录窗口: $e';
      });
    }
  }

  void _startWindowsCookiePolling() {
    _windowsCookiePoller?.cancel();
    _windowsCookiePoller = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final result = await _captureCookieResult();
      if (!mounted || result == null) return;
      timer.cancel();
      _windowsCookiePoller = null;
      _windowsBrowser?.markCompleted();

      // 设置 closing 标志并安全关闭
      final browser = _windowsBrowser;
      if (browser != null &&
          !browser._closing &&
          (browser.isOpened() ?? false)) {
        browser._closing = true;
        try {
          await browser.close();
        } catch (_) {
          // 忽略关闭错误
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(result);
    });
  }

  Widget _buildWindowsBody(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _webViewError == null
                    ? Icons.open_in_new_rounded
                    : Icons.error_outline,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                _webViewError ?? '已打开 Bangumi 登录窗口',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _webViewError == null
                    ? '请在弹出的原生浏览器窗口里登录。登录成功后会自动保存 Cookie 并返回。'
                    : '可以点击下方按钮重新打开登录窗口。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (_loading)
                const CircularProgressIndicator()
              else
                FilledButton.tonalIcon(
                  onPressed: _openWindowsBrowser,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(_webViewError == null ? '重新打开' : '重试'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_useWindowsBrowser) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: SafeArea(child: _buildWindowsBody(context)),
      );
    }

    final showError = _webViewError != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_loading && !showError)
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
          else if (!showError)
            IconButton(
              onPressed: () {
                _controller?.reload();
              },
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
                        '登录成功后会自动保存 Bangumi 网页 Cookie，并返回设置页。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: showError
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
                      initialUrlRequest: URLRequest(
                        url: WebUri('https://bgm.tv/login'),
                      ),
                      initialSettings: _settings,
                      onWebViewCreated: (controller) {
                        _controller = controller;
                      },
                      onTitleChanged: (controller, title) {
                        if (!mounted) return;
                        setState(() {
                          _title = title?.trim().isNotEmpty == true
                              ? title!.trim()
                              : 'Bangumi 登录';
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
                        final navigator = Navigator.of(context);
                        setState(() {
                          _loading = false;
                        });
                        final result = await _captureCookieResult(
                          pageSession: await _readWebSessionFromController(
                            controller,
                          ),
                        );
                        if (result != null && mounted) {
                          navigator.pop(result);
                        }
                      },
                      onProgressChanged: (controller, progress) {
                        if (!mounted) return;
                        setState(() {
                          _loading = progress < 100;
                        });
                      },
                      onReceivedError: (controller, request, error) {
                        if (_shouldIgnoreWebError(error)) {
                          return;
                        }
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

class _WindowsCookieLoginBrowser extends InAppBrowser {
  final WebViewEnvironment? webViewEnvironment;
  final Future<WebCookieLoginResult?> Function({WebSessionInfo? pageSession})
  captureResult;
  final Future<WebSessionInfo?> Function() captureSession;
  final Future<void> Function(WebCookieLoginResult result) handleResult;
  final VoidCallback handleExitWithoutResult;
  final ValueChanged<String?> handleTitleChanged;
  final ValueChanged<String> handleError;
  bool _completed = false;
  bool _closing = false;

  _WindowsCookieLoginBrowser({
    required this.webViewEnvironment,
    required this.captureResult,
    required this.captureSession,
    required this.handleResult,
    required this.handleExitWithoutResult,
    required this.handleTitleChanged,
    required this.handleError,
  }) : super(webViewEnvironment: webViewEnvironment);

  void markCompleted() {
    _completed = true;
  }

  Future<void> _tryComplete() async {
    if (_completed || _closing) return;
    final result = await captureResult(pageSession: await captureSession());
    if (result == null) return;
    _completed = true;
    _closing = true;
    await handleResult(result);
    try {
      await close();
    } catch (_) {
      // 忽略关闭错误（可能已被外部关闭）
    }
  }

  @override
  void onLoadStop(WebUri? url) {
    unawaited(_tryComplete());
  }

  @override
  void onUpdateVisitedHistory(WebUri? url, bool? isReload) {
    unawaited(_tryComplete());
  }

  @override
  void onTitleChanged(String? title) {
    handleTitleChanged(title);
  }

  @override
  void onReceivedError(WebResourceRequest request, WebResourceError error) {
    final description = error.description.toLowerCase();
    if (description.contains('connection was stopped') ||
        description.contains('operation was canceled') ||
        description.contains('navigation canceled')) {
      return;
    }
    handleError(error.description);
  }

  @override
  void onExit() {
    if (_completed) return;
    handleExitWithoutResult();
  }
}

class WebCookieLoginResult {
  final String cookie;
  final String? username;
  final bool validated;

  const WebCookieLoginResult({
    required this.cookie,
    required this.username,
    required this.validated,
  });
}
