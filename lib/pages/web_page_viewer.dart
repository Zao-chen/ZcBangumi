import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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
        headers: const {'User-Agent': 'ZCBangumi/0.1.0 (Flutter App)'},
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
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Open failed')));
    }
  }

  Future<void> _loadContent({Uri? requestUri}) async {
    var effectiveUri = requestUri ?? _currentUri ?? widget.initialUri;
    if (_currentUri == null &&
        (requestUri == null || requestUri.toString() == widget.initialUri.toString())) {
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
    final pageTitle = _decodeHtml(_stripTags(titleMatch?.group(1) ?? '')).trim();
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
      return _normalizeHtmlUrls(article, baseUri);
    }

    final templateMatch = RegExp(
      r"""<template\b[^>]*\bid=(["'])MOE_SKIN_TEMPLATE_BODYCONTENT\1[^>]*>([\s\S]*?)</template>""",
      caseSensitive: false,
    ).firstMatch(html);
    final templateBody = templateMatch?.group(2);
    if (templateBody != null && templateBody.trim().isNotEmpty) {
      return _normalizeHtmlUrls(templateBody, baseUri);
    }

    final contentMatch = RegExp(
      r"""<div\b[^>]*\bid=(["'])mw-content-text\1[^>]*>([\s\S]*?)</div>""",
      caseSensitive: false,
    ).firstMatch(html);
    final content = contentMatch?.group(0);
    if (content != null && content.trim().isNotEmpty) {
      return _normalizeHtmlUrls(content, baseUri);
    }

    return null;
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
      final snippet = _decodeHtml(_stripTags(snippetMatch?.group(2) ?? ''))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

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
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                if ((_title ?? '').trim().isNotEmpty) ...[
                  Text(
                    _title!,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                ],
                Html(
                  data: _contentHtml!,
                  style: {
                    'html': Style(
                      margin: Margins.zero,
                      padding: HtmlPaddings.zero,
                    ),
                    'body': Style(
                      margin: Margins.zero,
                      padding: HtmlPaddings.zero,
                      color: colorScheme.onSurface,
                    ),
                    'article': Style(
                      margin: Margins.zero,
                      padding: HtmlPaddings.zero,
                    ),
                    '#mw-content-text': Style(
                      margin: Margins.zero,
                      padding: HtmlPaddings.zero,
                    ),
                    '.mw-body-content': Style(
                      margin: Margins.zero,
                      padding: HtmlPaddings.zero,
                    ),
                    '.toc': Style(display: Display.none),
                    '#toc': Style(display: Display.none),
                    '.navbox': Style(display: Display.none),
                    '.catlinks': Style(display: Display.none),
                    '.mw-editsection': Style(display: Display.none),
                    '.mw-footer': Style(display: Display.none),
                    '.printfooter': Style(display: Display.none),
                    '.mw-authority-control': Style(display: Display.none),
                    '.moe-card-tool': Style(display: Display.none),
                    '.mobile-edit-button': Style(display: Display.none),
                    '.backToTop': Style(display: Display.none),
                    '.reference-edit': Style(display: Display.none),
                    '.mw-jump-link': Style(display: Display.none),
                    '.nomobile': Style(display: Display.none),
                    '.noprint': Style(display: Display.none),
                  },
                  onLinkTap: (url, attributes, element) async {
                    if (url == null || url.trim().isEmpty) {
                      return;
                    }
                    final uri = Uri.tryParse(url.trim());
                    if (uri == null) {
                      return;
                    }
                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                  },
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
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
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
    if (scheme == 'http' || scheme == 'https') {
      return NavigationActionPolicy.ALLOW;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return NavigationActionPolicy.CANCEL;
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
              await launchUrl(uri, mode: LaunchMode.externalApplication);
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
