import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zc_bangumi/services/internal_link_handler.dart';
import 'package:zc_bangumi/services/link_navigator.dart';

class EmbeddedWebPageView extends StatefulWidget {
  final Uri initialUri;

  const EmbeddedWebPageView({super.key, required this.initialUri});

  @override
  State<EmbeddedWebPageView> createState() => _EmbeddedWebPageViewState();
}

class _EmbeddedWebPageViewState extends State<EmbeddedWebPageView>
    with AutomaticKeepAliveClientMixin {
  static const String _selectionPrefPrefix = 'moegirl_selection_';
  late final Dio _dio;
  Uri? _currentUri;
  String? _title;
  String? _contentHtml;
  String? _error;
  bool _loading = true;
  bool _showingSearchPicker = false;

  @override
  void initState() {
    super.initState();
    _dio = Dio(
      BaseOptions(
        responseType: ResponseType.plain,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
        },
        validateStatus: (status) =>
            status != null && status >= 200 && status < 400,
      ),
    );
    _loadContent();
  }

  @override
  void didUpdateWidget(covariant EmbeddedWebPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialUri != widget.initialUri) {
      _currentUri = null;
      _loadContent(requestUri: widget.initialUri);
    }
  }

  Future<void> _openInBrowser() async {
    final uri = _currentUri ?? widget.initialUri;
    final ok = await LinkNavigator.openBrowser(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Open failed')));
    }
  }

  Future<void> _loadContent({Uri? requestUri}) async {
    var effectiveUri = requestUri ?? _currentUri ?? widget.initialUri;
    if (_currentUri == null &&
        (requestUri == null ||
            requestUri.toString() == widget.initialUri.toString())) {
      final rememberedUri = await _getRememberedSelectionUri();
      if (rememberedUri != null) {
        effectiveUri = rememberedUri;
      }
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final response = await _dio.getUri(effectiveUri);
      final html = response.data as String? ?? '';
      final searchResults = _extractSearchResults(html, response.realUri);
      if (searchResults.isNotEmpty && _isSearchResultPage(response.realUri)) {
        if (!mounted) {
          return;
        }
        final selected = await _promptSearchResult(searchResults);
        if (selected != null) {
          await _rememberSelection(selected.uri);
          await _loadContent(requestUri: selected.uri);
          return;
        }
      }
      final contentHtml = _extractContentHtml(html, response.realUri);
      if (contentHtml == null || contentHtml.trim().isEmpty) {
        throw Exception('Content not found');
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _currentUri = response.realUri;
        _title = _extractTitle(html, response.realUri);
        _contentHtml = contentHtml;
        _loading = false;
      });
      if (!_isSearchResultPage(response.realUri)) {
        await _rememberSelection(response.realUri);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _currentUri = widget.initialUri;
        _title = null;
        _contentHtml = null;
        _error = '$e';
        _loading = false;
      });
    }
  }

  String? get _selectionPrefKey {
    final keyword = widget.initialUri.queryParameters['search']?.trim();
    if (keyword == null || keyword.isEmpty) {
      return null;
    }
    return '$_selectionPrefPrefix$keyword';
  }

  Future<Uri?> _getRememberedSelectionUri() async {
    final key = _selectionPrefKey;
    if (key == null) {
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key)?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(raw);
    if (uri == null) {
      return null;
    }
    return uri;
  }

  Future<void> _rememberSelection(Uri uri) async {
    final key = _selectionPrefKey;
    if (key == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, uri.toString());
  }

  bool _isSearchResultPage(Uri uri) {
    final hasSearchQuery = uri.queryParameters.containsKey('search');
    final title = uri.queryParameters['title']?.toLowerCase() ?? '';
    return hasSearchQuery || title.contains('special:');
  }

  Future<_MoegirlSearchResult?> _promptSearchResult(
    List<_MoegirlSearchResult> results,
  ) async {
    if (_showingSearchPicker || !mounted) {
      return null;
    }
    _showingSearchPicker = true;
    try {
      return await showModalBottomSheet<_MoegirlSearchResult>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) {
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.72,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        Text(
                          '\u9009\u62E9\u840C\u767E\u6761\u76EE',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = results[index];
                        return ListTile(
                          title: Text(item.title),
                          subtitle: item.snippet.isEmpty
                              ? null
                              : Text(
                                  item.snippet,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => Navigator.of(context).pop(item),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      _showingSearchPicker = false;
    }
  }

  String? _extractTitle(String html, Uri realUri) {
    final headingMatch = RegExp(
      r'<h1\b[^>]*>([\s\S]*?)</h1>',
      caseSensitive: false,
    ).firstMatch(html);
    final heading = _stripTags(headingMatch?.group(1) ?? '').trim();
    if (heading.isNotEmpty) {
      return heading;
    }

    final titleMatch = RegExp(
      r'<title\b[^>]*>([\s\S]*?)</title>',
      caseSensitive: false,
    ).firstMatch(html);
    final pageTitle = _decodeHtml(
      _stripTags(titleMatch?.group(1) ?? ''),
    ).trim();
    if (pageTitle.isNotEmpty) {
      return pageTitle.replaceFirst(RegExp(r'\s*[-|].*$'), '').trim();
    }

    return Uri.decodeComponent(
      realUri.pathSegments.isNotEmpty ? realUri.pathSegments.last : '',
    );
  }

  String? _extractContentHtml(String html, Uri baseUri) {
    final articleMatch = RegExp(
      r"""<article\b[^>]*\bid=(["'])mw-body\1[^>]*>([\s\S]*?)</article>""",
      caseSensitive: false,
    ).firstMatch(html);
    final article = articleMatch?.group(0);
    if (article != null && article.isNotEmpty) {
      return _normalizeHtmlUrls(_rearrangeInfobox(article), baseUri);
    }

    final templateMatch = RegExp(
      r"""<template\b[^>]*\bid=(["'])MOE_SKIN_TEMPLATE_BODYCONTENT\1[^>]*>([\s\S]*?)</template>""",
      caseSensitive: false,
    ).firstMatch(html);
    final templateBody = templateMatch?.group(2);
    if (templateBody != null && templateBody.trim().isNotEmpty) {
      return _normalizeHtmlUrls(_rearrangeInfobox(templateBody), baseUri);
    }

    // Try to extract both sidebar and main content for better layout
    final sidebarMatch = RegExp(
      r"""<aside\b[^>]*\bid=(["'])mw-panel-toc\1[^>]*>([\s\S]*?)</aside>""",
      caseSensitive: false,
    ).firstMatch(html);
    final sidebar = sidebarMatch?.group(0) ?? '';

    final contentMatch = RegExp(
      r"""<div\b[^>]*\bid=(["'])mw-content-text\1[^>]*>([\s\S]*?)</div>""",
      caseSensitive: false,
    ).firstMatch(html);
    final content = contentMatch?.group(0);
    if (content != null && content.trim().isNotEmpty) {
      final rearranged = _rearrangeInfobox(content);
      final withSidebar = sidebar.isNotEmpty
          ? '<div style="display:flex;gap:20px">$sidebar<div style="flex:1">$rearranged</div></div>'
          : rearranged;
      return _normalizeHtmlUrls(withSidebar, baseUri);
    }

    return null;
  }

  /// Rearrange infobox to be right-aligned (CSS will handle float in WebView)
  String _rearrangeInfobox(String html) {
    // CSS in WebView will handle infobox float styling,
    // so we just return the HTML as-is
    return html;
  }

  List<_MoegirlSearchResult> _extractSearchResults(String html, Uri baseUri) {
    final itemMatches = RegExp(
      r"""<li\b[^>]*class=(["'])[^"']*mw-search-result[^"']*\1[^>]*>([\s\S]*?)</li>""",
      caseSensitive: false,
    ).allMatches(html);

    final results = <_MoegirlSearchResult>[];
    for (final match in itemMatches) {
      final itemHtml = match.group(2) ?? '';
      final linkMatch = RegExp(
        r"""<div\b[^>]*class=(["'])[^"']*mw-search-result-heading[^"']*\1[^>]*>[\s\S]*?<a\b[^>]*href=(["'])([^"']+)\2[^>]*>([\s\S]*?)</a>""",
        caseSensitive: false,
      ).firstMatch(itemHtml);
      if (linkMatch == null) {
        continue;
      }

      final href = _decodeHtml(linkMatch.group(3) ?? '').trim();
      if (href.isEmpty) {
        continue;
      }

      final title = _decodeHtml(_stripTags(linkMatch.group(4) ?? '')).trim();
      if (title.isEmpty) {
        continue;
      }

      final snippetMatch = RegExp(
        r"""<div\b[^>]*class=(["'])[^"']*searchresult[^"']*\1[^>]*>([\s\S]*?)</div>""",
        caseSensitive: false,
      ).firstMatch(itemHtml);
      final snippet = _decodeHtml(
        _stripTags(snippetMatch?.group(2) ?? ''),
      ).replaceAll(RegExp(r'\s+'), ' ').trim();

      results.add(
        _MoegirlSearchResult(
          title: title,
          snippet: snippet,
          uri: baseUri.resolve(href),
        ),
      );
    }

    return results;
  }

  String _normalizeHtmlUrls(String html, Uri baseUri) {
    var normalized = html.replaceAllMapped(
      RegExp(r'''(href|src)=("|')([^"']+)("|')''', caseSensitive: false),
      (match) {
        final attr = match.group(1)!;
        final quote = match.group(2)!;
        final raw = match.group(3) ?? '';
        return '$attr=$quote${_resolveUrl(raw, baseUri)}$quote';
      },
    );
    normalized = normalized.replaceAllMapped(
      RegExp(r'''data-src=("|')([^"']+)("|')''', caseSensitive: false),
      (match) {
        final quote = match.group(1)!;
        final raw = match.group(2) ?? '';
        return 'src=$quote${_resolveUrl(raw, baseUri)}$quote';
      },
    );
    return normalized;
  }

  String _resolveUrl(String raw, Uri baseUri) {
    final value = raw.trim();
    if (value.isEmpty) {
      return value;
    }
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) {
      return parsed.toString();
    }
    return baseUri.resolve(value).toString();
  }

  String _stripTags(String value) {
    return value.replaceAll(RegExp(r'<[^>]+>'), '');
  }

  String _decodeHtml(String value) {
    return value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  String _wrapHtmlDocument(String articleHtml, BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? '#e8e6e3' : '#222222';
    final linkColor = isDarkMode ? '#4a9eff' : '#2c5594';

    return '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    
    html, body {
      background-color: transparent;
      color: $textColor;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      font-size: 14px;
      line-height: 1.6;
    }
    
    a {
      color: $linkColor;
      text-decoration: underline;
    }
    
    body {
      padding: 12px;
    }
    
    article, #mw-content-text, .mw-body-content {
      margin: 0;
      padding: 0;
    }
    
    h1, h2, h3, h4, h5, h6 {
      margin-top: 12px;
      margin-bottom: 8px;
      font-weight: 700;
    }
    
    h1 { font-size: 28px; }
    h2 { font-size: 22px; }
    h3 { font-size: 18px; }
    h4 { font-size: 16px; }
    h5 { font-size: 14px; }
    h6 { font-size: 12px; }
    
    p {
      margin-bottom: 12px;
      line-height: 1.6;
    }
    
    table {
      margin: 12px 0;
      border-collapse: collapse;
      width: 100%;
      background-color: transparent;
    }
    
    tr, tbody, thead {
      background-color: transparent !important;
    }
    
    td, th {
      padding: 8px;
      border: 1px solid rgba(0,0,0,0.1);
      background-color: transparent;
      color: #222222;
    }
    
    th {
      font-weight: bold;
      background-color: transparent;
      color: #222222;
    }
    
    ul, ol {
      margin: 8px 0;
      padding-left: 24px;
    }
    
    li {
      margin-bottom: 4px;
    }
    
    blockquote {
      margin: 12px 0;
      padding-left: 12px;
      border-left: 4px solid rgba(0,0,0,0.3);
    }
    
    code {
      background-color: transparent;
      padding: 2px 4px;
      font-family: monospace;
      font-size: 12px;
    }
    
    pre {
      background-color: transparent;
      padding: 12px;
      margin: 12px 0;
      overflow-x: auto;
      border-radius: 4px;
    }
    
    img {
      max-width: 100%;
      height: auto;
      margin: 8px 0;
      display: block;
    }
    
    .infobox, .moe-infobox, .infobox3 {
      float: right;
      clear: right;
      margin: 0 0 12px 12px;
      border: 1px solid rgba(0,0,0,0.1);
      padding: 4px;
      background-color: transparent;
      max-width: 280px;
      color: #222222;
    }
    
    .infobox-title {
      margin: 3px 0;
      padding: 6px;
      background-color: transparent;
      color: #222222;
      font-size: 120%;
      font-weight: bold;
      text-align: center;
    }
    
    .infobox-image, .infobox-image-container {
      margin: 3px 0;
      text-align: center;
      padding: 0;
      color: #222222;
    }
    
    .infobox-image img {
      max-width: 100%;
      height: auto;
      margin: 0;
    }
    
    /* Hide unnecessary elements */
    .toc, #toc, .navbox, .catlinks, .mw-editsection,
    .mw-footer, .printfooter, .mw-authority-control,
    .moe-card-tool, .mobile-edit-button, .backToTop,
    .reference-edit, .mw-jump-link, .nomobile, .noprint {
      display: none !important;
    }
  </style>
</head>
<body>
  $articleHtml
</body>
</html>''';
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _contentHtml == null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.article_outlined,
                    size: 40,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Failed to load article content',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error ?? '',
                    style: TextStyle(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        : RefreshIndicator(
            onRefresh: _loadContent,
            child: Column(
              children: [
                if ((_title ?? '').trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Text(
                      _title!,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                Expanded(
                  child: InAppWebView(
                    initialSettings: InAppWebViewSettings(
                      useShouldOverrideUrlLoading: true,
                      useOnLoadResource: false,
                      useOnRenderProcessGone: false,
                      transparentBackground: true,
                    ),
                    onWebViewCreated: (controller) {
                      final htmlDoc = _wrapHtmlDocument(_contentHtml!, context);
                      controller.loadData(
                        data: htmlDoc,
                        mimeType: 'text/html',
                        encoding: 'utf-8',
                      );
                    },
                    shouldOverrideUrlLoading:
                        (controller, navigationAction) async {
                          final url = navigationAction.request.url;
                          if (url == null) {
                            return NavigationActionPolicy.ALLOW;
                          }

                          final result = InternalLinkHandler.handleLink(
                            url.uriValue,
                            context,
                          );

                          if (result == InternalLinkResult.handled) {
                            return NavigationActionPolicy.CANCEL;
                          } else if (result ==
                              InternalLinkResult.openInBrowser) {
                            await LinkNavigator.openBrowser(url.uriValue);
                            return NavigationActionPolicy.CANCEL;
                          }

                          return NavigationActionPolicy.ALLOW;
                        },
                  ),
                ),
              ],
            ),
          );

    return Stack(
      children: [
        Positioned.fill(child: body),
        Positioned(
          right: 12,
          bottom: 12,
          child: SafeArea(
            minimum: const EdgeInsets.only(right: 4, bottom: 4),
            child: Material(
              color: colorScheme.surface.withValues(alpha: 0.92),
              elevation: 2,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Open in browser',
                onPressed: _openInBrowser,
                icon: const Icon(Icons.open_in_new),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MoegirlSearchResult {
  final String title;
  final String snippet;
  final Uri uri;

  const _MoegirlSearchResult({
    required this.title,
    required this.snippet,
    required this.uri,
  });
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

  String get _resolvedTitle {
    final currentTitle = _pageTitle?.trim() ?? '';
    return currentTitle.isEmpty ? widget.title : currentTitle;
  }

  Future<void> _reload() async {
    await _controller?.reload();
  }

  Future<void> _openInBrowser() async {
    final uri = _currentUrl?.uriValue ?? widget.initialUri;
    final ok = await LinkNavigator.openBrowser(uri);
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
      await LinkNavigator.openBrowser(uri);
      return NavigationActionPolicy.CANCEL;
    }

    // 对于HTTP(S)链接，检查是否是站内链接
    final result = InternalLinkHandler.handleLink(uri, context);

    if (result == InternalLinkResult.handled) {
      return NavigationActionPolicy.CANCEL;
    } else if (result == InternalLinkResult.openInBrowser) {
      await LinkNavigator.openBrowser(uri);
      return NavigationActionPolicy.CANCEL;
    }

    // 其他情况，允许WebView处理
    return NavigationActionPolicy.ALLOW;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final showProgress = _progress > 0 && _progress < 100;

    return WillPopScope(
      onWillPop: _handleBackPressed,
      child: Scaffold(
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
        body: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri.uri(widget.initialUri)),
          initialSettings: InAppWebViewSettings(
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
              await LinkNavigator.openBrowser(uri);
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
        ),
      ),
    );
  }
}
