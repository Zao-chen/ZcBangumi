import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/models/bangumi_mirror_session.dart';
import 'package:zc_bangumi/models/bangumi_mirror_settings.dart';
import 'package:zc_bangumi/models/bangumi_web_session.dart';
import 'package:zc_bangumi/providers/auth_provider.dart';
import 'package:zc_bangumi/providers/connectivity_provider.dart';
import 'package:zc_bangumi/services/api_client.dart';
import 'package:zc_bangumi/services/bangumi_endpoint_service.dart';
import 'package:zc_bangumi/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BangumiEndpointService endpoints;
  late ApiClient api;

  setUp(() async {
    endpoints = BangumiEndpointService();
    await endpoints.applySettings(
      const BangumiMirrorSettings(source: BangumiMirrorSource.bangumiVip),
      acceptRisk: true,
    );
    api = ApiClient(endpoints: endpoints);
  });

  tearDown(() {
    api.dispose();
    endpoints.dispose();
  });

  test(
    'all three clients route and keep parameters and credential roles',
    () async {
      final adapter = RecordingAdapter(
        (options) =>
            jsonBody({'id': 1, 'image_url': 'https://lain.bangumi.vip/a.jpg'}),
      );
      api.dio.httpClientAdapter = adapter;
      api.nextDio.httpClientAdapter = adapter;
      api.webDio.httpClientAdapter = adapter;
      api.setToken('synthetic-token');
      api.setWebCookie('chii_auth=official-cookie');
      final response = await api.dio.get(
        '/v0/subjects/1',
        queryParameters: {'limit': 3},
      );
      await api.nextDio.get('/p1/timeline');
      await api.webDio.get(
        'https://bgm.tv/subject/1',
        options: Options(
          headers: {
            'Origin': 'https://bgm.tv',
            'Referer': 'https://bgm.tv/subject/1',
          },
        ),
      );
      expect(adapter.requests.map((request) => request.uri.host), [
        'api.bangumi.vip',
        'next.bangumi.vip',
        'bangumi.vip',
      ]);
      expect(adapter.requests.first.queryParameters['limit'], 3);
      expect(
        adapter.requests.first.headers['Authorization'],
        'Bearer synthetic-token',
      );
      expect(
        adapter.requests[1].headers['Authorization'],
        'Bearer synthetic-token',
      );
      expect(adapter.requests.last.headers['Authorization'], isNull);
      expect(adapter.requests.last.headers['Cookie'], isNull);
      expect(adapter.requests.last.headers['Origin'], 'https://bangumi.vip');
      expect(
        adapter.requests.last.headers['Referer'],
        'https://bangumi.vip/subject/1',
      );
      expect(response.data['image_url'], 'https://lain.bgm.tv/a.jpg');
      await endpoints.applySettings(const BangumiMirrorSettings());
      await api.dio.get('/v0/subjects/1');
      expect(adapter.requests.last.uri.host, 'api.bgm.tv');
    },
  );

  test(
    'updates and other non-Bangumi URLs are untouched and carry no credentials',
    () async {
      final adapter = RecordingAdapter((options) => jsonBody({'ok': true}));
      api.dio.httpClientAdapter = adapter;
      api.setToken('synthetic-token');
      await api.dio.get('https://api.github.com/repos/test/test/releases');
      final request = adapter.requests.single;
      expect(request.uri.host, 'api.github.com');
      expect(request.headers['Authorization'], isNull);
      expect(request.headers['Cookie'], isNull);
      expect(request.followRedirects, isTrue);
    },
  );

  test('untrusted redirects are not followed or given credentials', () async {
    final adapter = RecordingAdapter(
      (options) => ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': ['https://evil.example/v0/me'],
        },
      ),
    );
    api.dio.httpClientAdapter = adapter;
    api.setToken('synthetic-token');
    await expectLater(
      api.dio.get('/v0/me'),
      throwsA(
        isA<DioException>().having(
          (error) => error.message,
          'message',
          contains('未授权'),
        ),
      ),
    );
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.followRedirects, isFalse);
  });

  test(
    'safe GET redirect to official URL remains on the selected mirror',
    () async {
      final adapter = RecordingAdapter(
        (options) => options.uri.path.endsWith('/first')
            ? ResponseBody.fromString(
                '',
                302,
                headers: {
                  'location': ['https://api.bgm.tv/v0/second?q=1'],
                },
              )
            : jsonBody({'ok': true}),
      );
      api.dio.httpClientAdapter = adapter;
      await api.dio.get('/v0/first');
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.last.uri.toString(),
        'https://api.bangumi.vip/v0/second?q=1',
      );
    },
  );

  test('redirecting from API to web does not carry the API token', () async {
    final adapter = RecordingAdapter(
      (options) => options.uri.host == 'api.bangumi.vip'
          ? ResponseBody.fromString(
              '',
              302,
              headers: {
                'location': ['https://bgm.tv/subject/1'],
              },
            )
          : ResponseBody.fromString(
              '<html><div id="header"></div><div id="wrapper"></div></html>',
              200,
              headers: {
                'content-type': ['text/html'],
              },
            ),
    );
    api.dio.httpClientAdapter = adapter;
    api.setToken('synthetic-token');

    await api.dio.get('/v0/redirect');

    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.last.uri.host, 'bangumi.vip');
    expect(adapter.requests.last.headers['Authorization'], isNull);
  });

  test('mutation redirects and challenge pages never replay writes', () async {
    for (final response in [
      ResponseBody.fromString(
        '',
        307,
        headers: {
          'location': ['/v0/other'],
        },
      ),
      challengeBody(200),
    ]) {
      final adapter = RecordingAdapter((options) => response);
      api.dio.httpClientAdapter = adapter;
      await expectLater(
        api.dio.patch('/v0/progress', data: {'status': 2}),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requests, hasLength(1));
    }
  });

  test('an old response is cancelled after switching endpoints', () async {
    final response = Completer<ResponseBody>();
    final started = Completer<void>();
    final adapter = RecordingAdapter((options) {
      started.complete();
      return response.future;
    });
    api.dio.httpClientAdapter = adapter;
    final pending = api.dio.get('/v0/subjects/1');
    final assertion = expectLater(
      pending,
      throwsA(
        isA<DioException>().having(
          (error) => error.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
    await started.future;
    await endpoints.applySettings(const BangumiMirrorSettings());
    response.complete(jsonBody({'id': 1, 'name': 'old'}));
    await assertion;
  });

  test('200 and 403 challenge pages are not authentication expiry', () async {
    for (final status in [200, 403]) {
      final adapter = RecordingAdapter((options) => challengeBody(status));
      api.dio.httpClientAdapter = adapter;
      try {
        await api.dio.get('/v0/me');
        fail('challenge should fail before parsing');
      } on DioException catch (error) {
        expect(error.error, isA<BangumiMirrorChallengeException>());
        expect(ConnectivityProvider.isAuthExpired(error), isFalse);
      }
    }
  });

  test(
    'challenge during session restoration keeps the saved account token',
    () async {
      SharedPreferences.setMockInitialValues({
        'access_token': 'saved-token',
        'username': 'tester',
      });
      final storage = StorageService();
      await storage.init();
      api.dio.httpClientAdapter = RecordingAdapter(
        (options) => challengeBody(403),
      );
      final auth = AuthProvider(api: api, storage: storage);
      await auth.tryRestoreSession();
      expect(storage.accessToken, 'saved-token');
      expect(storage.username, 'tester');
      expect(api.hasToken, isTrue);
    },
  );

  test(
    'HTML API error without known challenge markers does not delete Token',
    () async {
      api.dio.httpClientAdapter = RecordingAdapter(
        (options) => ResponseBody.fromString(
          '<html>denied</html>',
          403,
          headers: {
            'content-type': ['text/html'],
          },
        ),
      );
      try {
        await api.dio.get('/v0/me');
        fail('HTML cannot be interpreted as an API response');
      } on DioException catch (error) {
        expect(ConnectivityProvider.isAuthExpired(error), isFalse);
      }
    },
  );

  test(
    'an HTML 200 response without a content type is not parsed as API data',
    () async {
      api.dio.httpClientAdapter = RecordingAdapter(
        (options) =>
            ResponseBody.fromString('<html><body>blocked</body></html>', 200),
      );
      await expectLater(
        api.dio.get('/v0/me'),
        throwsA(
          isA<DioException>().having(
            (error) => error.message,
            'message',
            contains('网页而非 API 数据'),
          ),
        ),
      );
    },
  );

  test(
    'anonymous probes strip credentials, validate JSON, and detect challenges',
    () async {
      final adapter = RecordingAdapter(
        (options) => jsonBody({'id': 1, 'name': 'public'}),
      );
      final client = Dio(
        BaseOptions(
          headers: {'Authorization': 'secret', 'Cookie': 'chii_auth=secret'},
        ),
      )..httpClientAdapter = adapter;
      final result = await endpoints.probe(
        BangumiServiceKind.api,
        client: client,
      );
      expect(result.status, BangumiConnectionStatus.available);
      expect(adapter.requests.single.headers['Authorization'], isNull);
      expect(adapter.requests.single.headers['Cookie'], isNull);
      final invalid = Dio()
        ..httpClientAdapter = RecordingAdapter(
          (options) => jsonBody({'error': 'not a subject'}),
        );
      expect(
        (await endpoints.probe(BangumiServiceKind.api, client: invalid)).status,
        BangumiConnectionStatus.failed,
      );
      final blocked = Dio()
        ..httpClientAdapter = RecordingAdapter((options) => challengeBody(200));
      expect(
        (await endpoints.probe(BangumiServiceKind.web, client: blocked)).status,
        BangumiConnectionStatus.challenge,
      );
    },
  );

  test(
    'web probes accept the current Bangumi homepage layout on both routes',
    () async {
      const homepage = '''
<!DOCTYPE html><html><head><title>Bangumi 番组计划</title></head><body>
<div id="wrapperNeue" class="wrapperNeue">
  <div id="headerNeue2"></div>
  <div id="main" class="mainWrapper"></div>
</div></body></html>''';
      for (final source in [
        BangumiMirrorSource.official,
        BangumiMirrorSource.bangumiVip,
      ]) {
        await endpoints.applySettings(BangumiMirrorSettings(source: source));
        final adapter = RecordingAdapter(
          (options) => ResponseBody.fromString(
            homepage,
            200,
            headers: {
              'content-type': ['text/html'],
            },
          ),
        );
        final result = await endpoints.probe(
          BangumiServiceKind.web,
          client: Dio()..httpClientAdapter = adapter,
        );
        expect(
          result.status,
          BangumiConnectionStatus.available,
          reason: source.name,
        );
        expect(adapter.requests.single.headers['Authorization'], isNull);
        expect(adapter.requests.single.headers['Cookie'], isNull);
      }
    },
  );

  test(
    'web probes still reject unrelated HTML and detect verification pages',
    () async {
      final cases = <String, BangumiConnectionStatus>{
        '<html><title>Bangumi</title><body>Network error</body></html>':
            BangumiConnectionStatus.failed,
        '<html><div id="headerNeue2"></div></html>':
            BangumiConnectionStatus.failed,
        '<html><div id="wrapperNeue"></div><div id="main"></div></html>':
            BangumiConnectionStatus.failed,
        '<html><div id="headerNeue2"></div><div id="main"></div>'
                '<div id="anubis-main">Verify</div></html>':
            BangumiConnectionStatus.challenge,
      };
      for (final entry in cases.entries) {
        final result = await endpoints.probe(
          BangumiServiceKind.web,
          client: Dio()
            ..httpClientAdapter = RecordingAdapter(
              (options) => ResponseBody.fromString(
                entry.key,
                200,
                headers: {
                  'content-type': ['text/html'],
                },
              ),
            ),
        );
        expect(result.status, entry.value);
      }
    },
  );

  test(
    'a verified session is scoped, persisted, and is not used by anonymous probes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final service = BangumiEndpointService(storage: storage);
      await service.applySettings(
        const BangumiMirrorSettings(source: BangumiMirrorSource.bangumiVip),
        acceptRisk: true,
      );
      final session = BangumiMirrorSession(
        fingerprint: service.settings.fingerprint,
        origin: 'https://bangumi.vip',
        userAgent: 'matching-test-user-agent',
        cookies: const [
          BangumiWebSessionCookie(
            name: 'validation',
            value: 'verified',
            domain: 'bangumi.vip',
            path: '/',
          ),
        ],
      );
      final probeAdapter = RecordingAdapter(
        (options) => ResponseBody.fromString(
          '<html><div id="header"></div><div id="wrapper"></div></html>',
          200,
          headers: {
            'content-type': ['text/html'],
          },
        ),
      );
      await service.saveVerifiedSession(
        BangumiServiceKind.web,
        session,
        client: Dio()..httpClientAdapter = probeAdapter,
      );
      expect(
        probeAdapter.requests.single.headers['Cookie'],
        'validation=verified',
      );
      expect(
        probeAdapter.requests.single.headers['User-Agent'],
        session.userAgent,
      );
      final restored = BangumiEndpointService(storage: storage);
      expect(restored.sessionFor(Uri.parse('https://bangumi.vip')), isNotNull);
      expect(restored.sessionFor(Uri.parse('https://api.bangumi.vip')), isNull);
      final client = ApiClient(endpoints: restored);
      final adapter = RecordingAdapter(
        (options) => ResponseBody.fromString('ok', 200),
      );
      client.webDio.httpClientAdapter = adapter;
      await client.webDio.get('/subject/1');
      expect(adapter.requests.single.headers['Cookie'], 'validation=verified');
      final anonymous = Dio()..httpClientAdapter = probeAdapter;
      await restored.probe(BangumiServiceKind.web, client: anonymous);
      expect(probeAdapter.requests.last.headers['Cookie'], isNull);
      await restored.clearCurrentSessions();
      expect(restored.currentSessions, isEmpty);
      expect(storage.bangumiMirrorSessions, isEmpty);
    },
  );

  test('failed verification never stores the candidate session', () async {
    final session = BangumiMirrorSession(
      fingerprint: endpoints.settings.fingerprint,
      origin: 'https://bangumi.vip',
      userAgent: 'test',
      cookies: const [],
    );
    await expectLater(
      endpoints.saveVerifiedSession(
        BangumiServiceKind.web,
        session,
        client: Dio()
          ..httpClientAdapter = RecordingAdapter(
            (options) => challengeBody(200),
          ),
      ),
      throwsStateError,
    );
    expect(endpoints.currentSessions, isEmpty);
  });

  test(
    'repeated anonymous probes do not alter an authenticated client',
    () async {
      final adapter = RecordingAdapter(
        (options) => jsonBody({'id': 1, 'name': 'public'}),
      );
      api.dio.httpClientAdapter = adapter;
      api.setToken('synthetic-token');
      final interceptorCount = api.dio.interceptors.length;
      for (var count = 0; count < 2; count++) {
        final result = await endpoints.probe(
          BangumiServiceKind.api,
          client: api.dio,
        );
        expect(result.status, BangumiConnectionStatus.available);
        expect(adapter.requests.last.headers['Authorization'], isNull);
      }
      expect(api.dio.interceptors.length, interceptorCount);
      await api.dio.get('/v0/me');
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer synthetic-token',
      );
    },
  );

  test(
    'official host-less cookies cannot reach mirrors or public API',
    () async {
      final adapter = RecordingAdapter((options) => jsonBody({'id': 1}));
      api.dio.httpClientAdapter = adapter;
      api.webDio.httpClientAdapter = adapter;
      api.setWebSession(
        BangumiWebSession(
          username: 'tester',
          uid: 1,
          capturedAt: DateTime.now(),
          validatedAt: DateTime.now(),
          primaryHost: 'bgm.tv',
          cookies: const [
            BangumiWebSessionCookie(
              name: 'chii_auth',
              value: 'official-only',
              domain: '',
              path: '/',
            ),
          ],
        ),
      );
      await api.webDio.get('/subject/1');
      expect(adapter.requests.last.headers['Cookie'], isNull);
      await api.webDio.get('https://external.example/');
      expect(adapter.requests.last.headers['Cookie'], isNull);
      await endpoints.applySettings(const BangumiMirrorSettings());
      api.setWebCookie('chii_auth=official-only');
      await api.webDio.get('https://api.bgm.tv/v0/subjects/1');
      expect(adapter.requests.last.headers['Cookie'], isNull);
      await endpoints.probe(BangumiServiceKind.web, client: api.webDio);
      expect(adapter.requests.last.headers['Cookie'], isNull);
      await api.webDio.get('/');
      expect(
        adapter.requests.last.headers['Cookie'],
        contains('official-only'),
      );
    },
  );

  test(
    'mislabeled JSON challenges are recognized before JSON decoding',
    () async {
      api.dio.httpClientAdapter = RecordingAdapter(
        (options) => ResponseBody.fromString(
          '<html><div id="anubis-main">verify</div></html>',
          200,
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );
      await expectLater(
        api.dio.get('/v0/me'),
        throwsA(
          isA<DioException>().having(
            (error) => error.error,
            'challenge',
            isA<BangumiMirrorChallengeException>(),
          ),
        ),
      );
    },
  );

  test(
    'valid JSON can contain HTML without being mistaken for a challenge',
    () async {
      api.dio.httpClientAdapter = RecordingAdapter(
        (options) => jsonBody({
          'id': 1,
          'content': "<html><div id='anubis-main'>quoted markup</div></html>",
        }),
      );
      final response = await api.dio.get('/v0/subjects/1');
      expect(response.data['id'], 1);
      expect(endpoints.lastChallenge, isNull);
    },
  );

  test(
    'clearing sessions invalidates a pending successful verification',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final service = BangumiEndpointService(storage: storage);
      await service.applySettings(
        const BangumiMirrorSettings(source: BangumiMirrorSource.bangumiVip),
        acceptRisk: true,
      );
      final started = Completer<void>();
      final response = Completer<ResponseBody>();
      final candidate = BangumiMirrorSession(
        fingerprint: service.settings.fingerprint,
        origin: service.baseUri(BangumiServiceKind.api).origin,
        userAgent: 'test',
        cookies: const [],
      );
      final pending = service.saveVerifiedSession(
        BangumiServiceKind.api,
        candidate,
        client: Dio()
          ..httpClientAdapter = RecordingAdapter((options) {
            started.complete();
            return response.future;
          }),
      );
      final assertion = expectLater(pending, throwsStateError);
      await started.future;
      await service.clearCurrentSessions();
      response.complete(jsonBody({'id': 1, 'name': 'public'}));
      await assertion;
      expect(service.currentSessions, isEmpty);
      expect(storage.bangumiMirrorSessions, isEmpty);
      service.dispose();
    },
  );

  test('simultaneous verification saves keep both service sessions', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final service = BangumiEndpointService(storage: storage);
    await service.applySettings(
      const BangumiMirrorSettings(source: BangumiMirrorSource.bangumiVip),
      acceptRisk: true,
    );
    await Future.wait(
      [BangumiServiceKind.api, BangumiServiceKind.next].map(
        (kind) => service.saveVerifiedSession(
          kind,
          BangumiMirrorSession(
            fingerprint: service.settings.fingerprint,
            origin: service.baseUri(kind).origin,
            userAgent: 'test',
            cookies: const [],
          ),
          client: Dio()
            ..httpClientAdapter = RecordingAdapter(
              (options) => jsonBody(
                kind == BangumiServiceKind.api
                    ? {'id': 1, 'name': 'public'}
                    : [],
              ),
            ),
        ),
      ),
    );
    expect(service.currentSessions, hasLength(2));
    expect(storage.bangumiMirrorSessions, hasLength(2));
    service.dispose();
  });
}

class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(dynamic data) => ResponseBody.fromString(
  jsonEncode(data),
  200,
  headers: {
    'content-type': ['application/json'],
  },
);
ResponseBody challengeBody(int status) => ResponseBody.fromString(
  '<html><title>正在确认你是不是机器人！</title><div id="anubis-main">verify</div></html>',
  status,
  headers: {
    'content-type': ['text/html'],
  },
);
