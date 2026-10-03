import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import '../constants.dart';
import '../models/bangumi_mirror_session.dart';
import '../models/bangumi_mirror_settings.dart';
import 'network_proxy_config.dart';
import 'storage_service.dart';
import 'web_network_config.dart';

enum BangumiConnectionStatus { available, challenge, failed, corsRestricted }

class BangumiConnectionResult {
  const BangumiConnectionResult(this.kind, this.status, this.message);

  final BangumiServiceKind kind;
  final BangumiConnectionStatus status;
  final String message;
}

class BangumiMirrorChallengeException implements Exception {
  const BangumiMirrorChallengeException(this.kind, this.uri);

  final BangumiServiceKind kind;
  final Uri uri;

  @override
  String toString() => '${kind.label}需要人机验证，请前往「设置 → 网络」展开镜像连接详情进行验证';
}

class BangumiEndpointService extends ChangeNotifier {
  BangumiEndpointService({
    StorageService? storage,
    BangumiMirrorSettings? settings,
  }) : _storage = storage {
    _consents.addAll(storage?.bangumiMirrorConsents ?? const []);
    for (final setting in storage?.bangumiMirrorHistory ?? const []) {
      _rememberSettings(setting);
    }
    for (final session
        in storage?.bangumiMirrorSessions ?? <BangumiMirrorSession>[]) {
      _sessions[session.key] = session;
    }
    final initial =
        settings ??
        storage?.bangumiMirrorSettings ??
        const BangumiMirrorSettings();
    try {
      if (initial.isOfficial || _consents.contains(initial.fingerprint)) {
        _settings = initial;
        _settings.endpoints;
      }
    } catch (_) {
      _settings = const BangumiMirrorSettings();
    }
    _rememberSettings(_settings);
    storage?.canonicalizeBangumiCacheData = canonicalizeData;
  }

  final StorageService? _storage;
  BangumiMirrorSettings _settings = const BangumiMirrorSettings();
  final Set<String> _consents = {};
  final List<BangumiMirrorSettings> _knownSettings = [
    const BangumiMirrorSettings(source: BangumiMirrorSource.bangumiVip),
  ];
  final Map<String, BangumiMirrorSession> _sessions = {};
  final Map<BangumiServiceKind, BangumiConnectionResult> _results = {};
  int _generation = 0;
  int _sessionRevision = 0;
  int _sessionEpoch = 0;
  Future<void> _sessionWriteTail = Future<void>.value();
  bool _applying = false;
  BangumiMirrorChallengeException? _lastChallenge;

  BangumiMirrorSettings get settings => _settings;
  int get generation => _generation;
  int get sessionRevision => _sessionRevision;
  BangumiMirrorChallengeException? get lastChallenge => _lastChallenge;
  Map<BangumiServiceKind, BangumiConnectionResult> get results =>
      Map.unmodifiable(_results);
  List<BangumiMirrorSession> get currentSessions => _sessions.values
      .where((session) => session.fingerprint == _settings.fingerprint)
      .toList();
  Set<String> get knownHosts {
    final hosts = <String>{
      'bgm.tv',
      'bangumi.tv',
      'chii.in',
      'www.bgm.tv',
      'www.bangumi.tv',
      'www.chii.in',
    };
    for (final settings in [
      _settings,
      ..._knownSettings,
      const BangumiMirrorSettings(),
    ]) {
      try {
        hosts.addAll(settings.endpoints.values.map((uri) => uri.host));
      } catch (_) {
        continue;
      }
    }
    return hosts;
  }

  bool hasConsent(BangumiMirrorSettings settings) =>
      settings.isOfficial || _consents.contains(settings.fingerprint);

  void _rememberSettings(BangumiMirrorSettings settings) {
    try {
      final fingerprint = settings.fingerprint;
      _knownSettings.removeWhere((entry) => entry.fingerprint == fingerprint);
      _knownSettings.add(settings);
    } catch (_) {
      return;
    }
  }

