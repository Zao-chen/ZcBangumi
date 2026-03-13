import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/bangumi_web_session.dart';
import 'api_client.dart';
import 'storage_service.dart';
import 'webview_environment_service.dart';

class BangumiWebPageSignal {
  final bool loggedIn;
  final String? username;
  final int? uid;

  const BangumiWebPageSignal({
    required this.loggedIn,
    this.username,
    this.uid,
  });
}

class BangumiWebSessionInspection {
  final List<BangumiWebSessionCookie> cookies;
  final bool hasAuthCookie;
  final int requestCookieCount;
  final List<String> requestCookieNames;
  final WebSessionInfo? validatedSession;
  final String? error;

  const BangumiWebSessionInspection({
    required this.cookies,
    required this.hasAuthCookie,
    required this.requestCookieCount,
    required this.requestCookieNames,
    required this.validatedSession,
    this.error,
  });
}

class BangumiWebSessionService {
  static const List<String> _sessionHosts = <String>[
    'https://bgm.tv/',
    'https://bangumi.tv/',
    'https://chii.in/',
  ];

  final StorageService storage;
  final ApiClient api;

  const BangumiWebSessionService({
    required this.storage,
    required this.api,
  });

  BangumiWebSession? get currentSession => storage.webSession;

  bool get hasValidSession => currentSession?.isValid == true;

  Future<void> restoreStoredSession() async {
    api.setWebSession(storage.webSession);
  }

  Future<void> clearPersistedSession({
    bool clearLegacyInvalidated = false,
  }) async {
    await storage.setWebSession(null);
    if (clearLegacyInvalidated) {
      await storage.setLegacyWebSessionInvalidated(false);
    }
    api.setWebSession(null);
  }

  Future<void> clearBangumiCookies() async {
    final manager = CookieManager.instance(
      webViewEnvironment: await WebViewEnvironmentService.getSharedEnvironment(),
    );

    for (final url in _sessionHosts) {
      try {
        final cookies = await manager.getCookies(url: WebUri(url));
        for (final cookie in cookies) {
          await manager.deleteCookie(url: WebUri(url), name: cookie.name);
        }
      } catch (_) {
        // Ignore best-effort cleanup failures.
      }
    }
  }

  Future<List<BangumiWebSessionCookie>> readBangumiCookies() async {
    final manager = CookieManager.instance(
      webViewEnvironment: await WebViewEnvironmentService.getSharedEnvironment(),
    );
    final seen = <String>{};
    final result = <BangumiWebSessionCookie>[];

    Future<void> collectFromUrl(String url) async {
      try {
        final cookies = await manager.getCookies(url: WebUri(url));
        for (final cookie in cookies) {
          final normalized = _normalizeCookie(cookie);
          if (normalized == null) continue;
          final key = [
            normalized.name,
            normalized.value,
            normalized.domain,
            normalized.path,
          ].join('\u0001');
          if (!seen.add(key)) continue;
          result.add(normalized);
        }
      } catch (_) {
        // Ignore and continue collecting from remaining hosts.
      }
    }

    try {
      final cookies = await manager.getAllCookies();
      for (final cookie in cookies) {
        final normalized = _normalizeCookie(cookie);
        if (normalized == null) continue;
        final key = [
          normalized.name,
          normalized.value,
          normalized.domain,
          normalized.path,
        ].join('\u0001');
        if (!seen.add(key)) continue;
        result.add(normalized);
      }
    } catch (_) {
      // Fallback to per-host collection below.
    }

    for (final url in _sessionHosts) {
      await collectFromUrl(url);
    }

    return result;
  }

  Future<WebSessionInfo?> validateSession([BangumiWebSession? session]) async {
    final candidate = session ?? storage.webSession;
    if (candidate == null || !candidate.hasCookies) return null;
    return api.validateWebSession(candidate);
  }

