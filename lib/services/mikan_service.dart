import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/mikan.dart';
import 'app_log_service.dart';
import 'network_proxy_config.dart';
import 'web_network_config.dart';

class MikanService {
  static const String defaultBaseUrl = 'https://mikanani.me';
  static const List<String> availableBaseUrls = [
    'https://mikanani.me',
    'https://mikanime.tv',
  ];
  static const String userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36 '
      'ZCBangumi/1.0';

  final Dio _dio;
  String _baseUrl;
  List<MikanSessionCookie> _cookies = const [];

  MikanService({
    Dio? dio,
    String baseUrl = defaultBaseUrl,
    AppLogService? logService,
  }) : _dio = _createDio(dio, logService: logService),
       _baseUrl = _normalizeBaseUrl(baseUrl);

  static Dio _createDio(Dio? dio, {AppLogService? logService}) {
    final client =
        dio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
            responseType: ResponseType.plain,
            headers: {if (!kIsWeb) 'User-Agent': userAgent},
            validateStatus: (status) =>
                status != null && status >= 200 && status < 400,
          ),
        );
    NetworkProxyConfig.installDio(client);
    WebNetworkConfig.installWebAdapter(client);
    if (logService != null) {
      client.interceptors.add(AppLogDioInterceptor(logService));
    }
    return client;
  }

  String get baseUrl => _baseUrl;

  void setBaseUrl(String baseUrl) {
    _baseUrl = _normalizeBaseUrl(baseUrl);
  }

  void setSession(MikanSession? session) {
    _cookies = session?.isValid == true ? session!.cookies : const [];
  }

  Future<MikanSession> login(String username, String password) async {
    final loginUri = _uri('/Account/Login');
    final loginResp = await _get(loginUri);
    final loginHtml = loginResp.data ?? '';
    final token = MikanHtmlParser.parseLoginToken(loginHtml);
    if (token == null || token.isEmpty) {
      throw Exception('Mikan 登录令牌获取失败');
    }

    final formData = {
      'UserName': username,
      'Password': password,
      'RememberMe': 'true',
      '__RequestVerificationToken': token,
    };

    final loginCookie = kIsWeb ? null : _cookieHeaderForUri(loginUri);
    final loginHeaders = <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
      if (!kIsWeb) 'Origin': _baseUrl,
      if (!kIsWeb) 'Referer': loginUri.toString(),
    };
    if (!kIsWeb && loginCookie != null) {
      loginHeaders['Cookie'] = loginCookie;
    }
    final postResp = await _dio.postUri<String>(
      loginUri,
      data: Uri(queryParameters: formData).query,
      options: Options(
        followRedirects: false,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 400,
        headers: loginHeaders,
      ),
    );
    _saveCookiesFromResponse(postResp, loginUri);

    final location = postResp.headers.value('location');
    final validateUri = location == null || location.isEmpty
        ? _uri('/')
        : loginUri.resolve(location);
    final validateResp = await _get(validateUri);
    final validateHtml = validateResp.data ?? '';
    MikanHtmlParser.validateLoginResponse(validateHtml);

    final user = MikanHtmlParser.parseUser(validateHtml, baseUrl: _baseUrl);
    if (user == null || user.name.isEmpty) {
      throw Exception('Mikan 登录失败，请检查账号或密码');
    }

    final now = DateTime.now();
    final session = MikanSession(
      username: user.name,
      capturedAt: now,
      validatedAt: now,
      primaryHost: Uri.parse(_baseUrl).host,
      cookies: List.unmodifiable(_cookies),
    );
    setSession(session);
    return session;
  }

  Future<MikanUser?> getUser() async {
    final resp = await _get(_uri('/'));
    return MikanHtmlParser.parseUser(resp.data ?? '', baseUrl: _baseUrl);
  }

  Future<List<MikanBangumi>> getMySubscribed() async {
    final resp = await _get(_uri('/Home/MyBangumi'));
    return MikanHtmlParser.parseMySubscribed(
      resp.data ?? '',
      baseUrl: _baseUrl,
    );
  }

  Future<MikanSearchResult> search(
    String keyword, {
    String subgroupId = '',
    int page = 1,
  }) async {
    final query = <String, String>{'searchstr': keyword, 'page': '$page'};
    if (subgroupId.isNotEmpty) {
      query['subgroupid'] = subgroupId;
    }
    final resp = await _get(_uri('/Home/Search', query));
    return MikanHtmlParser.parseSearch(resp.data ?? '', baseUrl: _baseUrl);
  }

  Future<MikanBangumiDetail> getBangumi(String bangumiId) async {
    final resp = await _get(_uri('/Home/Bangumi/$bangumiId'));
    return MikanHtmlParser.parseBangumi(
      resp.data ?? '',
      baseUrl: _baseUrl,
      fallbackId: bangumiId,
    );
  }

  Future<void> subscribeBangumi(
    String bangumiId, {
    String subtitleGroupId = '',
  }) async {
    await _postSubscription(
      '/Home/SubscribeBangumi',
      bangumiId,
      subtitleGroupId: subtitleGroupId,
    );
  }

  Future<void> unsubscribeBangumi(
    String bangumiId, {
    String subtitleGroupId = '',
  }) async {
    await _postSubscription(
      '/Home/UnsubscribeBangumi',
      bangumiId,
      subtitleGroupId: subtitleGroupId,
    );
  }

  Future<void> _postSubscription(
    String path,
    String bangumiId, {
    required String subtitleGroupId,
  }) async {
    final data = <String, dynamic>{'BangumiID': bangumiId};
    if (subtitleGroupId.isNotEmpty) {
      data['SubtitleGroupID'] = subtitleGroupId;
    }
    final uri = _uri(path);
    final cookie = kIsWeb ? null : _cookieHeaderForUri(uri);
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (!kIsWeb && cookie != null) {
      headers['Cookie'] = cookie;
    }
    await _dio.postUri<String>(
      uri,
      data: data,
      options: Options(headers: headers),
    );
  }

  Future<Response<String>> _get(Uri uri) async {
    final cookie = kIsWeb ? null : _cookieHeaderForUri(uri);
    final headers = <String, String>{};
    if (!kIsWeb && cookie != null) {
      headers['Cookie'] = cookie;
    }
    final resp = await _dio.getUri<String>(
      uri,
      options: Options(headers: headers),
    );
    _saveCookiesFromResponse(resp, uri);
    return resp;
  }

  Uri _uri(String path, [Map<String, String>? queryParameters]) {
    final base = Uri.parse(_baseUrl);
    final resolved = base.resolve(path);
    if (queryParameters == null || queryParameters.isEmpty) {
      return resolved;
    }
    return resolved.replace(queryParameters: queryParameters);
  }

  String? _cookieHeaderForUri(Uri uri) {
    final matches = _cookies.where((cookie) => cookie.matchesUri(uri)).toList();
    matches.sort((a, b) {
      final pathCompare = b.path.length.compareTo(a.path.length);
      if (pathCompare != 0) return pathCompare;
      return a.name.compareTo(b.name);
    });
    if (matches.isEmpty) return null;
    return matches.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
  }

  void _saveCookiesFromResponse(Response<dynamic> response, Uri uri) {
    final headers = response.headers['set-cookie'];
    if (headers == null || headers.isEmpty) return;
    final next = List<MikanSessionCookie>.from(_cookies);
    for (final header in headers) {
      final cookie = MikanSessionCookie.fromSetCookieHeader(
        header,
        fallbackDomain: uri.host,
      );
      if (cookie.name.isEmpty) continue;
      next.removeWhere(
        (item) =>
            item.name == cookie.name &&
            item.domain == cookie.domain &&
            item.path == cookie.path,
      );
      next.add(cookie);
    }
    _cookies = List.unmodifiable(next);
  }

  static String _normalizeBaseUrl(String baseUrl) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return defaultBaseUrl;
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}

