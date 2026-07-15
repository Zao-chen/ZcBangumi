import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/models/subject_search.dart';
import 'package:zc_bangumi/services/api_client.dart';

void main() {
  group('SubjectSearchFilter', () {
    test('serializes every official filter field', () {
      const filter = SubjectSearchFilter(
        types: [1, 2],
        metaTags: ['原创'],
        tags: ['科幻'],
        airDates: ['>=2020-01-01'],
        ratings: ['>=7'],
        ratingCounts: ['>=200'],
        ranks: ['<=100'],
        nsfw: false,
      );

      expect(filter.toJson(), {
        'type': [1, 2],
        'meta_tags': ['原创'],
        'tag': ['科幻'],
        'air_date': ['>=2020-01-01'],
        'rating': ['>=7'],
        'rating_count': ['>=200'],
        'rank': ['<=100'],
        'nsfw': false,
      });
    });

    test('omits an empty filter from the request body', () {
      const request = SubjectSearchRequest(keyword: '星际牛仔');

      expect(request.toJson(), {'keyword': '星际牛仔', 'sort': 'match'});
    });
  });

  group('ApiClient.searchSubjects', () {
    test('uses the official endpoint and parses a paged response', () async {
      final adapter = _RecordingAdapter(
        (_) => _jsonResponse({
          'total': 42,
          'limit': 30,
          'offset': 0,
          'data': [_subjectJson()],
        }),
      );
      final client = ApiClient();
      client.dio.httpClientAdapter = adapter;

      final page = await client.searchSubjects(
        keyword: '  星际牛仔  ',
        filter: const SubjectSearchFilter(types: [2]),
        sort: SubjectSearchSort.heat,
        limit: 30,
      );

      expect(adapter.requests, hasLength(1));
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/v0/search/subjects');
      expect(request.queryParameters, {'limit': 30, 'offset': 0});
      expect(request.data, {
        'keyword': '星际牛仔',
        'sort': 'heat',
        'filter': {
          'type': [2],
        },
      });

      expect(page.total, 42);
      expect(page.limit, 30);
      expect(page.offset, 0);
      expect(page.data, hasLength(1));
      final subject = page.data.single;
      expect(subject.id, 253);
      expect(subject.displayName, '星际牛仔');
      expect(subject.shortSummary, '赏金猎人的宇宙冒险。');
      expect(subject.score, 8.9);
      expect(subject.rank, 2);
      expect(subject.collectionTotal, 25);
    });

    test('propagates server failures instead of returning no results', () {
      final adapter = _RecordingAdapter(
        (_) => _jsonResponse({'title': 'server error'}, statusCode: 500),
      );
      final client = ApiClient();
      client.dio.httpClientAdapter = adapter;

      expect(
        client.searchSubjects(keyword: '星际牛仔'),
        throwsA(isA<DioException>()),
      );
    });

    test('rejects invalid pagination arguments before sending a request', () {
      final adapter = _RecordingAdapter((_) => _jsonResponse({}));
      final client = ApiClient();
      client.dio.httpClientAdapter = adapter;

      expect(
        client.searchSubjects(keyword: '   '),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        client.searchSubjects(keyword: '动画', limit: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        client.searchSubjects(keyword: '动画', offset: -1),
        throwsA(isA<ArgumentError>()),
      );
      expect(adapter.requests, isEmpty);
    });
  });
}

Map<String, dynamic> _subjectJson() => {
  'id': 253,
  'type': 2,
  'name': 'COWBOY BEBOP',
  'name_cn': '星际牛仔',
  'summary': '赏金猎人的宇宙冒险。',
  'series': false,
  'nsfw': false,
  'locked': false,
  'platform': 'TV',
  'images': {
    'large': 'https://example.com/large.jpg',
    'common': 'https://example.com/common.jpg',
    'medium': 'https://example.com/medium.jpg',
    'small': 'https://example.com/small.jpg',
    'grid': 'https://example.com/grid.jpg',
  },
  'volumes': 0,
  'eps': 26,
  'total_episodes': 26,
  'rating': {
    'rank': 2,
    'total': 100,
    'count': <String, dynamic>{},
    'score': 8.9,
  },
  'collection': {
    'wish': 1,
    'collect': 20,
    'doing': 2,
    'on_hold': 1,
    'dropped': 1,
  },
  'meta_tags': <String>[],
  'tags': <Map<String, dynamic>>[],
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
