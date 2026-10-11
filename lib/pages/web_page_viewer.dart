import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import '../widgets/scroll_aware_scaffold.dart';
import '../services/bangumi_endpoint_service.dart';
import '../models/bangumi_mirror_settings.dart';

import 'package:zc_bangumi/services/internal_link_handler.dart';
import 'package:zc_bangumi/services/link_navigator.dart';

Set<Factory<OneSequenceGestureRecognizer>> _webViewVerticalDragGestures() {
  return {
    Factory<OneSequenceGestureRecognizer>(
      () => VerticalDragGestureRecognizer(),
    ),
  };
}

class WebPageViewer extends StatefulWidget {
  final String title;
  final Uri initialUri;

  const WebPageViewer({
    super.key,
    required this.title,
    required this.initialUri,
  });

  @override
  State<WebPageViewer> createState() => _WebPageViewerState();
}

class _WebPageViewerState extends State<WebPageViewer> {
  InAppWebViewController? _controller;
  WebUri? _currentUrl;
  String? _pageTitle;
  int _progress = 0;
  bool _allowRoutePop = false;

  String get _resolvedTitle {
    final currentTitle = _pageTitle?.trim() ?? '';
    return currentTitle.isEmpty ? widget.title : currentTitle;
  }

  Future<void> _reload() async {
    await _controller?.reload();
  }

  Future<void> _openInBrowser() async {
    final uri = _currentUrl?.uriValue ?? widget.initialUri;
    final ok = await LinkNavigator.openBrowserFromContext(context, uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Open failed')));
    }
  }

  Future<bool> _handleBackPressed() async {
    final controller = _controller;
    if (controller == null) {
      return true;
    }

    final canGoBack = await controller.canGoBack();
    if (!canGoBack) {
      return true;
    }

    await controller.goBack();
    return false;
  }

  Future<void> _handlePopInvoked(bool didPop, Object? result) async {
    if (didPop) {
      return;
    }

    final shouldPopRoute = await _handleBackPressed();
    if (!shouldPopRoute || !mounted) {
      return;
    }

    setState(() => _allowRoutePop = true);
    Navigator.of(context).pop(result);
  }

  Future<NavigationActionPolicy> _handleNavigationAction(
    NavigationAction navigationAction,
  ) async {
    final uri = navigationAction.request.url?.uriValue;
    if (uri == null) {
      return NavigationActionPolicy.ALLOW;
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      // 非HTTP(S)链接，用浏览器打开
      await LinkNavigator.openBrowserFromContext(context, uri);
      return NavigationActionPolicy.CANCEL;
    }

    // 对于HTTP(S)链接，检查是否是站内链接
    final result = InternalLinkHandler.handleLink(uri, context);

    if (result == InternalLinkResult.handled) {
      return NavigationActionPolicy.CANCEL;
    } else if (result == InternalLinkResult.openInBrowser) {
      await LinkNavigator.openBrowserFromContext(context, uri);
      return NavigationActionPolicy.CANCEL;
    }

    // 其他情况，允许WebView处理
    return NavigationActionPolicy.ALLOW;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final showProgress = _progress > 0 && _progress < 100;
    final endpoints = context.watch<BangumiEndpointService?>();

    return PopScope<Object?>(
      canPop: _allowRoutePop,
      onPopInvokedWithResult: _handlePopInvoked,
      child: ScrollAwareScaffold(
        appBar: AppBar(
          title: Text(
            _resolvedTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: 'Open in browser',
              onPressed: _openInBrowser,
              icon: const Icon(Icons.open_in_new),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(showProgress ? 2 : 0),
            child: showProgress
                ? LinearProgressIndicator(
                    value: _progress / 100,
                    minHeight: 2,
                    color: colorScheme.primary,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  )
                : const SizedBox.shrink(),
          ),
        ),
        body: Builder(
          builder: (chromeContext) => InAppWebView(
            key: ValueKey(
              '${endpoints?.generation}:${endpoints?.sessionRevision}',
            ),
            gestureRecognizers: _webViewVerticalDragGestures(),
            initialUrlRequest: URLRequest(
              url: WebUri.uri(
                context.read<BangumiEndpointService?>()?.resolveUri(
                      widget.initialUri,
                    ) ??
                    widget.initialUri,
              ),
            ),
            initialSettings: InAppWebViewSettings(
              userAgent:
                  context.read<BangumiEndpointService?>()?.kindForUri(
                        widget.initialUri,
                      ) !=
                      null
                  ? context.read<BangumiEndpointService>().userAgent(
                      BangumiServiceKind.web,
                    )
                  : null,
              supportZoom: true,
              useShouldOverrideUrlLoading: true,
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
            },
            shouldOverrideUrlLoading: (controller, navigationAction) {
              return _handleNavigationAction(navigationAction);
            },
            onCreateWindow: (controller, createWindowAction) async {
              final uri = createWindowAction.request.url?.uriValue;
              if (uri != null) {
                await LinkNavigator.openBrowserFromContext(context, uri);
              }
              return false;
            },
            onTitleChanged: (controller, title) {
              if (!mounted) {
                return;
              }
              setState(() => _pageTitle = title);
            },
            onLoadStart: (controller, url) {
              if (!mounted) {
                return;
              }
              setState(() {
                _currentUrl = url;
                _progress = 0;
              });
            },
            onLoadStop: (controller, url) {
              if (!mounted) {
                return;
              }
              setState(() {
                _currentUrl = url;
                _progress = 100;
              });
            },
            onProgressChanged: (controller, progress) {
              if (!mounted) {
                return;
              }
              setState(() => _progress = progress.clamp(0, 100).toInt());
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
    );
  }
}
