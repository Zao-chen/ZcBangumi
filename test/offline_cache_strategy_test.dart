import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/constants.dart';
import 'package:zc_bangumi/models/collection.dart';
import 'package:zc_bangumi/models/subject.dart';
import 'package:zc_bangumi/models/user.dart';
import 'package:zc_bangumi/providers/auth_provider.dart';
import 'package:zc_bangumi/providers/collection_provider.dart';
import 'package:zc_bangumi/providers/connectivity_provider.dart';
import 'package:zc_bangumi/services/api_client.dart';
import 'package:zc_bangumi/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageService cache metadata', () {
    test('wraps cache data and touches access metadata on read', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      await storage.setCache('sample', {'value': 1});
      final first = storage.getCacheEntry('sample', touch: false)!;

      expect(first.data, {'value': 1});
      expect(first.accessCount, 0);

      expect(storage.getCache('sample'), {'value': 1});
      final touched = storage.getCacheEntry('sample', touch: false)!;

      expect(touched.accessCount, 1);
      expect(touched.lastAccessedAt.isBefore(first.lastAccessedAt), isFalse);
    });

    test(
      'prunes old cold cache while preserving hot and recent subjects',
      () async {
        final old = DateTime.now().subtract(const Duration(days: 120));
        final subject = _subject(7);
        SharedPreferences.setMockInitialValues({
          'cache_cold': jsonEncode(_entry({'value': 'cold'}, old, 0)),
          'cache_hot': jsonEncode(_entry({'value': 'hot'}, old, 12)),
        });
        final storage = StorageService();
        await storage.init();
        await storage.saveRecentSubjectDetail(subject);
        await storage.setCache('subject_7', subject.toJson());

        final removed = await storage.pruneStaleDataCache();

        expect(removed, 1);
        expect(storage.getCache('cold'), isNull);
        expect(storage.getCache('hot'), {'value': 'hot'});
        expect(storage.getCache('subject_7'), isNotNull);
      },
    );
  });

  group('AuthProvider offline restore', () {
    test('clears auth on 401', () async {
      SharedPreferences.setMockInitialValues({
        'access_token': 'token',
        'username': 'alice',
      });
      final storage = StorageService();
      await storage.init();
      final auth = AuthProvider(
        api: _AuthApi(
          error: DioException(
            requestOptions: RequestOptions(path: '/v0/me'),
            response: Response(
              requestOptions: RequestOptions(path: '/v0/me'),
              statusCode: 401,
            ),
          ),
        ),
        storage: storage,
      );

      await auth.tryRestoreSession();

      expect(auth.isLoggedIn, isFalse);
      expect(auth.canUseAuthenticatedCache, isFalse);
      expect(storage.accessToken, isNull);
      expect(storage.username, isNull);
    });

    test('keeps cached login on network failure', () async {
      SharedPreferences.setMockInitialValues({
        'access_token': 'token',
        'username': 'alice',
      });
      final storage = StorageService();
      await storage.init();
      final connectivity = ConnectivityProvider(
        failureBannerDelay: Duration.zero,
      );
      final auth = AuthProvider(
        api: _AuthApi(
          error: DioException(
            requestOptions: RequestOptions(path: '/v0/me'),
            type: DioExceptionType.connectionError,
            error: 'offline',
          ),
        ),
        storage: storage,
        connectivity: connectivity,
      );

      await auth.tryRestoreSession();

      expect(auth.isLoggedIn, isFalse);
      expect(auth.offlineSession, isTrue);
      expect(auth.canUseAuthenticatedCache, isTrue);
      expect(auth.username, 'alice');
      expect(connectivity.shouldShowBanner, isTrue);
    });
  });

  test(
    'CollectionProvider keeps cached progress list on network failure',
    () async {
      SharedPreferences.setMockInitialValues({'username': 'alice'});
      final storage = StorageService();
      await storage.init();
      final cached = [_collection(1).toJson()];
      await storage.setCache(
        'collections_${BgmConst.subjectAnime}_alice',
        cached,
      );
      final connectivity = ConnectivityProvider(
        failureBannerDelay: Duration.zero,
      );
      final provider = CollectionProvider(
        api: _CollectionApi(
          error: DioException(
            requestOptions: RequestOptions(path: '/collections'),
            type: DioExceptionType.connectionError,
            error: 'offline',
          ),
        ),
        storage: storage,
        connectivity: connectivity,
      );

      await provider.loadDoingCollections(
        username: 'alice',
        subjectType: BgmConst.subjectAnime,
      );

      expect(provider.getCollections(BgmConst.subjectAnime), hasLength(1));
      expect(provider.getError(BgmConst.subjectAnime), isNull);
      expect(connectivity.shouldShowBanner, isTrue);
    },
  );

  test('ConnectivityProvider suppresses transient network failures', () async {
    final connectivity = ConnectivityProvider(
      failureBannerDelay: const Duration(milliseconds: 20),
    );

    connectivity.reportNetworkFailure(
      DioException(
        requestOptions: RequestOptions(path: '/collections'),
        type: DioExceptionType.connectionTimeout,
        error: 'slow request',
      ),
    );
    connectivity.reportNetworkSuccess();

    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(connectivity.shouldShowBanner, isFalse);
    expect(connectivity.usingCache, isFalse);
    connectivity.dispose();
  });
}

Map<String, dynamic> _entry(dynamic data, DateTime accessedAt, int count) => {
  '__cache_meta': {
    'version': 1,
    'createdAt': accessedAt.toIso8601String(),
    'updatedAt': accessedAt.toIso8601String(),
    'lastAccessedAt': accessedAt.toIso8601String(),
    'accessCount': count,
  },
  'data': data,
};

Subject _subject(int id) => Subject(
  id: id,
  type: BgmConst.subjectAnime,
  name: 'Subject $id',
  nameCn: '条目 $id',
  summary: '',
  eps: 12,
  volumes: 0,
  score: 0,
  rank: 0,
  collectionTotal: 0,
  date: '',
  tags: const [],
  infobox: const {},
);

UserCollection _collection(int id) => UserCollection(
  subjectId: id,
  subjectType: BgmConst.subjectAnime,
  rate: 0,
  type: BgmConst.collectionDoing,
  tags: const [],
  epStatus: 0,
  volStatus: 0,
  updatedAt: DateTime(2026),
  private_: false,
  subject: SlimSubject(
    id: id,
    type: BgmConst.subjectAnime,
    name: 'Subject $id',
    nameCn: '条目 $id',
    shortSummary: '',
    eps: 12,
    volumes: 0,
    collectionTotal: 0,
    score: 0,
    rank: 0,
  ),
);

class _AuthApi extends ApiClient {
  final Object? error;

  _AuthApi({this.error});

  @override
  Future<BangumiUser> getMe() async {
    final e = error;
    if (e != null) throw e;
    return BangumiUser(
      id: 1,
      username: 'alice',
      nickname: 'Alice',
      avatar: UserAvatar(large: '', medium: '', small: ''),
      sign: '',
      userGroup: 0,
    );
  }
}

class _CollectionApi extends ApiClient {
  final Object? error;

  _CollectionApi({this.error});

  @override
  Future<PagedResult<UserCollection>> getUserCollections({
    required String username,
    int? subjectType,
    int? collectionType,
    int limit = 30,
    int offset = 0,
  }) async {
    final e = error;
    if (e != null) throw e;
    return PagedResult(total: 0, limit: limit, offset: offset, data: const []);
  }
}