  Future<T> _enqueueSessionWrite<T>(Future<T> Function() action) async {
    final previous = _sessionWriteTail;
    final completed = Completer<void>();
    _sessionWriteTail = completed.future;
    await previous;
    try {
      return await action();
    } finally {
      completed.complete();
    }
  }

  Future<void> applySettings(
    BangumiMirrorSettings next, {
    bool acceptRisk = false,
  }) async {
    if (_applying) throw StateError('正在保存镜像设置，请稍后重试');
    final fingerprint = next.fingerprint;
    if (!hasConsent(next) && !acceptRisk) {
      throw StateError('必须先确认该镜像的凭据安全风险');
    }
    _applying = true;
    try {
      final consents = {
        ..._consents,
        if (!next.isOfficial && acceptRisk) fingerprint,
      };
      final history = [..._knownSettings, next];
      await _storage?.setBangumiMirrorConsents(consents.toList());
      await _storage?.setBangumiMirrorHistory(history);
      await _storage?.setBangumiMirrorSettings(next);
      _consents.addAll(consents);
      _rememberSettings(next);
      final changed = _settings.fingerprint != fingerprint;
      _settings = next;
      if (changed) {
        _generation++;
        _results.clear();
        _lastChallenge = null;
      }
      notifyListeners();
    } finally {
      _applying = false;
    }
  }

  Uri baseUri(BangumiServiceKind kind) => _settings.endpoints[kind]!;

  static BangumiServiceKind? officialKind(Uri uri) {
    final host = uri.host.toLowerCase();
    if (const {
      'bgm.tv',
      'www.bgm.tv',
      'bangumi.tv',
      'www.bangumi.tv',
      'chii.in',
      'www.chii.in',
    }.contains(host)) {
      return BangumiServiceKind.web;
    }
    for (final kind in BangumiServiceKind.values) {
      if (host == Uri.parse(kind.officialBaseUrl).host) return kind;
    }
    return null;
  }

