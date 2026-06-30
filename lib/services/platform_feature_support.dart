import 'package:flutter/foundation.dart';

class PlatformFeatureSupport {
  PlatformFeatureSupport._();

  static bool get timeline => !kIsWeb;
  static bool get rakuen => !kIsWeb;
  static bool get mikan => !kIsWeb;
  static bool get appUpdate => !kIsWeb;
  static bool get networkProxy => !kIsWeb;
}
