import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/models/character.dart';
import 'package:zc_bangumi/models/entity_search.dart';
import 'package:zc_bangumi/services/api_client.dart';

void main() {
  group('entity search request models', () {
    test('omit empty filters and serialize supported filters', () {
      expect(const CharacterSearchRequest(keyword: '爱音').toJson(), {
        'keyword': '爱音',
      });
      expect(
        const CharacterSearchRequest(
          keyword: '爱音',
          filter: CharacterSearchFilter(nsfw: false),
        ).toJson(),
        {
          'keyword': '爱音',
          'filter': {'nsfw': false},
        },
      );
      expect(
        const PersonSearchRequest(
          keyword: '林原惠',
          filter: PersonSearchFilter(careers: ['seiyu', 'actor']),
        ).toJson(),
        {
          'keyword': '林原惠',
          'filter': {
            'career': ['seiyu', 'actor'],
          },
        },
      );
    });
  });

  group('ApiClient.searchCharacters', () {
    test('uses the official endpoint and parses nested statistics', () async {
      final adapter = _RecordingAdapter(
        (_) => _jsonResponse({
          'total': 8,
          'limit': 6,
          'offset': 0,
          'data': [_characterJson()],
        }),
      );
      final client = ApiClient();
      client.dio.httpClientAdapter = adapter;

      final page = await client.searchCharacters(
        keyword: '  千早爱音  ',
        filter: const CharacterSearchFilter(nsfw: false),
        limit: 6,
      );

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/v0/search/characters');
      expect(request.queryParameters, {'limit': 6, 'offset': 0});
      expect(request.data, {
        'keyword': '千早爱音',
        'filter': {'nsfw': false},
      });
      expect(page.total, 8);
      expect(page.data.single.name, '千早愛音');
      expect(page.data.single.collects, 233);
      expect(page.data.single.comments, 17);
      expect(page.data.single.images.single.medium, contains('medium'));

      final cached = page.data.single.toJson();
      final restored = Character.fromJson(cached);
      expect(restored.images.single.medium, contains('medium'));
      expect(restored.collects, 233);
    });

    test('accepts a null images object', () async {
      final character = _characterJson()..['images'] = null;
      final adapter = _RecordingAdapter(
        (_) => _jsonResponse({
          'data': [character],
        }),
      );
      final client = ApiClient();
      client.dio.httpClientAdapter = adapter;

      final page = await client.searchCharacters(keyword: '爱音');

      expect(page.data.single.images, isEmpty);
    });
  });

  group('ApiClient.searchPersons', () {
    test('uses the official endpoint and parses a paged response', () async {
      final adapter = _RecordingAdapter(
        (_) => _jsonResponse({
          'total': 3,
          'limit': 30,
          'offset': 0,
          'data': [_personJson()],
        }),
      );
      final client = ApiClient();
      client.dio.httpClientAdapter = adapter;

      final page = await client.searchPersons(
        keyword: '  林原惠 ',
        filter: const PersonSearchFilter(careers: ['seiyu']),
      );

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/v0/search/persons');
      expect(request.queryParameters, {'limit': 30, 'offset': 0});
      expect(request.data, {
        'keyword': '林原惠',
        'filter': {
          'career': ['seiyu'],
        },
      });
      expect(page.total, 3);
      expect(page.data.single.name, '林原めぐみ');
      expect(page.data.single.career, ['seiyu', 'actor']);
      expect(page.data.single.shortSummary, '日本女性声优、歌手。');
    });
  });

  test('entity searches reject invalid input before sending requests', () {
    final adapter = _RecordingAdapter((_) => _jsonResponse({}));
    final client = ApiClient();
    client.dio.httpClientAdapter = adapter;

    expect(client.searchCharacters(keyword: '  '), throwsArgumentError);
    expect(
      client.searchCharacters(keyword: '角色', limit: 0),
      throwsArgumentError,
    );
    expect(
      client.searchPersons(keyword: '人物', offset: -1),
      throwsArgumentError,
    );
    expect(adapter.requests, isEmpty);
  });
}

Map<String, dynamic> _characterJson() => {
  'id': 141354,
  'name': '千早愛音',
  'type': 1,
  'images': {
    'large': 'https://example.com/character-large.jpg',
    'medium': 'https://example.com/character-medium.jpg',
    'small': 'https://example.com/character-small.jpg',
    'grid': 'https://example.com/character-grid.jpg',
  },
  'summary': '月之森女子学园的转学生。',
  'locked': false,
  'stat': {'comments': 17, 'collects': 233},
};

Map<String, dynamic> _personJson() => {
  'id': 3,
  'name': '林原めぐみ',
  'type': 1,
  'career': ['seiyu', 'actor'],
  'images': null,
  'short_summary': '日本女性声优、歌手。',
  'locked': false,
};

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