class MikanHtmlParser {
  MikanHtmlParser._();

  static String? parseLoginToken(String html) {
    final document = html_parser.parse(html);
    return _textAttr(
      document.querySelector(
        '#loginForm input[name=__RequestVerificationToken], '
        '#mobileLoginForm input[name=__RequestVerificationToken], '
        '#login input[name=__RequestVerificationToken], '
        'form[action*="/Account/Login"] input[name=__RequestVerificationToken]',
      ),
      'value',
    );
  }

  static void validateLoginResponse(String html) {
    final document = html_parser.parse(html);
    final hasLoginForm =
        document.querySelector('input[name="UserName"]') != null &&
        document.querySelector('input[name="Password"]') != null &&
        document.querySelector(
              'form[action*="/Account/Login"], #loginForm, #login',
            ) !=
            null;
    if (!hasLoginForm) return;

    final message = document
        .querySelectorAll(
          '.validation-summary-errors li, .validation-summary-errors, '
          '.field-validation-error, .text-danger, .js-login-error, .m-login-error',
        )
        .map((e) => _normalizeText(e.text))
        .where((e) => e.isNotEmpty)
        .toSet()
        .join('\n');
    throw Exception(message.isEmpty ? 'Mikan 登录失败，请检查账号或密码' : message);
  }

