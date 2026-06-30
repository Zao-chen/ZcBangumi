import 'package:dio/dio.dart';

import '../models/network_proxy_settings.dart';
import 'network_proxy_config_stub.dart'
    if (dart.library.io) 'network_proxy_config_io.dart'
    as platform;

class NetworkProxyConfig {
  NetworkProxyConfig._();

  static NetworkProxySettings _settings = const NetworkProxySettings.direct();

  static NetworkProxySettings get settings => _settings;

  static void initialize(NetworkProxySettings settings) {
    _settings = settings.normalized();
    platform.NetworkProxyConfigPlatform.applySettings(_settings);
  }

  static void installDio(Dio dio) {
    platform.NetworkProxyConfigPlatform.installDio(dio, _settings);
  }

  static void update(NetworkProxySettings settings) {
    _settings = settings.normalized();
    platform.NetworkProxyConfigPlatform.applySettings(_settings);
  }
}
