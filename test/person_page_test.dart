import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/models/person.dart';
import 'package:zc_bangumi/models/subject_tab_config.dart';
import 'package:zc_bangumi/pages/person_page.dart';
import 'package:zc_bangumi/providers/app_state_provider.dart';
import 'package:zc_bangumi/providers/auth_provider.dart';
import 'package:zc_bangumi/services/api_client.dart';
import 'package:zc_bangumi/services/storage_service.dart';

void main() {
  test('subject detail tabs include the staff entry', () {
    expect(SubjectTabConfig.allTabIds, contains(SubjectTabConfig.personsId));
    expect(SubjectTabConfig.getById(SubjectTabConfig.personsId)?.label, '制作');
  });

  test(
    'legacy subject tab order inserts staff immediately after characters',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      await storage.setCache('app_state', {
        'subjectTabOrder': [
          SubjectTabConfig.overviewId,
          SubjectTabConfig.charactersId,
          SubjectTabConfig.relatedId,
          SubjectTabConfig.commentsId,
          SubjectTabConfig.moegirlId,
        ],
      });

      final appState = AppStateProvider(storage: storage);
      await Future<void>.delayed(Duration.zero);

      expect(appState.subjectTabOrder, [
        SubjectTabConfig.overviewId,
        SubjectTabConfig.charactersId,
        SubjectTabConfig.personsId,
        SubjectTabConfig.relatedId,
        SubjectTabConfig.commentsId,
        SubjectTabConfig.moegirlId,
      ]);
    },
  );

  testWidgets('person page closes the detail, works, and character loop', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final api = _PersonApiClient();
    final auth = AuthProvider(api: api, storage: storage);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<StorageService>.value(value: storage),
          Provider<ApiClient>.value(value: api),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ],
        child: const MaterialApp(home: PersonPage(personId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('测试人物'), findsWidgets);
    expect(find.text('声优'), findsWidgets);
    expect(find.text('简介'), findsOneWidget);
    expect(find.text('人物简介'), findsOneWidget);
    expect(find.text('作品'), findsOneWidget);
    expect(find.text('角色'), findsOneWidget);

    await tester.tap(find.text('作品'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('person_subject_253')), findsOneWidget);
    expect(find.text('星际牛仔'), findsOneWidget);

    await tester.tap(find.text('角色'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('person_character_10')), findsOneWidget);
    expect(find.text('角色一'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('person_collection_button')));
    await tester.pump();
    expect(find.text('请先登录后再收藏人物'), findsOneWidget);
  });
}

class _PersonApiClient extends ApiClient {
  @override
  Future<PersonDetail> getPerson(int personId) async {
    return const PersonDetail(
      id: 1,
      name: '测试人物',
      type: 1,
      career: ['seiyu'],
      summary: '人物简介',
      gender: '女',
      collects: 20,
    );
  }

  @override
  Future<List<PersonSubject>> getPersonSubjects(int personId) async {
    return const [
      PersonSubject(
        id: 253,
        type: 2,
        name: 'COWBOY BEBOP',
        nameCn: '星际牛仔',
        image: '',
        staff: '声优',
        eps: '1-26',
      ),
    ];
  }

  @override
  Future<List<PersonCharacter>> getPersonCharacters(int personId) async {
    return const [
      PersonCharacter(
        id: 10,
        name: '角色一',
        type: 1,
        subjectId: 253,
        subjectType: 2,
        subjectName: 'COWBOY BEBOP',
        subjectNameCn: '星际牛仔',
        staff: '主角',
      ),
    ];
  }
}