  static MikanUser? parseUser(String html, {required String baseUrl}) {
    final document = html_parser.parse(html);
    final name = _normalizeText(
      document.querySelector('#user-name .text-right')?.text ?? '',
    );
    final avatar = _resolveUrl(
      baseUrl,
      _textAttr(document.querySelector('#user-welcome #head-pic'), 'src') ?? '',
    );
    final rss = _resolveUrl(
      baseUrl,
      _textAttr(
            document.querySelector('#an-episode-updates .mikan-rss'),
            'href',
          ) ??
          '',
    );
    if (name.isEmpty && avatar.isEmpty && rss.isEmpty) return null;
    return MikanUser(name: name, avatar: avatar, rss: rss);
  }

  static List<MikanBangumi> parseMySubscribed(
    String html, {
    required String baseUrl,
  }) {
    final document = html_parser.parse(html);
    return document
        .querySelectorAll('li')
        .map((li) {
          final span = li.querySelector('span[data-bangumiid]');
          final id = _textAttr(span, 'data-bangumiid') ?? '';
          if (id.isEmpty) return null;
          return MikanBangumi(
            id: id,
            cover: _resolveUrl(
              baseUrl,
              (_textAttr(span, 'data-src') ?? '').split('?').first,
            ),
            name: _normalizeText(
              _textAttr(li.querySelector('.an-text'), 'title') ??
                  _textAttr(li.querySelector('.date-text[title]'), 'title') ??
                  '',
            ),
            subscribed: li.querySelector('.active') != null,
            updateAt: _normalizeText(
              li.querySelector('.date-text')?.text ?? '',
            ),
          );
        })
        .whereType<MikanBangumi>()
        .toList();
  }

  static MikanSearchResult parseSearch(String html, {required String baseUrl}) {
    final document = html_parser.parse(html);
    final subgroups = document
        .querySelectorAll(
          'div.leftbar-container .leftbar-item .subgroup-longname',
        )
        .map(
          (ele) => MikanSubgroup(
            id: _textAttr(ele, 'data-subgroupid') ?? '',
            name: _normalizeText(ele.text),
          ),
        )
        .where((item) => item.id.isNotEmpty || item.name.isNotEmpty)
        .toList();

    final bangumis = document
        .querySelectorAll('div.central-container > ul > li')
        .map((li) {
          final href = _textAttr(li.querySelector('a'), 'href') ?? '';
          final id = href.replaceFirst('/Home/Bangumi/', '').trim();
          if (id.isEmpty) return null;
          final span = li.querySelector('span');
          return MikanBangumi(
            id: id,
            cover: _resolveUrl(
              baseUrl,
              (_textAttr(span, 'data-src') ?? '').split('?').first,
            ),
            name: _normalizeText(
              _textAttr(li.querySelector('.an-text'), 'title') ?? '',
            ),
          );
        })
        .whereType<MikanBangumi>()
        .toList();

    final records = document
        .querySelectorAll('tr.js-search-results-row')
        .map((row) => _parseSearchRecord(row, baseUrl: baseUrl))
        .whereType<MikanRecordItem>()
        .toList();

    return MikanSearchResult(
      bangumis: bangumis,
      subgroups: subgroups,
      records: records,
    );
  }

