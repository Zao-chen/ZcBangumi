import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../models/network_proxy_settings.dart';

class NetworkProxyConfigPlatform {
  NetworkProxyConfigPlatform._();

  static NetworkProxySettings _settings = const NetworkProxySettings.direct();
  static final Set<Dio> _registeredDios = <Dio>{};

  static void installDio(Dio dio, NetworkProxySettings settings) {
    _registeredDios.add(dio);
    _settings = settings.normalized();
    _installAdapter(dio);
  }

  static void applySettings(NetworkProxySettings settings) {
    _settings = settings.normalized();
    for (final dio in _registeredDios) {
      dio.httpClientAdapter.close(force: true);
      _installAdapter(dio);
    }
  }

  static void _installAdapter(Dio dio) {
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        _configureClient(client);
        return client;
      },
    );
  }

  static void _configureClient(HttpClient client) {
    switch (_settings.mode) {
      case NetworkProxyMode.direct:
        client.findProxy = (_) => 'DIRECT';
      case NetworkProxyMode.system:
        client.findProxy = HttpClient.findProxyFromEnvironment;
      case NetworkProxyMode.manual:
        if (_settings.isManualValid) {
          final host = _settings.host.trim();
          final port = _settings.port;
          client.findProxy = (_) => 'PROXY $host:$port';
        } else {
          client.findProxy = (_) => 'DIRECT';
        }
    }
  }
}
