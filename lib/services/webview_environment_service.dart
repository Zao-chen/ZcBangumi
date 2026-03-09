import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WebViewEnvironmentService {
  static WebViewEnvironment? _windowsEnvironment;

  static Future<WebViewEnvironment?> getSharedEnvironment() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return null;
    }
    _windowsEnvironment ??= await WebViewEnvironment.create();
    return _windowsEnvironment;
  }
}
