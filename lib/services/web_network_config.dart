import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class WebNetworkConfig {
  WebNetworkConfig._();

  static void installWebAdapter(Dio dio, {bool available = true}) {
    if (!kIsWeb) return;

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          _removeBrowserForbiddenHeaders(options.headers);
          if (!available) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.cancel,
                message: '此接口不支持浏览器跨域访问，请在 Bangumi 原站或完整客户端使用',
              ),
            );
            return;
          }
          handler.next(options);
        },
      ),
    );
  }

  static void _removeBrowserForbiddenHeaders(Map<String, dynamic> headers) {
    headers.removeWhere((key, _) {
      switch (key.toLowerCase()) {
        case 'cookie':
        case 'host':
        case 'origin':
        case 'referer':
        case 'user-agent':
          return true;
        default:
          return false;
      }
    });
  }
}
