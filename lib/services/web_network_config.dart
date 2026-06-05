import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class WebNetworkConfig {
  WebNetworkConfig._();

  static const String proxyBase = String.fromEnvironment('ZC_WEB_PROXY_BASE');

  static bool get hasProxy => proxyBase.trim().isNotEmpty;

  static void installWebAdapter(Dio dio) {
    if (!kIsWeb) return;

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          _removeBrowserForbiddenHeaders(options.headers);

          final originalUri = options.uri;
          if (hasProxy && shouldProxy(originalUri)) {
            final proxiedUri = proxyUri(originalUri);
            options.baseUrl = '';
            options.path = proxiedUri.toString();
            options.queryParameters = const {};
          }

          handler.next(options);
        },
      ),
    );
  }

  static bool shouldProxy(Uri uri) {
    if (!kIsWeb || !hasProxy) return false;

    switch (uri.host.toLowerCase()) {
      case 'bgm.tv':
      case 'bangumi.tv':
      case 'next.bgm.tv':
      case 'mikanani.me':
      case 'mikanime.tv':
        return true;
      default:
        return false;
    }
  }

  static Uri proxyUri(Uri target) {
    final base = Uri.parse(proxyBase.trim());
    final nextQuery = Map<String, String>.from(base.queryParameters)
      ..['url'] = target.toString();
    return base.replace(queryParameters: nextQuery);
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
