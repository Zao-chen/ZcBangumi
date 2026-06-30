import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/services/mikan_service.dart';

void main() {
  test('getBangumi completes capped subgroup records from search', () async {
    final dio = Dio(
      BaseOptions(
        responseType: ResponseType.plain,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    dio.httpClientAdapter = _FakeMikanAdapter();
    final service = MikanService(dio: dio);

    final detail = await service.getBangumi('681');
    final records = detail.subgroupBangumis.single.records;

    expect(records.length, 16);
    expect(records.last.title, contains('16'));
    expect(records.last.magnet, startsWith('magnet:?xt=urn:btih:search16'));
    expect(records.last.torrent, 'https://mikanani.me/Download/16.torrent');
  });
}

class _FakeMikanAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = options.uri;
    if (uri.path == '/Home/Bangumi/681') {
      return ResponseBody.fromString(_detailHtml(), 200);
    }
    if (uri.path == '/Home/Search' &&
        uri.queryParameters['searchstr'] == '测试动画' &&
        uri.queryParameters['subgroupid'] == '15') {
      return ResponseBody.fromString(_searchHtml(), 200);
    }
    return ResponseBody.fromString('not found', 404);
  }

  @override
  void close({bool force = false}) {}
}

String _detailHtml() {
  return '''
    <div id="sk-container">
      <div class="pull-left leftbar-container">
        <p class="bangumi-title"><a href="/Home/Bangumi?bangumiId=681">测试动画</a></p>
      </div>
      <div class="central-container">
        <p>简介</p>
        <div class="subgroup-text" id="15">
          <a href="/Home/PublishGroup/15">字幕组</a>
          <a class="mikan-rss" href="/RSS/Bangumi?bangumiId=681&subgroupid=15"></a>
        </div>
        <div class="episode-table">
          <table><tbody>
            ${List.generate(15, (index) => _detailRow(index + 1)).join()}
          </tbody></table>
        </div>
      </div>
    </div>
  ''';
}

String _searchHtml() {
  return '''
    <table><tbody>
      ${List.generate(16, (index) => _searchRow(index + 1)).join()}
    </tbody></table>
  ''';
}

String _detailRow(int index) {
  return '''
    <tr>
      <td><input data-magnet="magnet:?xt=urn:btih:detail$index"></td>
      <td><a class="magnet-link-wrap" href="/Home/Episode/$index">[字幕组] 测试动画 [$index][1080P][MP4]</a></td>
      <td>${index}00MB</td>
      <td>2026/06/$index 07:23</td>
      <td><a href="/Download/$index.torrent">种子</a></td>
    </tr>
  ''';
}

String _searchRow(int index) {
  return '''
    <tr class="js-search-results-row">
      <td><input data-magnet="magnet:?xt=urn:btih:search$index"></td>
      <td>
        <a class="magnet-link-wrap" href="/Home/Episode/$index">[字幕组] 测试动画 [$index][1080P][MP4]</a>
        <a data-clipboard-text="magnet:?xt=urn:btih:search$index" class="js-magnet">[复制磁连]</a>
      </td>
      <td>${index}00MB</td>
      <td>2026/06/$index 07:23</td>
      <td><a href="/Download/$index.torrent">种子</a></td>
    </tr>
  ''';
}