  BangumiServiceKind? kindForUri(Uri uri, {BangumiServiceKind? preferred}) {
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    final official = officialKind(uri);
    if (official != null && uri.port == (uri.scheme == 'https' ? 443 : 80)) {
      return official;
    }
    for (final settings in [_settings, ..._knownSettings.reversed]) {
      try {
        final matches = settings.endpoints.entries
            .where((entry) => entry.value.origin == uri.origin)
            .map((entry) => entry.key)
            .toList();
        if (matches.isEmpty) continue;
        if (preferred != null && matches.contains(preferred)) return preferred;
        if (uri.path.startsWith('/v0/') &&
            matches.contains(BangumiServiceKind.api)) {
          return BangumiServiceKind.api;
        }
        if (uri.path.startsWith('/p1/') &&
            matches.contains(BangumiServiceKind.next)) {
          return BangumiServiceKind.next;
        }
        if ((uri.path.startsWith('/pic/') || uri.path.startsWith('/r/')) &&
            matches.contains(BangumiServiceKind.lain)) {
          return BangumiServiceKind.lain;
        }
        return matches.first;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Uri canonicalUri(Uri uri, {BangumiServiceKind? preferred}) {
    final kind = kindForUri(uri, preferred: preferred);
    if (kind == null) return uri;
    return _replaceOrigin(uri, Uri.parse(kind.officialBaseUrl));
  }

  Uri resolveUri(Uri uri, {BangumiServiceKind? preferred}) {
    final kind = kindForUri(uri, preferred: preferred);
    if (kind == null) return uri;
    return _replaceOrigin(uri, baseUri(kind));
  }

  String resolveUrl(String url) {
    final raw = url.startsWith('//') ? 'https:$url' : url;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || kindForUri(uri) == null) return url;
    return resolveUri(uri).toString();
  }

  static Uri _replaceOrigin(Uri uri, Uri origin) => uri.replace(
    scheme: origin.scheme,
    host: origin.host,
    port: origin.port,
    userInfo: '',
  );

  dynamic canonicalizeData(dynamic data, {String? field}) {
    if (data is Map) {
      return data.map(
        (key, value) =>
            MapEntry('$key', canonicalizeData(value, field: '$key')),
      );
    }
    if (data is List) {
      return data
          .map((value) => canonicalizeData(value, field: field))
          .toList();
    }
    final urlField =
        field != null &&
        (field.endsWith('Url') ||
            field.endsWith('_url') ||
            const {
              'url',
              'avatar',
              'image',
              'cover',
              'icon',
              'banner',
              'small',
              'medium',
              'large',
              'common',
              'grid',
              'original',
              'userAvatar',
              'href',
              'src',
            }.contains(field));
    if (data is String && urlField) {
      final uri = Uri.tryParse(data.startsWith('//') ? 'https:$data' : data);
      if (uri != null && uri.hasScheme && kindForUri(uri) != null) {
        return canonicalUri(uri).toString();
      }
    }
    return data;
  }

  String rewriteHtml(String html) {
    final document = html_parser.parseFragment(html);
    for (final element in document.querySelectorAll(
      '[src], [href], [data-src], [srcset]',
    )) {
      for (final attribute in const ['src', 'href', 'data-src']) {
        final value = element.attributes[attribute];
        if (value == null || value.startsWith('#')) continue;
        final uri = Uri.tryParse(value);
        if (uri == null) continue;
        final absolute = Uri.parse(BgmConst.webBaseUrl).resolveUri(uri);
        if ((uri.hasScheme || uri.hasAuthority) &&
            kindForUri(absolute) == null) {
          continue;
        }
        element.attributes[attribute] = resolveUri(absolute).toString();
      }
      final srcset = element.attributes['srcset'];
      if (srcset != null &&
          !RegExp(r'(^|[\s,])data:', caseSensitive: false).hasMatch(srcset)) {
        element.attributes['srcset'] = srcset
            .split(',')
            .map((part) {
              final pieces = part.trim().split(RegExp(r'\s+'));
              final candidate = Uri.tryParse(pieces[0]);
              if (candidate != null) {
                final absolute = Uri.parse(
                  BgmConst.webBaseUrl,
                ).resolveUri(candidate);
                if (kindForUri(absolute) != null) {
                  pieces[0] = resolveUri(absolute).toString();
                }
              }
              return pieces.join(' ');
            })
            .join(', ');
      }
    }
    return document.outerHtml;
  }

  bool isActiveOrigin(Uri uri, BangumiServiceKind kind) =>
      uri.origin == baseUri(kind).origin;

  BangumiMirrorSession? sessionFor(Uri uri) => _settings.isOfficial
      ? null
      : _sessions['${_settings.fingerprint}|${uri.origin}'];

  String userAgent(BangumiServiceKind kind) {
    final session = sessionFor(baseUri(kind));
    return session?.userAgent ??
        (kind == BangumiServiceKind.web ||
                kind == BangumiServiceKind.lain ||
                kind == BangumiServiceKind.fast
            ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
            : BgmConst.userAgent);
  }

  Map<String, String> imageHeaders(Uri uri) {
    if (kindForUri(uri) == null ||
        _settings.isOfficial ||
        !hasConsent(_settings)) {
      return {};
    }
    final resolved = resolveUri(uri);
    final session = sessionFor(resolved);
    final cookie = session?.cookieHeader(resolved);
    return {
      if (!kIsWeb)
        'User-Agent': session?.userAgent ?? userAgent(kindForUri(uri)!),
      if (!kIsWeb && cookie != null) 'Cookie': cookie,
    };
  }

  void install(
    Dio dio, {
    BangumiServiceKind? preferredKind,
    bool anonymous = false,
  }) {
    if (dio.interceptors.any(
      (interceptor) =>
          interceptor is _BangumiEndpointInterceptor &&
          identical(interceptor.service, this),
    )) {
      return;
    }
    dio.interceptors.insert(
      0,
      _BangumiEndpointInterceptor(this, dio, preferredKind, anonymous),
    );
  }

  static bool isChallenge(Response<dynamic> response) {
    if (response.headers.value('cf-mitigated') == 'challenge') return true;
    final data = response.data;
    final text = data is String
        ? data
        : data is List<int>
        ? utf8.decode(data, allowMalformed: true)
        : '';
    if (text.isEmpty) return false;
    final sample = text
        .substring(0, text.length > 131072 ? 131072 : text.length)
        .toLowerCase();
    if (!sample.trimLeft().startsWith('<')) return false;
    return sample.contains('id="anubis-main"') ||
        sample.contains("id='anubis-main'") ||
        sample.contains('/.within.website/x/cmd/anubis/') ||
        sample.contains('id="challenge-form"') ||
        RegExp(
          r'<title[^>]*>\s*(just a moment|attention required|正在确认你是不是机器人|verify you are human)',
          caseSensitive: false,
        ).hasMatch(sample);
  }

  Uri probeUri(BangumiServiceKind kind) => baseUri(kind).resolve(switch (kind) {
    BangumiServiceKind.web => '/',
    BangumiServiceKind.api => '/v0/subjects/1',
    BangumiServiceKind.next => '/p1/timeline?limit=1',
    BangumiServiceKind.lain ||
    BangumiServiceKind.fast => '/pic/cover/l/c4/ca/1_d2tF2.jpg',
  });

  Future<BangumiConnectionResult> probe(
    BangumiServiceKind kind, {
    BangumiMirrorSession? session,
    Dio? client,
  }) async {
    final epoch = _generation;
    final uri = probeUri(kind);
    final dio =
        client ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 12),
          ),
        );
    if (client == null) {
      NetworkProxyConfig.installDio(dio);
      WebNetworkConfig.installWebAdapter(dio);
    }
    install(dio, preferredKind: kind);
    BangumiConnectionResult result;
    try {
      final response = await dio.getUri<dynamic>(
        uri,
        options: Options(
          responseType:
              kind == BangumiServiceKind.lain || kind == BangumiServiceKind.fast
              ? ResponseType.bytes
              : ResponseType.plain,
          extra: {
            'bangumiAnonymous': true,
            'bangumiPreferredKind': kind,
            'bangumiProbeSession': session,
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if (isChallenge(response)) {
        result = BangumiConnectionResult(
          kind,
          BangumiConnectionStatus.challenge,
          '需要人机验证',
        );
      } else if (response.statusCode != 200) {
        result = BangumiConnectionResult(
          kind,
          BangumiConnectionStatus.failed,
          'HTTP ${response.statusCode}',
        );
      } else {
        final valid = switch (kind) {
          BangumiServiceKind.api => _validSubject(response.data),
          BangumiServiceKind.next => _validTimeline(response.data),
          BangumiServiceKind.web => _validWebPage(response.data),
          BangumiServiceKind.lain || BangumiServiceKind.fast =>
            response.headers.value('content-type')?.startsWith('image/') ==
                true,
        };
        result = BangumiConnectionResult(
          kind,
          valid
              ? BangumiConnectionStatus.available
              : BangumiConnectionStatus.failed,
          valid ? '可用' : '返回的内容不符合该服务格式',
        );
      }
    } on DioException catch (error) {
      if (error.error is BangumiMirrorChallengeException) {
        result = BangumiConnectionResult(
          kind,
          BangumiConnectionStatus.challenge,
          '需要人机验证',
        );
      } else {
        result = BangumiConnectionResult(
          kind,
          kIsWeb && error.type == DioExceptionType.connectionError
              ? BangumiConnectionStatus.corsRestricted
              : BangumiConnectionStatus.failed,
          kIsWeb ? '连接失败，可能受浏览器跨域策略限制' : '连接失败，请检查网络、代理或镜像地址',
        );
      }
    } catch (_) {
      result = BangumiConnectionResult(
        kind,
        BangumiConnectionStatus.failed,
        '返回的内容不符合该服务格式',
      );
    } finally {
      if (client == null) {
        NetworkProxyConfig.uninstallDio(dio);
        dio.close(force: true);
      }
    }
    if (epoch == _generation) {
      _results[kind] = result;
      notifyListeners();
    }
    return result;
  }

  static dynamic _decoded(dynamic data) =>
      data is String ? jsonDecode(data) : data;
  static bool _validSubject(dynamic data) {
    final value = _decoded(data);
    return value is Map && value['id'] is num && value['name'] is String;
  }

  static bool _validTimeline(dynamic data) => _decoded(data) is List;
  static bool _validWebPage(dynamic data) {
    if (data is! String) return false;
    final document = html_parser.parse(data);
    return document.querySelector('#header, #headerNeue, #headerNeue2') !=
            null &&
        document.querySelector('#wrapper, #wrapperNeue, #main') != null;
  }

  Future<void> saveVerifiedSession(
    BangumiServiceKind kind,
    BangumiMirrorSession session, {
    Dio? client,
  }) async {
    if (_settings.isOfficial ||
        !hasConsent(_settings) ||
        session.fingerprint != _settings.fingerprint ||
        session.origin != baseUri(kind).origin) {
      throw StateError('镜像线路已变更，请重新验证');
    }
    final epoch = _generation;
    final sessionEpoch = _sessionEpoch;
    final result = await probe(kind, session: session, client: client);
    if (epoch != _generation) throw StateError('镜像线路已变更，请重新验证');
    if (result.status != BangumiConnectionStatus.available) {
      throw StateError('客户端复测未通过。请检查系统与应用代理出口是否一致，或重新验证。');
    }
    await _enqueueSessionWrite(() async {
      if (epoch != _generation || sessionEpoch != _sessionEpoch) {
        throw StateError('镜像线路或验证会话已变更，请重新验证');
      }
      final next = {..._sessions, session.key: session};
      await _storage?.setBangumiMirrorSessions(next.values.toList());
      if (epoch != _generation || sessionEpoch != _sessionEpoch) {
        await _storage?.setBangumiMirrorSessions(_sessions.values.toList());
        throw StateError('镜像线路或验证会话已变更，请重新验证');
      }
      _sessions[session.key] = session;
      if (_lastChallenge?.kind == kind) _lastChallenge = null;
      _sessionRevision++;
      notifyListeners();
    });
  }

  Future<void> clearCurrentSessions() async {
    final fingerprint = _settings.fingerprint;
    _sessionEpoch++;
    _sessions.removeWhere((key, value) => value.fingerprint == fingerprint);
    _sessionRevision++;
    _results.clear();
    _lastChallenge = null;
    notifyListeners();
    await _enqueueSessionWrite(() async {
      await _storage?.setBangumiMirrorSessions(_sessions.values.toList());
    });
  }

  void reportChallenge(BangumiMirrorChallengeException challenge) {
    if (_settings.isOfficial) return;
    _lastChallenge = challenge;
    _results[challenge.kind] = BangumiConnectionResult(
      challenge.kind,
      BangumiConnectionStatus.challenge,
      '需要人机验证',
    );
    notifyListeners();
  }

  void dismissChallenge() {
    _lastChallenge = null;
    notifyListeners();
  }
}

class _BangumiEndpointInterceptor extends Interceptor {
  _BangumiEndpointInterceptor(
    this.service,
    this.dio,
    this.preferredKind,
    this.anonymous,
  );

  final BangumiEndpointService service;
  final Dio dio;
  final BangumiServiceKind? preferredKind;
  final bool anonymous;

  static void _removeHeader(RequestOptions options, String name) =>
      options.headers.removeWhere((key, value) => key.toLowerCase() == name);

  DioException _failure(
    RequestOptions options,
    String message, {
    Response<dynamic>? response,
    Object? error,
    DioExceptionType type = DioExceptionType.unknown,
  }) => DioException(
    requestOptions: options,
    response: response,
    type: type,
    error: error,
    message: message,
  );

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final requestKind =
        options.extra['bangumiPreferredKind'] as BangumiServiceKind? ??
        preferredKind;
    final isAnonymous = anonymous || options.extra['bangumiAnonymous'] == true;
    final kind = service.kindForUri(options.uri, preferred: requestKind);
    if (kind == null) {
      _removeHeader(options, 'authorization');
      _removeHeader(options, 'cookie');
      return handler.next(options);
    }
    final epoch = options.extra.putIfAbsent(
      'bangumiGeneration',
      () => service.generation,
    );
    if (epoch != service.generation) {
      return handler.reject(
        _failure(options, '镜像线路已变更，已忽略旧线路请求', type: DioExceptionType.cancel),
      );
    }
    final target = service.resolveUri(options.uri, preferred: requestKind);
    final inlineQuery = Uri.tryParse(options.path)?.query ?? '';
    options.path = target.replace(query: inlineQuery).toString();
    options.baseUrl = '';
    options.extra['bangumiKind'] = kind;
    final allowed =
        service.isActiveOrigin(target, kind) &&
        service.hasConsent(service.settings);
    if (!allowed ||
        isAnonymous ||
        (kind != BangumiServiceKind.api && kind != BangumiServiceKind.next)) {
      _removeHeader(options, 'authorization');
    }
    final session =
        options.extra['bangumiProbeSession'] as BangumiMirrorSession? ??
        (isAnonymous ? null : service.sessionFor(target));
    if (!service.settings.isOfficial ||
        isAnonymous ||
        !allowed ||
        kind != BangumiServiceKind.web) {
      _removeHeader(options, 'cookie');
    }
    if (!kIsWeb && allowed) {
      options.headers['User-Agent'] =
          session?.userAgent ?? service.userAgent(kind);
      if (session?.fingerprint == service.settings.fingerprint &&
          session?.origin == target.origin) {
        final cookie = session?.cookieHeader(target);
        if (cookie != null) options.headers['Cookie'] = cookie;
      }
    }
    if (!service.settings.isOfficial &&
        (kind == BangumiServiceKind.api || kind == BangumiServiceKind.next) &&
        options.responseType == ResponseType.json) {
      options.extra['bangumiDecodeJson'] = true;
      options.responseType = ResponseType.plain;
    }
    for (final key in options.headers.keys.toList()) {
      if (key.toLowerCase() == 'origin' || key.toLowerCase() == 'referer') {
        final uri = Uri.tryParse('${options.headers[key]}');
        if (uri != null) {
          options.headers[key] = service.resolveUri(uri).toString();
        }
      }
    }
    if (!kIsWeb) {
      options.extra.putIfAbsent(
        'bangumiFollowRedirects',
        () => options.followRedirects,
      );
      options.followRedirects = false;
      final original = options.validateStatus;
      options.validateStatus = (status) =>
          (status != null && status >= 300 && status < 400) || original(status);
    }
    handler.next(options);
  }

  bool _stale(RequestOptions options) =>
      options.extra.containsKey('bangumiGeneration') &&
      options.extra['bangumiGeneration'] != service.generation;

  DioException? _challenge(Response<dynamic>? response) {
    if (response == null ||
        response.requestOptions.extra['bangumiKind'] == null ||
        !BangumiEndpointService.isChallenge(response)) {
      return null;
    }
    final challenge = BangumiMirrorChallengeException(
      response.requestOptions.extra['bangumiKind'] as BangumiServiceKind,
      response.requestOptions.uri,
    );
    if (!anonymous &&
        response.requestOptions.extra['bangumiAnonymous'] != true) {
      service.reportChallenge(challenge);
    }
    return _failure(
      response.requestOptions,
      challenge.toString(),
      error: challenge,
    );
  }

  DioException? _invalidApiHtml(Response<dynamic>? response) {
    if (response == null || service.settings.isOfficial) return null;
    final kind = response.requestOptions.extra['bangumiKind'];
    if (kind != BangumiServiceKind.api && kind != BangumiServiceKind.next) {
      return null;
    }
    final contentType = response.headers.value('content-type') ?? '';
    final body = response.data is String ? response.data as String : '';
    final sample = body.substring(0, body.length > 8192 ? 8192 : body.length);
    final looksLikeHtml = RegExp(
      r'^\s*(?:<!--[\s\S]*?-->\s*)*<(?:!doctype\s+html|html\b|head\b|body\b)',
      caseSensitive: false,
    ).hasMatch(sample);
    if (contentType.contains('text/html') || looksLikeHtml) {
      return _failure(response.requestOptions, '镜像返回了网页而非 API 数据，请检查地址或手动验证');
    }
    return null;
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    final options = response.requestOptions;
    if (_stale(options)) {
      return handler.reject(
        _failure(options, '镜像线路已变更，已忽略旧线路响应', type: DioExceptionType.cancel),
      );
    }
    final challenge = _challenge(response);
    if (challenge != null) return handler.reject(challenge);
    final location = response.headers.value('location');
    if (!kIsWeb &&
        location != null &&
        response.statusCode != null &&
        response.statusCode! >= 300 &&
        response.statusCode! < 400 &&
        options.extra['bangumiFollowRedirects'] == true) {
      if (options.method != 'GET' && options.method != 'HEAD') {
        return handler.reject(_failure(options, '写请求发生重定向，请检查镜像后手动重试'));
      }
      final target = service.resolveUri(options.uri.resolve(location));
      final kind = service.kindForUri(target);
      final count = options.extra['bangumiRedirectCount'] as int? ?? 0;
      if (kind == null || !service.isActiveOrigin(target, kind) || count >= 5) {
        return handler.reject(_failure(options, '镜像重定向到未授权地址或跳转次数过多，已停止请求'));
      }
      try {
        final redirectedHeaders = Map<String, dynamic>.from(options.headers)
          ..removeWhere((key, value) => key.toLowerCase() == 'cookie');
        if (kind != BangumiServiceKind.api && kind != BangumiServiceKind.next) {
          redirectedHeaders.removeWhere(
            (key, value) => key.toLowerCase() == 'authorization',
          );
        }
        final redirected = await dio.fetch<dynamic>(
          options.copyWith(
            path: target.toString(),
            baseUrl: '',
            queryParameters: {},
            headers: redirectedHeaders,
            extra: {...options.extra, 'bangumiRedirectCount': count + 1},
          ),
        );
        return handler.resolve(redirected);
      } on DioException catch (error) {
        return handler.reject(error);
      }
    }
    final invalid = _invalidApiHtml(response);
    if (invalid != null) return handler.reject(invalid);
    if (options.extra['bangumiDecodeJson'] == true &&
        (options.extra['bangumiKind'] == BangumiServiceKind.api ||
            options.extra['bangumiKind'] == BangumiServiceKind.next) &&
        response.data is String) {
      try {
        final body = response.data as String;
        final trimmed = body.trimLeft();
        if (Transformer.isJsonMimeType(
              response.headers.value('content-type'),
            ) ||
            trimmed.startsWith('{') ||
            trimmed.startsWith('[')) {
          response.data = body.isEmpty ? null : jsonDecode(body);
        }
      } on Object {
        return handler.reject(_failure(options, '镜像返回的 API 数据格式无效'));
      }
    }
    if (options.extra['bangumiKind'] != null &&
        (response.data is Map ||
            response.data is List && response.data is! List<int>)) {
      response.data = service.canonicalizeData(response.data);
    }
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    if (_stale(error.requestOptions)) {
      return handler.next(
        _failure(
          error.requestOptions,
          '镜像线路已变更，已忽略旧线路响应',
          type: DioExceptionType.cancel,
        ),
      );
    }
    handler.next(
      _challenge(error.response) ?? _invalidApiHtml(error.response) ?? error,
    );
  }
}