  static MikanBangumiDetail parseBangumi(
    String html, {
    required String baseUrl,
    String fallbackId = '',
  }) {
    final document = html_parser.parse(html);
    final titleLink = document.querySelector(
      '#sk-container > div.pull-left.leftbar-container > p.bangumi-title > a',
    );
    final href = _textAttr(titleLink, 'href') ?? '';
    final id = RegExp(r'(\d+)').firstMatch(href)?.group(1) ?? fallbackId;
    final posterStyle =
        _textAttr(
          document.querySelector(
            '#sk-container > div.pull-left.leftbar-container > div.bangumi-poster',
          ),
          'style',
        ) ??
        '';
    final cover = _resolveUrl(
      baseUrl,
      RegExp(r"""['"]([^'"]+)['"]""").firstMatch(posterStyle)?.group(1) ?? '',
    );
    final name = _normalizeText(
      document
              .querySelector(
                '#sk-container > div.pull-left.leftbar-container > p.bangumi-title',
              )
              ?.text ??
          '',
    );
    final more = <String, String>{};
    for (final info in document.querySelectorAll(
      '#sk-container > div.pull-left.leftbar-container > p.bangumi-info',
    )) {
      final link = _textAttr(info.querySelector('a'), 'href');
      final text = _normalizeText(info.text);
      final parts = text.split('：');
      if (parts.length >= 2) {
        final key = _normalizeText(parts.first.replaceAll('番组计划链接', '番组计划链接'));
        more[key] = link != null && link.isNotEmpty
            ? _resolveUrl(baseUrl, link)
            : _normalizeText(parts.sublist(1).join('：'));
      }
    }

    final subgroups = <MikanSubgroupBangumi>[];
    final subgroupNodes = document.querySelectorAll('.subgroup-text');
    final tables = document.querySelectorAll(
      '#sk-container > div.central-container > div.episode-table > table',
    );
    for (var i = 0; i < subgroupNodes.length; i++) {
      final subgroup = _parseSubgroupBangumi(
        subgroupNodes[i],
        baseUrl: baseUrl,
      );
      final table = i < tables.length ? tables[i] : null;
      final records = table == null
          ? const <MikanRecordItem>[]
          : table
                .querySelectorAll('tbody > tr')
                .map((row) => _parseRecordItemFromRow(row, baseUrl: baseUrl))
                .whereType<MikanRecordItem>()
                .toList();
      subgroups.add(
        MikanSubgroupBangumi(
          dataId: subgroup.dataId,
          name: subgroup.name,
          subscribed: subgroup.subscribed,
          sublang: subgroup.sublang,
          rss: subgroup.rss,
          state: subgroup.state,
          subgroups: subgroup.subgroups,
          records: records,
        ),
      );
    }

    return MikanBangumiDetail(
      id: id,
      name: name,
      cover: cover,
      intro: _normalizeText(
        document
                .querySelector('#sk-container > div.central-container > p')
                ?.text ??
            '',
      ),
      subscribed:
          document.querySelector('#sk-container .subscribed-badge') != null,
      more: more,
      subgroupBangumis: subgroups,
    );
  }

  static MikanSubgroupBangumi _parseSubgroupBangumi(
    dom.Element sub, {
    required String baseUrl,
  }) {
    var name = _normalizeText(
      sub.querySelector('a[href*="/Home/PublishGroup/"]')?.text ?? '',
    );
    if (name.isEmpty) {
      name = _normalizeText(sub.querySelector('.dropdown span')?.text ?? '');
    }
    if (name.isEmpty) {
      final clone = sub.clone(true);
      clone
          .querySelectorAll(
            '.mikan-rss, .subscribed, .dropdown, script, style, i',
          )
          .forEach((element) => element.remove());
      name = _normalizeText(clone.text);
    }
    if (name.isEmpty) {
      name = '生肉/不明字幕';
    }

    final subscribedNode = sub.querySelector('.subscribed');
    final subscribed =
        subscribedNode != null && subscribedNode.attributes['style'] == null;
    final sublang = subscribed ? _normalizeText(subscribedNode.text) : '';
    final state = subscribed
        ? sublang == '简中'
              ? 1
              : sublang == '繁中'
              ? 2
              : 0
        : -1;

    final subgroups = sub
        .querySelectorAll('a[href*="/Home/PublishGroup/"]')
        .map(
          (a) => MikanSubgroup(
            id: (_textAttr(a, 'href') ?? '').split('/').last,
            name: _normalizeText(a.text),
          ),
        )
        .where((item) => item.id.isNotEmpty || item.name.isNotEmpty)
        .toList();

    return MikanSubgroupBangumi(
      dataId: _textAttr(sub, 'id') ?? '',
      name: name,
      subscribed: subscribed,
      sublang: sublang,
      rss: _resolveUrl(
        baseUrl,
        _textAttr(sub.querySelector('.mikan-rss'), 'href') ?? '',
      ),
      state: state,
      subgroups: subgroups,
    );
  }

