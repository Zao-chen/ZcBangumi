import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/internal_link_handler.dart';
import '../services/link_navigator.dart';
import '../widgets/scroll_aware_scaffold.dart';

/// Loads the original site, including its styles, scripts and navigation.
class MoegirlWebView extends StatefulWidget {
  const MoegirlWebView({
    super.key,
    required this.subjectId,
    required this.initialUri,
    required this.isActive,
  });

  final int subjectId;
  final Uri initialUri;
  final bool isActive;

  @override
  State<MoegirlWebView> createState() => _MoegirlWebViewState();
}

class _MoegirlWebViewState extends State<MoegirlWebView>
    with AutomaticKeepAliveClientMixin {
  final _readerChanges = ValueNotifier<int>(0);
  InAppWebViewKeepAlive _keepAlive = InAppWebViewKeepAlive();
  BuildContext? _fullscreenContext;
  bool _isFullscreen = false;
  InAppWebViewController? _controller;
  Uri? _startUri;
  Uri? _currentUri;
  String? _error;
  int _progress = 0;
  int _restoreRevision = 0;
  int _historyRevision = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;

  String get _selectionKey => 'moegirl_subject_${widget.subjectId}';

  @override
  void initState() {
    super.initState();
    _restoreSelection();
  }

  @override
  void didUpdateWidget(covariant MoegirlWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subjectId != widget.subjectId ||
        oldWidget.initialUri != widget.initialUri) {
      _disposeKeepAliveAfterFrame(_keepAlive);
      _keepAlive = InAppWebViewKeepAlive();
      _controller = null;
      _startUri = null;
      _currentUri = null;
      _error = null;
      _progress = 0;
      _canGoBack = false;
      _canGoForward = false;
      _historyRevision++;
      _restoreSelection();
    }
  }

  @override
  void dispose() {
    _readerChanges.dispose();
    _disposeKeepAliveAfterFrame(_keepAlive);
    super.dispose();
  }

  Future<void> _disposeKeepAliveAfterFrame(
    InAppWebViewKeepAlive keepAlive,
  ) async {
    // Detach the platform view before releasing its retained native instance.
    await WidgetsBinding.instance.endOfFrame;
    await InAppWebViewController.disposeKeepAlive(keepAlive);
  }

  void _setReaderState(VoidCallback update) {
    if (!mounted) return;
    setState(update);
    _readerChanges.value++;
  }

  BuildContext get _navigationContext {
    final fullscreenContext = _fullscreenContext;
    return fullscreenContext != null && fullscreenContext.mounted
        ? fullscreenContext
        : context;
  }

  Future<void> _openFullscreen() async {
    if (_isFullscreen || _controller == null) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    setState(() {
      _isFullscreen = true;
      _controller = null;
    });
    // A retained native WebView can only be attached to one widget at a time.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (fullscreenContext) {
        _fullscreenContext = fullscreenContext;
        return Scaffold(
          appBar: AppBar(
            title: const Text('萌娘百科'),
            leading: IconButton(
              tooltip: '退出全屏',
              onPressed: () => Navigator.of(fullscreenContext).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
            scrolledUnderElevation: 0,
          ),
          body: ListenableBuilder(
            listenable: _readerChanges,
            builder: (context, _) => _buildReader(context, fullscreen: true),
          ),
        );
      },
    );
    await navigator.push(route);
    // Wait for the closing animation to detach the fullscreen platform view.
    await route.completed;
    _fullscreenContext = null;
    if (!mounted) return;
    setState(() {
      _isFullscreen = false;
      _controller = null;
    });
  }

  static bool _isMoegirlUri(Uri uri) {
    final host = uri.host.toLowerCase();
    return (uri.scheme == 'https' || uri.scheme == 'http') &&
        (host == 'moegirl.org.cn' || host.endsWith('.moegirl.org.cn'));
  }

  bool get _canRememberCurrentPage {
    final uri = _currentUri;
    if (uri == null || !_isMoegirlUri(uri) || _error != null) return false;
    if (uri.host != 'zh.moegirl.org.cn' && uri.host != 'mzh.moegirl.org.cn') {
      return false;
    }
    if (uri.queryParameters.containsKey('search')) return false;
    final action = uri.queryParameters['action'];
    if (action != null && action != 'view') return false;
    final title = uri.path == '/index.php'
        ? uri.queryParameters['title'] ?? ''
        : uri.pathSegments.join('/');
    return title.isNotEmpty &&
        !title.toLowerCase().startsWith('special:') &&
        !title.startsWith('特殊:');
  }

  Future<void> _restoreSelection() async {
    final revision = ++_restoreRevision;
    final initialUri = widget.initialUri;
    final key = _selectionKey;
    Uri? savedUri;
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyword = initialUri.queryParameters['search'];
      final raw =
          prefs.getString(key) ??
          (keyword == null
              ? null
              : prefs.getString('moegirl_selection_$keyword'));
      final parsed = raw == null ? null : Uri.tryParse(raw);
      if (parsed != null && _isMoegirlUri(parsed)) savedUri = parsed;
    } catch (_) {
      // A preferences failure must not prevent opening the original website.
    }
    if (!mounted || revision != _restoreRevision) return;
    _setReaderState(() {
      _startUri = savedUri ?? initialUri;
      _currentUri = _startUri;
    });
  }

  Future<void> _rememberCurrentPage() async {
    if (!_canRememberCurrentPage) return;
    final key = _selectionKey;
    final uri = _currentUri!;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, uri.toString());
      if (mounted) _showMessage('已记住此作品的萌百条目');
    } catch (_) {
      if (mounted) _showMessage('保存失败，请重试');
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(
      _navigationContext,
    ).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openExternal(Uri uri) async {
    final opened = await LinkNavigator.openBrowserFromContext(
      _navigationContext,
      uri,
    );
    if (!opened && mounted) _showMessage('打开网页失败');
  }

  Future<NavigationActionPolicy> _navigationPolicy(Uri uri) async {
    if (_isMoegirlUri(uri) || uri.toString() == 'about:blank') {
      return NavigationActionPolicy.ALLOW;
    }
    if (const {'javascript', 'data', 'file', 'about'}.contains(uri.scheme)) {
      return NavigationActionPolicy.CANCEL;
    }
    if (!mounted) return NavigationActionPolicy.CANCEL;
    final result = InternalLinkHandler.handleLink(uri, _navigationContext);
    if (result != InternalLinkResult.handled) await _openExternal(uri);
    return NavigationActionPolicy.CANCEL;
  }

  Future<void> _updateHistory(InAppWebViewController controller) async {
    final revision = ++_historyRevision;
    try {
      final back = await controller.canGoBack();
      final forward = await controller.canGoForward();
      if (!mounted ||
          revision != _historyRevision ||
          controller != _controller) {
        return;
      }
      _setReaderState(() {
        _canGoBack = back;
        _canGoForward = forward;
      });
    } catch (_) {
      // The native view may be disposed while its history is being queried.
    }
  }

  void _reportError(WebResourceRequest request, String message) {
    if (!mounted || request.isForMainFrame != true) return;
    final failedUri = request.url.uriValue;
    if (_currentUri != null &&
        failedUri.replace(fragment: '') != _currentUri!.replace(fragment: '')) {
      return;
    }
    _setReaderState(() {
      _error = message;
      _progress = 100;
    });
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isFullscreen) return const SizedBox.expand();
    return _buildReader(context);
  }

  Widget _buildReader(BuildContext context, {bool fullscreen = false}) {
    final startUri = _startUri;
    if (startUri == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return PopScope<Object?>(
      canPop: fullscreen || !widget.isActive || !_canGoBack,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !fullscreen && widget.isActive && _canGoBack) {
          _controller?.goBack();
        }
      },
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '网页后退',
                  onPressed: _canGoBack ? () => _controller?.goBack() : null,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                IconButton(
                  tooltip: '网页前进',
                  onPressed: _canGoForward
                      ? () => _controller?.goForward()
                      : null,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
                Expanded(
                  child: fullscreen
                      ? const SizedBox.shrink()
                      : const Text(
                          '萌娘百科',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
                IconButton(
                  tooltip: '刷新网页',
                  onPressed: _controller == null
                      ? null
                      : () => _controller?.reload(),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: '在浏览器打开',
                  onPressed: () => _openExternal(_currentUri ?? startUri),
                  icon: const Icon(Icons.open_in_new_rounded),
                ),
                if (!fullscreen)
                  IconButton.filledTonal(
                    tooltip: '全屏查看',
                    onPressed: _controller == null ? null : _openFullscreen,
                    icon: const Icon(Icons.fullscreen_rounded),
                  ),
                PopupMenuButton<String>(
                  tooltip: '萌百选项',
                  onSelected: (value) {
                    if (value == 'remember') {
                      _rememberCurrentPage();
                    } else if (value == 'search') {
                      _controller?.loadUrl(
                        urlRequest: URLRequest(
                          url: WebUri.uri(widget.initialUri),
                        ),
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'remember',
                      enabled: _canRememberCurrentPage && _progress == 100,
                      child: const Text('记住当前条目'),
                    ),
                    PopupMenuItem(
                      value: 'search',
                      enabled: _controller != null,
                      child: const Text('重新搜索'),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(
              height: 2,
              child: _progress < 100
                  ? LinearProgressIndicator(
                      value: _progress == 0 ? null : _progress / 100,
                    )
                  : null,
            ),
            if (_error != null)
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(_error!)),
                      TextButton(
                        onPressed: () => _controller?.reload(),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Builder(
                builder: (chromeContext) => InAppWebView(
                  key: ValueKey('${widget.subjectId}:${widget.initialUri}'),
                  keepAlive: _keepAlive,
                  initialUrlRequest: URLRequest(url: WebUri.uri(startUri)),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    supportZoom: true,
                    useShouldOverrideUrlLoading: true,
                    supportMultipleWindows: true,
                  ),
                  gestureRecognizers: {
                    Factory<OneSequenceGestureRecognizer>(
                      () => VerticalDragGestureRecognizer(),
                    ),
                    Factory<OneSequenceGestureRecognizer>(
                      () => HorizontalDragGestureRecognizer(),
                    ),
                  },
                  onWebViewCreated: (controller) {
                    _setReaderState(() => _controller = controller);
                    _updateHistory(controller);
                  },
                  shouldOverrideUrlLoading: (controller, action) async {
                    // Embedded frames must not launch external browsers while loading.
                    if (!action.isForMainFrame) {
                      return NavigationActionPolicy.ALLOW;
                    }
                    final uri = action.request.url?.uriValue;
                    return uri == null
                        ? NavigationActionPolicy.ALLOW
                        : _navigationPolicy(uri);
                  },
                  onCreateWindow: (controller, action) async {
                    final uri = action.request.url?.uriValue;
                    if (uri != null &&
                        await _navigationPolicy(uri) ==
                            NavigationActionPolicy.ALLOW) {
                      await controller.loadUrl(urlRequest: action.request);
                    }
                    return false;
                  },
                  onLoadStart: (controller, url) {
                    if (!mounted) return;
                    _setReaderState(() {
                      _currentUri = url?.uriValue ?? _currentUri;
                      _error = null;
                      _progress = 0;
                    });
                  },
                  onLoadStop: (controller, url) {
                    if (!mounted) return;
                    _setReaderState(() {
                      _currentUri = url?.uriValue ?? _currentUri;
                      _progress = 100;
                    });
                    _updateHistory(controller);
                  },
                  onUpdateVisitedHistory: (controller, url, isReload) {
                    if (!mounted) return;
                    _setReaderState(
                      () => _currentUri = url?.uriValue ?? _currentUri,
                    );
                    _updateHistory(controller);
                  },
                  onProgressChanged: (_, progress) {
                    if (mounted) {
                      _setReaderState(() => _progress = progress.clamp(0, 100));
                    }
                  },
                  onReceivedError: (_, request, error) {
                    if (error.type == WebResourceErrorType.CANCELLED) return;
                    _reportError(request, '网页加载失败，请检查网络后重试');
                  },
                  onReceivedHttpError: (_, request, response) {
                    _reportError(
                      request,
                      '网页暂时无法访问（${response.statusCode}），可重试或在浏览器打开',
                    );
                  },
                  onScrollChanged: (_, _, offset) {
                    if (!fullscreen &&
                        chromeContext.mounted &&
                        widget.isActive) {
                      ScrollAwareChrome.maybeOf(
                        chromeContext,
                      )?.handleNativeScroll(offset.toDouble());
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
