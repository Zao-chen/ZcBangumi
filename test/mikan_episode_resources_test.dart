import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/models/episode.dart';
import 'package:zc_bangumi/models/mikan.dart';
import 'package:zc_bangumi/models/subject.dart';
import 'package:zc_bangumi/providers/mikan_provider.dart';
import 'package:zc_bangumi/services/mikan_service.dart';
import 'package:zc_bangumi/services/storage_service.dart';
import 'package:zc_bangumi/widgets/subject_action_buttons.dart';
import 'package:zc_bangumi/widgets/progress_grid.dart';

class _EpisodeResourceMikanService extends MikanService {
  _EpisodeResourceMikanService() : super();

  @override
  Future<MikanBangumiDetail> getBangumi(String bangumiId) async {
    return const MikanBangumiDetail(
      id: '681',
      name: '测试动画',
      subgroupBangumis: [
        MikanSubgroupBangumi(
          dataId: '15',
          name: '测试字幕组',
          records: [
            MikanRecordItem(
              title: '第一集资源',
              episode: '01',
              subgroupName: '测试字幕组',
              magnet: 'magnet:?xt=urn:btih:ep1',
            ),
            MikanRecordItem(
              title: '第二集资源',
              episode: '02',
              subgroupName: '测试字幕组',
              magnet: 'magnet:?xt=urn:btih:ep2',
            ),
          ],
        ),
        MikanSubgroupBangumi(
          dataId: '16',
          name: '另一字幕组',
          records: [
            MikanRecordItem(
              title: '另一字幕组第一集',
              episode: '1',
              magnet: 'magnet:?xt=urn:btih:other-ep1',
            ),
          ],
        ),
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('episode menu exposes Mikan resources callback', (tester) async {
    Episode? selected;
    final episode = _episode(sort: 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProgressGrid(
            episodes: [UserEpisodeCollection(episode: episode, type: 0)],
            onShowMikanResources: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(ValueKey('episode_${episode.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Mikan 资源'), findsOneWidget);

    await tester.tap(find.text('Mikan 资源'));
    await tester.pumpAndSettle();
    expect(selected?.id, episode.id);
  });

  testWidgets('episode resources default to the selected episode', (
    tester,
  ) async {
    final setup = await _pumpResourceLauncher(
      tester,
      episode: _episode(sort: 1),
    );

    await tester.tap(find.text('打开资源'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('第一集资源'), findsOneWidget);
    expect(find.text('另一字幕组第一集'), findsOneWidget);
    expect(find.text('第二集资源'), findsNothing);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('测试字幕组'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('mikan_episode_filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('集数: 全部').last);
    await tester.pumpAndSettle();

    expect(find.text('第一集资源'), findsOneWidget);
    expect(find.text('第二集资源'), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);
    addTearDown(setup.dispose);
  });

  testWidgets('unknown episode falls back to all season resources', (
    tester,
  ) async {
    final setup = await _pumpResourceLauncher(
      tester,
      episode: _episode(sort: 3),
    );

    await tester.tap(find.text('打开资源'));
    await tester.pumpAndSettle();

    expect(find.textContaining('未识别到 EP.3 的资源'), findsOneWidget);
    expect(find.text('第一集资源'), findsOneWidget);
    expect(find.text('第二集资源'), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);
    addTearDown(setup.dispose);
  });
}

Future<_TestSetup> _pumpResourceLauncher(
  WidgetTester tester, {
  required Episode episode,
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  await storage.init();
  final mikan = MikanProvider(
    service: _EpisodeResourceMikanService(),
    storage: storage,
  );
  await mikan.saveMapping(
    MikanSubjectMapping(
      subjectId: 12345,
      bangumiId: '681',
      bangumiName: '测试动画',
      subgroupId: '15',
      subgroupName: '测试字幕组',
      updatedAt: DateTime(2026, 7, 31),
    ),
  );
  final subject = _subject();

  await tester.pumpWidget(
    ChangeNotifierProvider<MikanProvider>.value(
      value: mikan,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showMikanSubscriptionDialog(
                context,
                subject,
                initialEpisode: episode.sortLabel,
                showResources: true,
              ),
              child: const Text('打开资源'),
            ),
          ),
        ),
      ),
    ),
  );
  return _TestSetup(mikan);
}

Subject _subject() {
  return Subject(
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
  );
}

Episode _episode({required double sort}) {
  return Episode(
    id: sort.toInt() + 1000,
    type: 0,
    name: '',
    nameCn: '第 ${sort.toInt()} 集',
    sort: sort,
    ep: sort,
    airdate: '',
    comment: 0,
    duration: '',
    desc: '',
    disc: 0,
  );
}

class _TestSetup {
  final MikanProvider provider;

  const _TestSetup(this.provider);

  void dispose() {
    provider.dispose();
  }
}
