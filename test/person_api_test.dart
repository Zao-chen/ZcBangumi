import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/models/person.dart';
import 'package:zc_bangumi/services/api_client.dart';

void main() {
  group('Person models', () {
    test('parses official person detail fields and complex infobox values', () {
      final person = PersonDetail.fromJson({
        'id': 1,
        'name': '测试人物',
        'type': 1,
        'career': ['seiyu', 'actor', 'new_career'],
        'images': {
          'large': 'large.jpg',
          'medium': 'medium.jpg',
          'small': 'small.jpg',
          'grid': 'grid.jpg',
        },
        'summary': '人物简介',
        'locked': false,
        'last_modified': '2026-07-15T08:00:00Z',
        'infobox': [
          {'key': '别名', 'value': 'Alias'},
          {
            'key': '简体中文名',
            'value': [
              {'v': '测试名', 'k': '中文'},
            ],
          },
        ],
        'gender': '女',
        'blood_type': 3,
        'birth_year': 1990,
        'birth_mon': 7,
        'birth_day': 15,
        'stat': {'comments': 12, 'collects': 34},
      });

      expect(person.name, '测试人物');
      expect(person.typeLabel, '个人');
      expect(person.careerLabels, ['声优', '演员', 'new_career']);
      expect(person.infobox['别名'], 'Alias');
      expect(person.infobox['简体中文名'], '测试名（中文）');
      expect(person.bloodTypeLabel, 'AB');
      expect(person.birthdayLabel, '1990年7月15日');
      expect(person.comments, 12);
      expect(person.collects, 34);
    });
  });

  group('ApiClient person flow', () {
    test('loads person and character relation endpoints', () async {
      final adapter = _RecordingAdapter((request) {
        switch (request.uri.path) {
          case '/v0/subjects/253/persons':
            return _jsonResponse([
              {
                'id': 1,
                'name': '人物一',
                'type': 1,
                'career': ['seiyu'],
                'images': null,
                'relation': '声优',
                'eps': '1-26',
              },
            ]);
          case '/v0/persons/1':
            return _jsonResponse({
              'id': 1,
              'name': '人物一',
              'type': 1,
              'career': ['seiyu'],
              'summary': '简介',
              'locked': false,
              'last_modified': '2026-07-15T08:00:00Z',
              'stat': {'comments': 1, 'collects': 2},
            });
          case '/v0/persons/1/subjects':
            return _jsonResponse([
              {
                'id': 253,
                'type': 2,
                'name': 'COWBOY BEBOP',
                'name_cn': '星际牛仔',
                'image': 'cover.jpg',
                'staff': '声优',
                'eps': '1-26',
              },
            ]);
          case '/v0/persons/1/characters':
            return _jsonResponse([
              {
                'id': 10,
                'name': '角色一',
                'type': 1,
                'subject_id': 253,
                'subject_type': 2,
                'subject_name': 'COWBOY BEBOP',
                'subject_name_cn': '星际牛仔',
                'staff': '主角',
              },
            ]);
          case '/v0/characters/10/subjects':
            return _jsonResponse([
              {
                'id': 253,
                'type': 2,
                'name': 'COWBOY BEBOP',
                'name_cn': '星际牛仔',
                'image': 'cover.jpg',
                'staff': '主角',
                'eps': '1-26',
              },
            ]);
          case '/v0/characters/10/persons':
            return _jsonResponse([
              {
                'id': 1,
                'name': '人物一',
                'type': 1,
                'images': {
                  'medium': 'person-medium.jpg',
                  'small': 'person-small.jpg',
                },
                'subject_id': 253,
                'subject_type': 2,
                'subject_name': 'COWBOY BEBOP',
                'subject_name_cn': '星际牛仔',
                'staff': '主角',
              },
            ]);
          default:
            return _jsonResponse({'title': 'not found'}, statusCode: 404);
        }
      });
      final client = ApiClient();
      client.dio.httpClientAdapter = adapter;

      final staff = await client.getSubjectPersons(253);
      final person = await client.getPerson(1);
      final subjects = await client.getPersonSubjects(1);
      final characters = await client.getPersonCharacters(1);
      final appearances = await client.getCharacterSubjects(10);
      final characterPersons = await client.getCharacterPersons(10);

      expect(staff.single.relation, '声优');
      expect(staff.single.eps, '1-26');
      expect(person.summary, '简介');
      expect(subjects.single.displayName, '星际牛仔');
      expect(characters.single.name, '角色一');
      expect(characters.single.displaySubjectName, '星际牛仔');
      expect(appearances.single.displayName, '星际牛仔');
      expect(appearances.single.staff, '主角');
      expect(characterPersons.single.name, '人物一');
      expect(characterPersons.single.displaySubjectName, '星际牛仔');
      expect(characterPersons.single.images?.bestSmall, 'person-medium.jpg');
      expect(characterPersons.single.staff, '主角');
      expect(adapter.requests.map((request) => request.uri.path), [
        '/v0/subjects/253/persons',
        '/v0/persons/1',
        '/v0/persons/1/subjects',
        '/v0/persons/1/characters',
        '/v0/characters/10/subjects',
        '/v0/characters/10/persons',
      ]);
    });

    test('reports person collection state from 200 and 404', () async {
      final adapter = _RecordingAdapter((request) {
        if (request.uri.path.contains('/persons/2')) {
          return _jsonResponse({'title': 'not found'}, statusCode: 404);
        }
        return _jsonResponse({
          'id': 1,
          'name': '人物一',
          'type': 1,
          'career': ['seiyu'],
          'created_at': '2026-07-15T08:00:00Z',
        });
      });
      final client = ApiClient();
      client.dio.httpClientAdapter = adapter;

      expect(
        await client.isPersonCollected(username: '测试 用户', personId: 1),
        isTrue,
      );
      expect(
        await client.isPersonCollected(username: '测试 用户', personId: 2),
        isFalse,
      );
      expect(
        adapter.requests.first.uri.toString(),
        contains('%E6%B5%8B%E8%AF%95'),
      );
    });

    test('propagates non-404 collection failures', () {
      final adapter = _RecordingAdapter(
        (_) => _jsonResponse({'title': 'server error'}, statusCode: 500),
      );
      final client = ApiClient();
      client.dio.httpClientAdapter = adapter;

      expect(
        client.isPersonCollected(username: 'user', personId: 1),
        throwsA(isA<DioException>()),
      );
    });
  });
}

ResponseBody _jsonResponse(Object body, {int statusCode = 200}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _RecordingAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions request) handler;
  final List<RequestOptions> requests = [];

  _RecordingAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}
