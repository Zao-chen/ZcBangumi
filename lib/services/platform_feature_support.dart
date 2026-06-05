import 'package:flutter/foundation.dart';

import 'web_network_config.dart';

class PlatformFeatureSupport {
  PlatformFeatureSupport._();

  static bool get timeline => !kIsWeb || WebNetworkConfig.hasProxy;
  static bool get rakuen => !kIsWeb || WebNetworkConfig.hasProxy;
  static bool get mikan => !kIsWeb;
  static bool get appUpdate => !kIsWeb;
}
