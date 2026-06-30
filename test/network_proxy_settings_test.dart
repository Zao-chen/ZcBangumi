import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/models/network_proxy_settings.dart';

void main() {
  test('normalizes manual proxy host from URL', () {
    final settings = NetworkProxySettings.fromJson({
      'mode': 'manual',
      'host': 'http://127.0.0.1:7890',
      'port': 7890,
    });

    expect(settings.mode, NetworkProxyMode.manual);
    expect(settings.host, '127.0.0.1');
    expect(settings.port, 7890);
    expect(settings.isManualValid, isTrue);
  });

  test('direct proxy settings are serialized as defaults', () {
    const settings = NetworkProxySettings.direct();

    expect(settings.displayText, '直连');
    expect(settings.toJson(), {'mode': 'direct', 'host': '', 'port': null});
  });
}
