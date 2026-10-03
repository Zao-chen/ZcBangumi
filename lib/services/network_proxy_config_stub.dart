import 'package:dio/dio.dart';

import '../models/network_proxy_settings.dart';

class NetworkProxyConfigPlatform {
  NetworkProxyConfigPlatform._();

  static void installDio(Dio dio, NetworkProxySettings settings) {}
  static void uninstallDio(Dio dio) {}

  static void applySettings(NetworkProxySettings settings) {}
}
