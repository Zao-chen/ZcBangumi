import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/utils/mikan_error.dart';

void main() {
  test('formats Mikan server errors without exposing Dio internals', () {
    final error = DioException.badResponse(
      statusCode: 502,
      requestOptions: RequestOptions(path: '/Home/Bangumi/681'),
      response: Response<void>(
        requestOptions: RequestOptions(path: '/Home/Bangumi/681'),
        statusCode: 502,
      ),
    );

    final message = mikanErrorMessage(error);

    expect(message, 'Mikan 服务暂时不可用（502），请稍后重试或切换站点');
    expect(message, isNot(contains('DioException')));
  });

  test('formats connection timeouts with a retry suggestion', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/Home/Bangumi/681'),
      type: DioExceptionType.connectionTimeout,
    );

    expect(mikanErrorMessage(error), '连接 Mikan 超时，请重试或切换站点');
  });
}