  Future<BangumiWebSessionInspection> inspectSession({
    required BangumiWebPageSignal pageSignal,
  }) async {
    try {
      final cookies = await readBangumiCookies();
      if (cookies.isEmpty) {
        return const BangumiWebSessionInspection(
          cookies: [],
          hasAuthCookie: false,
          requestCookieCount: 0,
          requestCookieNames: [],
          validatedSession: null,
        );
      }

      final hasAuthCookie = cookies.any(
        (cookie) =>
            cookie.name == 'chii_auth' ||
            cookie.name == 'chii_sec_id' ||
            cookie.name == 'chii_sid',
      );
      if (!hasAuthCookie) {
        return BangumiWebSessionInspection(
          cookies: cookies,
          hasAuthCookie: false,
          requestCookieCount: 0,
          requestCookieNames: const [],
          validatedSession: null,
        );
      }

      final now = DateTime.now();
      final candidate = BangumiWebSession(
        username: (pageSignal.username ?? '').trim(),
        uid: pageSignal.uid ?? 0,
        capturedAt: now,
        validatedAt: now,
        primaryHost: 'bgm.tv',
        cookies: cookies,
      );
      final requestCookies = candidate.cookiesForUri(Uri.parse('https://bgm.tv/'));
      final validatedSession = await validateSession(candidate) ??
          _fallbackValidatedSessionFromPageSignal(pageSignal);

      return BangumiWebSessionInspection(
        cookies: cookies,
        hasAuthCookie: true,
        requestCookieCount: requestCookies.length,
        requestCookieNames: requestCookies.map((cookie) => cookie.name).toList(),
        validatedSession: validatedSession,
      );
    } catch (e) {
      return BangumiWebSessionInspection(
        cookies: const [],
        hasAuthCookie: false,
        requestCookieCount: 0,
        requestCookieNames: const [],
        validatedSession: null,
        error: '$e',
      );
    }
  }

  Future<BangumiWebSession?> captureValidatedSession({
    required BangumiWebPageSignal pageSignal,
    BangumiWebSessionInspection? inspection,
  }) async {
    final resolvedInspection =
        inspection ?? await inspectSession(pageSignal: pageSignal);
    if (!resolvedInspection.hasAuthCookie ||
        resolvedInspection.validatedSession == null ||
        resolvedInspection.cookies.isEmpty) {
      return null;
    }

    final now = DateTime.now();
    final session = BangumiWebSession(
      username: resolvedInspection.validatedSession!.username,
      uid: resolvedInspection.validatedSession!.uid,
      capturedAt: now,
      validatedAt: now,
      primaryHost: 'bgm.tv',
      cookies: resolvedInspection.cookies,
    );

    await storage.setWebSession(session);
    await storage.setLegacyWebSessionInvalidated(false);
    api.setWebSession(session);
    return session;
  }

  BangumiWebSessionCookie? _normalizeCookie(Cookie cookie) {
    final name = cookie.name.trim();
    if (name.isEmpty) return null;

    final domain = (cookie.domain ?? '').trim().toLowerCase();
    if (domain.isNotEmpty &&
        !domain.endsWith('bgm.tv') &&
        !domain.endsWith('bangumi.tv') &&
        !domain.endsWith('chii.in')) {
      return null;
    }

    return BangumiWebSessionCookie(
      name: name,
      value: '${cookie.value}',
      domain: domain,
      path: (cookie.path ?? '/').trim().isEmpty ? '/' : '${cookie.path}',
      expiresDate: cookie.expiresDate,
      isSecure: cookie.isSecure ?? false,
      isHttpOnly: cookie.isHttpOnly ?? false,
    );
  }

  WebSessionInfo? _fallbackValidatedSessionFromPageSignal(
    BangumiWebPageSignal pageSignal,
  ) {
    final username = (pageSignal.username ?? '').trim();
    final uid = pageSignal.uid ?? 0;
    if (!pageSignal.loggedIn || username.isEmpty || uid <= 0) {
      return null;
    }
    return WebSessionInfo(uid: uid, username: username);
  }
}
