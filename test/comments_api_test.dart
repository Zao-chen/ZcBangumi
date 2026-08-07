import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/services/api_client.dart';

void main() {
  group('P1 comments API', () {
    test('loads subject comments with paging and maps P1 fields', () async {
      final adapter = _RecordingAdapter(
        (_) => _jsonResponse({
          'total': 42,
          'data': [
            {
              'id': 101,
              'type': 2,
              'rate': 9,
              'comment': 'API 吐槽',
              'updatedAt': 1760000000,
              'user': {
                'id': 7,
                'username': 'api_user',
                'nickname': '接口用户',
                'avatar': {
                  'small': 'small.jpg',
                  'medium': 'medium.jpg',
                  'large': 'large.jpg',
                },
              },
            },
          ],
        }),
      );
      final client = ApiClient();
      client.nextDio.httpClientAdapter = adapter;
      client.setToken('test-token');

      final result = await client.getSubjectComments(
        subjectId: 560988,
        limit: 20,
        offset: 40,
      );

      expect(result.total, 42);
      expect(result.limit, 20);
      expect(result.offset, 40);
      expect(result.data.single.id, 101);
      expect(result.data.single.content, 'API 吐槽');
      expect(result.data.single.rating, 9);
      expect(result.data.single.state, 2);
      expect(result.data.single.spoiler, 0);
      expect(result.data.single.usable, 1);
      expect(
        result.data.single.updatedAt.millisecondsSinceEpoch,
        1760000000000,
      );
      expect(result.data.single.userName, '接口用户');
      expect(result.data.single.userAvatar, 'medium.jpg');

      final request = adapter.requests.single;
      expect(request.uri.path, '/p1/subjects/560988/comments');
      expect(request.queryParameters, {'limit': 20, 'offset': 40});
      expect(request.headers['Authorization'], 'Bearer test-token');
    });

    test(
      'keeps character list responses paged without HTML fallback',
      () async {
        final adapter = _RecordingAdapter(
          (_) => _jsonResponse(
            List.generate(
              4,
              (index) => {
                'id': index + 1,
                'content': '角色吐槽 ${index + 1}',
                'state': 1,
                'createdAt': 1760000000 + index,
                'user': {'id': index + 10, 'nickname': '用户 ${index + 1}'},
              },
            ),
          ),
        );
        final client = ApiClient();
        client.nextDio.httpClientAdapter = adapter;

        final result = await client.getCharacterComments(
          characterId: 1,
          limit: 2,
          offset: 1,
        );

        expect(result.total, 4);
        expect(result.data.map((comment) => comment.id), [2, 3]);
        expect(adapter.requests.single.uri.path, '/p1/characters/1/comments');
      },
    );

    test('propagates API errors instead of turning them into empty data', () {
      final adapter = _RecordingAdapter(
        (_) => _jsonResponse({'message': 'bad gateway'}, statusCode: 502),
      );
      final client = ApiClient();
      client.nextDio.httpClientAdapter = adapter;

      expect(
        client.getSubjectComments(subjectId: 1),
        throwsA(
          isA<DioException>().having(
            (error) => error.response?.statusCode,
            'statusCode',
            502,
          ),
        ),
      );
    });

    test('rejects malformed successful responses', () {
      final adapter = _RecordingAdapter((_) => _jsonResponse('invalid'));
      final client = ApiClient();
      client.nextDio.httpClientAdapter = adapter;

      expect(
        client.getSubjectComments(subjectId: 1),
        throwsA(isA<FormatException>()),
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