  static MikanRecordItem? _parseSearchRecord(
    dom.Element row, {
    required String baseUrl,
  }) {
    final cells = row.children;
    if (cells.length < 5) return null;
    final link = cells[1].querySelector('a');
    final titleText = _normalizeText(link?.text ?? '');
    final parsed = _parseTagsAndTitle(titleText);
    return MikanRecordItem(
      title: parsed.title,
      tags: parsed.tags,
      url: _resolveUrl(baseUrl, _textAttr(link, 'href') ?? ''),
      size: _normalizeText(cells[2].text),
      publishAt: _normalizeText(cells[3].text),
      torrent: _resolveUrl(
        baseUrl,
        _textAttr(cells[4].querySelector('a'), 'href') ?? '',
      ),
    );
  }

  static MikanRecordItem? _parseRecordItemFromRow(
    dom.Element row, {
    required String baseUrl,
  }) {
    final cells = row.children;
    if (cells.length < 4) return null;
    final firstCell = cells.length >= 5 ? cells[1] : cells[0];
    final link =
        firstCell.querySelector('a.magnet-link-wrap') ??
        firstCell.querySelector('a');
    final magnet =
        _textAttr(
          firstCell.querySelector('[data-clipboard-text]'),
          'data-clipboard-text',
        ) ??
        _textAttr(cells.first.querySelector('[data-magnet]'), 'data-magnet') ??
        '';
    final parsed = _parseTagsAndTitle(_normalizeText(link?.text ?? ''));
    final sizeCell = cells.length >= 5 ? cells[2] : cells[1];
    final dateCell = cells.length >= 5 ? cells[3] : cells[2];
    final torrentCell = cells.length >= 5 ? cells[4] : cells[3];

    return MikanRecordItem(
      magnet: magnet,
      title: parsed.title,
      tags: parsed.tags,
      url: _resolveUrl(baseUrl, _textAttr(link, 'href') ?? ''),
      size: _normalizeText(sizeCell.text),
      publishAt: _normalizeText(dateCell.text),
      torrent: _resolveUrl(
        baseUrl,
        _textAttr(torrentCell.querySelector('a'), 'href') ?? '',
      ),
    );
  }

  static _ParsedTitle _parseTagsAndTitle(String text) {
    final tags = <String>{};
    for (final match in RegExp(r'\[([^\]]+)\]').allMatches(text)) {
      final raw = match.group(1)?.trim() ?? '';
      final upper = raw.toUpperCase();
      if (upper == 'GB' || upper == 'CHS' || raw == '简中') {
        tags.add('简');
      } else if (upper == 'BIG5' || upper == 'CHT' || raw == '繁中') {
        tags.add('繁');
      } else if (RegExp(r'^\d{3,4}P$').hasMatch(upper) ||
          const {'MP4', 'MKV', 'AVI', 'HEVC', 'AVC'}.contains(upper)) {
        tags.add(upper);
      } else if (raw.contains('特别篇') || upper == 'SP') {
        tags.add(raw.contains('特别篇') ? '特别篇' : 'SP');
      }
    }
    return _ParsedTitle(title: text, tags: tags.toList()..sort());
  }

  static String _normalizeText(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String? _textAttr(dom.Element? element, String name) {
    return element?.attributes[name]?.trim();
  }

  static String _resolveUrl(String baseUrl, String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('magnet:')) return trimmed;
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    return Uri.parse(baseUrl).resolve(trimmed).toString();
  }
}

class _ParsedTitle {
  final String title;
  final List<String> tags;

  const _ParsedTitle({required this.title, required this.tags});
}
