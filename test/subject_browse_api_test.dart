import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/constants.dart';
import 'package:zc_bangumi/models/subject_browse.dart';
import 'package:zc_bangumi/services/api_client.dart';

void main() {
  group('ApiClient.browseSubjects', () {
    test('sends every supported official query parameter', () async {
      final adapter = _RecordingAdapter(
        (_) => _jsonResponse({
          'total': 1,
          'limit': 30,
          'offset': 0,
          'data': [_subjectJson()],
        }),
      );
      final client = ApiClient();
      client.dio.httpClientAdapter = adapter;

      final page = await client.browseSubjects(
        filter: const SubjectBrowseFilter(
          type: BgmConst.subjectGame,
          category: 4003,
          platform: '  PC  ',
          year: 2026,
          month: 7,
          sort: SubjectBrowseSort.date,
        ),
      );

      final request = adapter.requests.single;
      expect(request.method, 'GET');
      expect(request.uri.path, '/v0/subjects');
      expect(request.queryParameters, {
        'type': BgmConst.subjectGame,
        'cat': 4003,
        'platform': 'PC',
        'sort': 'date',
        'year': 2026,
        'month': 7,
        'limit': 30,
        'offset': 0,
      });
      expect(page.total, 1);
      expect(page.data.single.displayName, '测试条目');
      expect(page.data.single.date, '2026-07-30');
    });

    test('omits optional filters and supports book series', () async {
      final adapter = _RecordingAdapter(
        (_) => _jsonResponse({
          'total': 0,
          'limit': 10,
          'offset': 20,
          'data': <dynamic>[],
        }),
      );
      final client = ApiClient();
      client.dio.httpClientAdapter = adapter;

      await client.browseSubjects(
        filter: const SubjectBrowseFilter(
          type: BgmConst.subjectBook,
          series: true,
        ),
        limit: 10,
        offset: 20,
      );

      expect(adapter.requests.single.queryParameters, {
        'type': BgmConst.subjectBook,
        'series': true,
        'sort': 'rank',
        'limit': 10,
        'offset': 20,
      });
    });

    test('rejects invalid type, pagination, and month locally', () {
      final adapter = _RecordingAdapter((_) => _jsonResponse({}));
      final client = ApiClient();
      client.dio.httpClientAdapter = adapter;

      expect(
        client.browseSubjects(filter: const SubjectBrowseFilter(type: 5)),
        throwsArgumentError,
      );
      expect(
        client.browseSubjects(filter: const SubjectBrowseFilter(), limit: 51),
        throwsArgumentError,
      );
      expect(
        client.browseSubjects(filter: const SubjectBrowseFilter(month: 13)),
        throwsArgumentError,
      );
      expect(adapter.requests, isEmpty);
    });
  });
}

Map<String, dynamic> _subjectJson() => {
  'id': 1,
  'type': 4,
  'name': 'Test Subject',
  'name_cn': '测试条目',
  'summary': 'Summary',
  'series': false,
  'nsfw': true,
  'locked': false,
  'platform': 'PC',
  'date': '2026-07-30',
  'images': null,
  'volumes': 0,
  'eps': 0,
  'total_episodes': 0,
  'rating': {
    'rank': 12,
    'total': 10,
    'count': <String, dynamic>{},
    'score': 8.1,
  },
  'collection': {
    'wish': 1,
    'collect': 2,
    'doing': 3,
    'on_hold': 4,
    'dropped': 5,
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
