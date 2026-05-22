import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/models/mikan.dart';
import 'package:zc_bangumi/models/subject.dart';
import 'package:zc_bangumi/providers/mikan_provider.dart';
import 'package:zc_bangumi/services/mikan_service.dart';
import 'package:zc_bangumi/services/storage_service.dart';

class _FakeMikanService extends MikanService {
  int getUserCalls = 0;
  int subscribedCalls = 0;
  int searchCalls = 0;
  int detailCalls = 0;
  int subscribeCalls = 0;
  bool throwOnSubscribe = false;

  _FakeMikanService() : super(baseUrl: MikanService.defaultBaseUrl);

  @override
  Future<MikanUser?> getUser() async {
    getUserCalls++;
    return const MikanUser(name: 'tester');
  }

  @override
  Future<List<MikanBangumi>> getMySubscribed() async {
    subscribedCalls++;
    return [MikanBangumi(id: '$subscribedCalls', name: '订阅 $subscribedCalls')];
  }

  @override
  Future<MikanSearchResult> search(
    String keyword, {
    String subgroupId = '',
    int page = 1,
  }) async {
    searchCalls++;
    return const MikanSearchResult();
  }

  @override
  Future<MikanBangumiDetail> getBangumi(String bangumiId) async {
    detailCalls++;
    return MikanBangumiDetail(
      id: bangumiId,
      name: '测试动画',
      subgroupBangumis: const [
        MikanSubgroupBangumi(dataId: '99', name: '旧字幕组'),
        MikanSubgroupBangumi(dataId: '15', name: '字幕组', subscribed: true),
      ],
    );
  }

  @override
  Future<void> subscribeBangumi(
    String bangumiId, {
    String subtitleGroupId = '',
  }) async {
    subscribeCalls++;
    if (throwOnSubscribe) {
      throw Exception('subscribe failed');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<StorageService> storageWithSession() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await storage.setMikanSession(
      MikanSession(
        username: 'tester',
        capturedAt: DateTime(2026, 5, 21),
        validatedAt: DateTime(2026, 5, 21),
        primaryHost: 'mikanani.me',
        cookies: const [
          MikanSessionCookie(
            name: 'session',
            value: 'ok',
            domain: 'mikanani.me',
            path: '/',
          ),
        ],
      ),
    );
    return storage;
  }

  test('restores saved Mikan session', () async {
    final storage = await storageWithSession();
    final service = _FakeMikanService();
    final provider = MikanProvider(service: service, storage: storage);

    await provider.tryRestoreSession();

    expect(provider.isLoggedIn, isTrue);
    expect(provider.user?.name, 'tester');
    expect(service.getUserCalls, 1);
  });

  test('Mikan feature is enabled by default and can be disabled', () async {
    final storage = await storageWithSession();
    final service = _FakeMikanService();
    final provider = MikanProvider(service: service, storage: storage);

    expect(provider.isEnabled, isTrue);

    await provider.setEnabled(false);
    await provider.tryRestoreSession();

    expect(provider.isEnabled, isFalse);
    expect(service.getUserCalls, 0);
  });

  test('successful subscribe invalidates subscribed cache', () async {
    final storage = await storageWithSession();
    final service = _FakeMikanService();
    final provider = MikanProvider(service: service, storage: storage);
    await provider.tryRestoreSession();

    final first = await provider.getSubscribed();
    await provider.syncSubscription(
      mapping: MikanSubjectMapping(
        subjectId: 1,
        bangumiId: '681',
        bangumiName: '测试动画',
        subgroupId: '15',
        subgroupName: '字幕组',
        updatedAt: DateTime(2026, 5, 21),
      ),
      subscribe: true,
    );
    final second = await provider.getSubscribed();

    expect(first.single.id, '1');
    expect(second.single.id, '2');
    expect(service.subscribeCalls, 1);
  });

  test('saved mapping is refreshed from Mikan without searching', () async {
    final storage = await storageWithSession();
    final service = _FakeMikanService();
    final provider = MikanProvider(service: service, storage: storage);
    final mapping = MikanSubjectMapping(
      subjectId: 12345,
      bangumiId: '681',
      bangumiName: '测试动画',
      subgroupId: '99',
      subgroupName: '旧字幕组',
      updatedAt: DateTime(2026, 5, 21),
    );
    await provider.saveMapping(mapping);

    final resolved = await provider.findExactMapping(
      Subject(
        id: 12345,
        type: 2,
        name: 'test',
        nameCn: '测试动画',
        summary: '',
        eps: 12,
        volumes: 0,
        score: 0,
        rank: 0,
        collectionTotal: 0,
        date: '',
        tags: const [],
        infobox: const {},
      ),
    );

    expect(resolved?.bangumiId, '681');
    expect(resolved?.subgroupId, '15');
    expect(resolved?.subgroupName, '字幕组');
    expect(resolved?.subscribed, isTrue);
    expect(service.searchCalls, 0);
    expect(service.detailCalls, 1);
  });
}
