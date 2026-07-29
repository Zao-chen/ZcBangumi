import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/models/collection.dart';
import 'package:zc_bangumi/services/api_client.dart';

void main() {
  group('entity collection models', () {
    test('parses character collection fields and cache round-trip', () {
      final item = UserCharacterCollection.fromJson({
        'id': 10,
        'name': '测试机体',
        'type': 2,
        'images': {
          'large': 'large.jpg',
          'medium': 'medium.jpg',
          'small': 'small.jpg',
          'grid': 'grid.jpg',
        },
        'created_at': '2026-07-15T08:00:00+08:00',
      });

      expect(item.id, 10);
      expect(item.typeLabel, '机体');
      expect(item.images?.bestSmall, 'medium.jpg');
      expect(
        UserCharacterCollection.fromJson(item.toJson()).createdAt,
        item.createdAt,
      );
    });

    test('accepts missing career and images in live person responses', () {
      final item = UserPersonCollection.fromJson({
        'id': 20,
        'name': '测试人物',
        'type': 1,
        'created_at': '2026-07-15T08:00:00Z',
      });

      expect(item.typeLabel, '个人');
      expect(item.career, isEmpty);
      expect(item.images, isNull);
    });

    test('maps known person careers to Chinese labels', () {
      final item = UserPersonCollection.fromJson({
        'id': 21,
        'name': '声优',
        'type': 1,
        'career': ['seiyu', 'actor'],
        'created_at': '2026-07-15T08:00:00Z',
      });

      expect(item.careerLabels, ['声优', '演员']);
    });
  });

  group('ApiClient entity collections', () {
    test('loads paged character and person collections', () async {
      final adapter = _RecordingAdapter((request) {
        if (request.uri.path.endsWith('/characters')) {
          return _jsonResponse({
            'total': 2,
            'limit': 30,
            'offset': 0,
            'data': [
              {
                'id': 10,
                'name': '测试角色',
                'type': 1,
                'images': null,
                'created_at': '2026-07-15T08:00:00Z',
              },
            ],
          });
        }
        return _jsonResponse({
          'data': [
            {
              'id': 20,
              'name': '测试人物',
              'type': 1,
              'created_at': '2026-07-16T08:00:00Z',
            },
          ],
        });
      });
      final client = ApiClient();
      client.dio.httpClientAdapter = adapter;

      final characters = await client.getUserCharacterCollections(
        username: '测试 用户',
      );
      final persons = await client.getUserPersonCollections(
        username: '测试 用户',
        limit: 10,
        offset: 1,
      );

      expect(characters.total, 2);
      expect(characters.data.single.name, '测试角色');
      expect(persons.total, 1);
      expect(persons.limit, 10);
      expect(persons.offset, 1);
      expect(persons.data.single.career, isEmpty);

      final characterRequest = adapter.requests.first;
      expect(characterRequest.method, 'GET');
      expect(
        characterRequest.uri.toString(),
        contains(
          '/v0/users/%E6%B5%8B%E8%AF%95%20%E7%94%A8%E6%88%B7/collections/-/characters',
        ),
      );
      expect(characterRequest.queryParameters, {'limit': 30, 'offset': 0});

      final personRequest = adapter.requests.last;
      expect(personRequest.uri.path, endsWith('/collections/-/persons'));
      expect(personRequest.queryParameters, {'limit': 10, 'offset': 1});
    });

    test('rejects invalid collection paging before requesting', () {
      final adapter = _RecordingAdapter((_) => _jsonResponse({}));
      final client = ApiClient();
      client.dio.httpClientAdapter = adapter;

      expect(
        client.getUserCharacterCollections(username: ' ', limit: 30),
        throwsArgumentError,
      );
      expect(
        client.getUserPersonCollections(username: 'user', limit: 51),
        throwsArgumentError,
      );
      expect(
        client.getUserPersonCollections(username: 'user', offset: -1),
        throwsArgumentError,
      );
      expect(adapter.requests, isEmpty);
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
