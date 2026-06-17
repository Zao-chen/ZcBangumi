import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class WebNetworkConfig {
  WebNetworkConfig._();

  static void installWebAdapter(Dio dio) {
    if (!kIsWeb) return;

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          _removeBrowserForbiddenHeaders(options.headers);
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
