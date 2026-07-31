import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/models/bangumi_index.dart';
import 'package:zc_bangumi/services/api_client.dart';

void main() {
  test('loads index detail, reverse indexes and related content', () async {
    final adapter = _RecordingAdapter((request) {
      if (request.uri.path == '/p1/indexes/10') {
        return _jsonResponse({
          'id': 10,
          'uid': 1,
          'type': 0,
          'title': 'Test',
          'desc': '',
          'private': false,
          'stats': {'subject': <String, dynamic>{}},
          'createdAt': 1,
          'updatedAt': 1,
        });
      }
      if (request.uri.path.endsWith('/related')) {
        return _jsonResponse({
          'total': 1,
          'data': [
            {
              'id': 2,
              'cat': 0,
              'rid': 10,
              'sid': 12,
              'order': 10,
              'comment': '',
              'createdAt': 1,
              'subject': {'name': 'Subject'},
            },
          ],
        });
      }
      return _jsonResponse({
        'total': 1,
        'data': [
          {
            'id': 10,
            'uid': 1,
            'type': 0,
            'title': 'Test',
            'private': false,
            'stats': {'subject': <String, dynamic>{}},
            'createdAt': 1,
            'updatedAt': 1,
          },
        ],
      });
    });
    final client = ApiClient();
    client.nextDio.httpClientAdapter = adapter;

    final detail = await client.getBangumiIndex(10);
    final reverse = await client.getSubjectIndexes(subjectId: 12);
    final related = await client.getIndexRelated(
      indexId: 10,
      category: IndexRelatedCategory.subject,
      subjectType: 2,
    );

    expect(detail.title, 'Test');
    expect(reverse.data.single.id, 10);
    expect(related.data.single.sid, 12);
    expect(adapter.requests[1].uri.path, '/p1/subjects/12/indexes');
    expect(adapter.requests[2].queryParameters, {
      'cat': 0,
      'type': 2,
      'limit': 30,
      'offset': 0,
    });
  });

  test(
    'sends complete update and related mutation payloads with token',
    () async {
      final adapter = _RecordingAdapter((request) {
        if (request.method == 'PUT' && request.uri.path.endsWith('/related')) {
          return _jsonResponse({'id': 99});
        }
        return _jsonResponse({});
      });
      final client = ApiClient()..setToken('token');
      client.nextDio.httpClientAdapter = adapter;

      await client.updateBangumiIndex(
        indexId: 10,
        title: 'Title',
        description: ' Desc ',
        private: true,
      );
      await client.addBangumiIndexRelated(
        indexId: 10,
        category: IndexRelatedCategory.character,
        subjectId: 20,
        order: 30,
        comment: ' note ',
      );
      await client.updateBangumiIndexRelated(
        indexId: 10,
        relatedId: 99,
        order: 40,
        comment: ' changed ',
      );

      expect(adapter.requests.first.data, {
        'title': 'Title',
        'desc': ' Desc ',
        'private': true,
      });
      expect(adapter.requests[1].data, {
        'cat': 1,
        'sid': 20,
        'order': 30,
        'comment': ' note ',
      });
      expect(adapter.requests[2].data, {'order': 40, 'comment': ' changed '});
      expect(
        adapter.requests.every(
          (request) => request.headers['Authorization'] == 'Bearer token',
        ),
        isTrue,
      );
    },
  );

  test('maps known P1 errors to directory exception', () async {
    final client = ApiClient();
    client.nextDio.httpClientAdapter = _RecordingAdapter(
      (_) => _jsonResponse({'message': 'already exists'}, statusCode: 409),
    );

    expect(
      () => client.addBangumiIndexRelated(
        indexId: 1,
        category: IndexRelatedCategory.subject,
        subjectId: 2,
        order: 10,
      ),
      throwsA(
        isA<BangumiIndexApiException>()
            .having((error) => error.conflict, 'conflict', isTrue)
            .having((error) => error.message, 'message', '该内容已经在目录中'),
      ),
    );
  });

  test('falls back safely when P1 error fields are not strings', () async {
    final client = ApiClient();
    client.nextDio.httpClientAdapter = _RecordingAdapter(
      (_) => _jsonResponse({
        'message': {'unexpected': true},
      }, statusCode: 403),
    );

    expect(
      () => client.deleteBangumiIndex(1),
      throwsA(
        isA<BangumiIndexApiException>()
            .having((error) => error.forbidden, 'forbidden', isTrue)
            .having((error) => error.message, 'message', '当前账号没有目录操作权限'),
      ),
    );
  });

  test('covers user lists, create, delete and collection endpoints', () async {
    final adapter = _RecordingAdapter((request) {
      if (request.method == 'POST' && request.uri.path == '/p1/indexes') {
        return _jsonResponse({'id': 88});
      }
      if (request.method == 'GET') {
        return _jsonResponse({'total': 0, 'data': <dynamic>[]});
      }
      return _jsonResponse({});
    });
    final client = ApiClient();
    client.nextDio.httpClientAdapter = adapter;

    expect(
      await client.createBangumiIndex(
        title: ' New ',
        description: 'Desc',
        private: false,
      ),
      88,
    );
    await client.getUserCreatedIndexes(username: 'test user');
    await client.getUserCollectedIndexes(username: 'test user');
    await client.getCharacterIndexes(characterId: 3);
    await client.getPersonIndexes(personId: 4);
    await client.collectBangumiIndex(88);
    await client.uncollectBangumiIndex(88);
    await client.deleteBangumiIndexRelated(indexId: 88, relatedId: 9);
    await client.deleteBangumiIndex(88);

    expect(
      adapter.requests.map((request) => request.uri.path),
      containsAll([
        '/p1/indexes',
        '/p1/users/test%20user/indexes',
        '/p1/users/test%20user/collections/indexes',
        '/p1/characters/3/indexes',
        '/p1/persons/4/indexes',
        '/p1/collections/indexes/88',
        '/p1/indexes/88/related/9',
        '/p1/indexes/88',
      ]),
    );
    expect(adapter.requests.first.data['title'], 'New');
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
