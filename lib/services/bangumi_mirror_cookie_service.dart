import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/bangumi_mirror_session.dart';
import '../models/bangumi_mirror_settings.dart';
import 'bangumi_endpoint_service.dart';

class BangumiMirrorCookieService {
  BangumiMirrorCookieService({CookieManager? manager})
    : _manager = manager ?? CookieManager.instance();

  final CookieManager _manager;

  Future<void> clear(
    BangumiEndpointService endpoints,
    List<BangumiMirrorSession> sessions,
  ) async {
    final settings = endpoints.settings;
    if (settings.isOfficial) return;
    final targets = <String, Uri>{
      for (final kind in BangumiServiceKind.values)
        endpoints.probeUri(kind).toString(): endpoints.probeUri(kind),
      for (final origin in settings.endpoints.values) origin.toString(): origin,
      for (final session in sessions)
        for (final cookie in session.cookies)
          '${session.origin}${cookie.path}': Uri.parse(
            session.origin,
          ).replace(path: cookie.path),
    };
    final removed = <String>{};
    for (final uri in targets.values) {
      if (BangumiEndpointService.officialKind(uri) != null) continue;
      final cookies = await _manager.getCookies(url: WebUri.uri(uri));
      for (final cookie in cookies) {
        final domain = cookie.domain?.isNotEmpty == true
            ? cookie.domain!
            : uri.host;
        final path = cookie.path ?? '/';
        final key = '${uri.host}|$domain|$path|${cookie.name}';
        if (!removed.add(key)) continue;
        final deleted = await _manager.deleteCookie(
          url: WebUri.uri(uri),
          name: cookie.name,
          domain: domain,
          path: path,
        );
        if (!deleted) throw StateError('无法清除 WebView 验证 Cookie');
      }
    }
  }
}
