import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../constants.dart';
import '../models/bangumi_web_session.dart';
import '../models/rakuen_topic_detail.dart';
import 'webview_environment_service.dart';

class WebReplyService {
  static Future<void> submitReply({
    required String topicUrl,
    required String content,
    required BangumiWebSession session,
    RakuenPost? replyToPost,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw Exception('回复内容不能为空');
    }

    final cookie = session.buildCookieHeaderForUri(
      Uri.parse(BgmConst.webBaseUrl),
    );
    final cookieJar = session.cookies
        .map((item) => item.toJson())
        .cast<Map<String, dynamic>>()
        .toList();

    final isSubReply = replyToPost?.subReplyAction != null;
    final replyPageUrl = isSubReply
        ? _getTopicPageUrl(_normalizeWebUrl(topicUrl))
        : _buildReplyPageUrl(topicUrl);
    if (replyPageUrl == null) {
      throw Exception('当前主题暂不支持回复');
    }

    if (kDebugMode) {
      print('');
      print('-----------------');
      print('[WebReplyService] 开始网页回复');
      print('  目标地址: $replyPageUrl');
      print('  回复类型: ${isSubReply ? "楼中楼" : "主题回复"}');
      print('  Cookie Header 长度: ${cookie?.length ?? 0}');
      print('  CookieJar 数量: ${cookieJar.length}');
      print('-----------------');
    }

    final environment = await WebViewEnvironmentService.getSharedEnvironment();
    await _seedCookies(
      cookie: cookie,
      cookieJar: cookieJar,
      environment: environment,
    );
    await Future.delayed(const Duration(milliseconds: 500));

    final completer = Completer<void>();
    HeadlessInAppWebView? headlessWebView;
    Timer? timeoutTimer;
    var submitted = false;
    var cookiesInjected = false;

    Future<void> finishSuccess() async {
      if (completer.isCompleted) return;
      timeoutTimer?.cancel();
      await headlessWebView?.dispose();
      if (kDebugMode) {
        print('[WebReplyService] 网页回复成功');
      }
      completer.complete();
    }

    Future<void> finishError(Object error) async {
      if (completer.isCompleted) return;
      timeoutTimer?.cancel();
      await headlessWebView?.dispose();
      if (kDebugMode) {
        print('[WebReplyService] 网页回复失败: $error');
      }
      completer.completeError(error);
    }

    Future<void> handlePage(InAppWebViewController controller) async {
      final currentUrl =
          (await controller.getUrl())?.toString() ?? replyPageUrl;

      if (kDebugMode) {
        print('[WebReplyService] 页面加载完成: $currentUrl');
      }

      if (!isSubReply && !currentUrl.endsWith('/new_reply')) {
        if (currentUrl.contains('/group/topic/') ||
            currentUrl.contains('/subject/topic/')) {
          if (kDebugMode) {
            print('[WebReplyService] 跳转到主题回复页');
          }
          await controller.loadUrl(
            urlRequest: URLRequest(url: WebUri(replyPageUrl)),
          );
          return;
        }
      }

      final result = await controller.evaluateJavascript(
        source: isSubReply
            ? _buildSubReplyScript(
                content: trimmed,
                postId: replyToPost!.id,
                subReplyAction: replyToPost.subReplyAction!,
              )
            : _buildReplyScript(trimmed),
      );

      if (kDebugMode) {
        print('[WebReplyService] JavaScript 返回: $result');
      }

      final normalizedResult = _normalizeJsResult(result);
      if (normalizedResult == null) {
        throw Exception(
          '无法识别网页回复结果，返回类型: ${result.runtimeType}',
        );
      }

      final status = '${normalizedResult['status'] ?? ''}';
      final detail = '${normalizedResult['detail'] ?? '-'}';

      if (kDebugMode) {
        print('[WebReplyService] 状态: $status, 详情: $detail');
      }

      switch (status) {
        case 'submitted':
          submitted = true;
          if (isSubReply && replyToPost != null) {
            final success = await _waitForSubReplySuccess(
              controller: controller,
              postId: replyToPost.id,
              content: trimmed,
            );
            if (success) {
              await finishSuccess();
            }
          }
          return;
        case 'success':
          await finishSuccess();
          return;
        case 'login_required':
          throw Exception(
            '当前网页会话未登录，请先在设置中重新登录 Bangumi 网页',
          );
        case 'form_missing':
          throw Exception('当前主题没有可用的回复表单: $detail');
        default:
          throw Exception(
            '网页回复失败，状态: $status，详情: $detail，URL: $currentUrl',
          );
      }
    }

    headlessWebView = HeadlessInAppWebView(
      webViewEnvironment: environment,
      initialUrlRequest: URLRequest(
        url: WebUri(_getTopicPageUrl(replyPageUrl)),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        isInspectable: kDebugMode,
        thirdPartyCookiesEnabled: true,
        userAgent:
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      ),
      onLoadStop: (controller, url) async {
        if (!cookiesInjected && (cookie?.trim().isNotEmpty ?? false)) {
          try {
            final hasAuthCookie = await controller.evaluateJavascript(
              source: '''
(() => {
  const cookies = document.cookie || '';
  return (
    cookies.includes('chii_auth') ||
    cookies.includes('chii_sec_id') ||
    cookies.includes('chii_sid')
  );
})()
''',
            );

            if (hasAuthCookie != true) {
              if (kDebugMode) {
                print('[WebReplyService] 页面 Cookie 缺失，准备补种');
              }

              final parts = cookie!.trim().split(';');
              for (final part in parts) {
                final segment = part.trim();
                if (segment.isEmpty) continue;
                final index = segment.indexOf('=');
                if (index <= 0) continue;

                final name = segment.substring(0, index).trim();
                final value = segment.substring(index + 1).trim();
                if (name.isEmpty) continue;

                final encodedName = jsonEncode(name);
                final encodedValue = jsonEncode(value);
                await controller.evaluateJavascript(
                  source: '''
(() => {
  const name = $encodedName;
  const value = $encodedValue;
  const host = location.hostname || 'bgm.tv';
  const cookieDomain = host.endsWith('bangumi.tv')
    ? '.bangumi.tv'
    : host.endsWith('chii.in')
        ? '.chii.in'
        : '.bgm.tv';
  document.cookie = name + '=' + value + '; path=/; domain=' + cookieDomain + '; max-age=86400';
})()
''',
                );
              }

              cookiesInjected = true;
              if (kDebugMode) {
                print('[WebReplyService] 页面 Cookie 已补种，重新加载当前页面');
              }
              await controller.reload();
              return;
            }
          } catch (e) {
            if (kDebugMode) {
              print('[WebReplyService] 页面 Cookie 检查失败: $e');
            }
          }
        }

        try {
          await handlePage(controller);
        } catch (e) {
          await finishError(e);
        }
      },
      onUpdateVisitedHistory: (controller, url, isReload) async {
        if (!submitted || completer.isCompleted) return;
        final currentUrl = url?.toString() ?? '';
        if ((currentUrl.contains('/group/topic/') ||
                currentUrl.contains('/subject/topic/')) &&
            !currentUrl.endsWith('/new_reply')) {
          await finishSuccess();
        }
      },
      onReceivedError: (controller, request, error) async {
        final description = error.description.toLowerCase();
        if (description.contains('connection was stopped') ||
            description.contains('operation was canceled') ||
            description.contains('navigation canceled')) {
          return;
        }
        await finishError(Exception('网页加载失败: ${error.description}'));
      },
    );

    timeoutTimer = Timer(const Duration(seconds: 25), () async {
      await finishError(Exception('网页回复超时，请重试'));
    });

    await headlessWebView.run();
    return completer.future;
  }

  static String? _buildReplyPageUrl(String topicUrl) {
    final normalized = _normalizeWebUrl(topicUrl);
    if (normalized.contains('/group/topic/') ||
        normalized.contains('/subject/topic/')) {
      return normalized.endsWith('/new_reply')
          ? normalized
          : '$normalized/new_reply';
    }
    return null;
  }

  static String _getTopicPageUrl(String replyPageUrl) {
    return replyPageUrl.replaceAll(RegExp(r'/new_reply$'), '');
  }

  static String _normalizeWebUrl(String value) {
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) {
      return '${BgmConst.webBaseUrl}$value';
    }
    return '${BgmConst.webBaseUrl}/$value';
  }

  static Future<void> _seedCookies({
    String? cookie,
    List<Map<String, dynamic>>? cookieJar,
    WebViewEnvironment? environment,
  }) async {
    final manager = CookieManager.instance(webViewEnvironment: environment);

    if (kDebugMode) {
      print('[WebReplyService] 开始注入 Cookie');
    }

    try {
      final oldCookies = await manager.getCookies(url: WebUri('https://bgm.tv/'));
      for (final oldCookie in oldCookies) {
        await manager.deleteCookie(
          url: WebUri('https://bgm.tv/'),
          name: oldCookie.name,
        );
      }
      if (kDebugMode && oldCookies.isNotEmpty) {
        print('[WebReplyService] 已清理旧 Cookie: ${oldCookies.length}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[WebReplyService] 清理旧 Cookie 失败，可忽略: $e');
      }
    }

    if (cookieJar != null && cookieJar.isNotEmpty) {
      if (kDebugMode) {
        print('[WebReplyService] 使用结构化 CookieJar: ${cookieJar.length}');
      }

      var successCount = 0;
      final failedCookies = <String>[];

      for (final item in cookieJar) {
        try {
          final name = '${item['name'] ?? ''}'.trim();
          final value = '${item['value'] ?? ''}';
          final domain = '${item['domain'] ?? ''}'.trim();
          final path = '${item['path'] ?? '/'}'.trim();
          if (name.isEmpty) continue;

          final urls = _getCookieUrls(domain);
          if (urls.isEmpty) continue;

          var planted = false;
          for (final url in urls) {
            try {
              await manager.setCookie(
                url: WebUri(url),
                name: name,
                value: value,
                domain: domain.isEmpty ? null : domain,
                path: path.isEmpty ? '/' : path,
                expiresDate: item['expiresDate'] as int?,
                isSecure: item['isSecure'] as bool?,
                isHttpOnly: item['isHttpOnly'] as bool?,
              );
              planted = true;
            } catch (_) {}
          }

          if (planted) {
            successCount++;
          } else {
            failedCookies.add(name);
          }
        } catch (_) {}
      }

      if (kDebugMode) {
        print('[WebReplyService] CookieJar 注入成功: $successCount/${cookieJar.length}');
        if (failedCookies.isNotEmpty) {
          print('[WebReplyService] 注入失败的 Cookie: ${failedCookies.join(", ")}');
        }
      }

      final missingCookies = await _verifyCookies(manager);
      if (missingCookies.isNotEmpty &&
          cookie != null &&
          cookie.trim().isNotEmpty) {
        if (kDebugMode) {
          print(
            '[WebReplyService] 用 Cookie Header 补种缺失项: ${missingCookies.join(", ")}',
          );
        }
        await _seedCookiesFromString(cookie, manager);
        await _verifyCookies(manager);
      }
      return;
    }

    await _seedCookiesFromString(cookie, manager);
  }

  static Future<void> _seedCookiesFromString(
    String? cookie,
    CookieManager manager,
  ) async {
    final normalized = (cookie ?? '').trim();
    if (normalized.isEmpty) {
      if (kDebugMode) {
        print('[WebReplyService] 没有可用的 Cookie Header');
      }
      return;
    }

    if (kDebugMode) {
      print('[WebReplyService] 使用 Cookie Header 补种');
    }

    final parts = normalized.split(';');
    var successCount = 0;
    const importantNames = {'chii_auth', 'chii_sec_id', 'chii_sid'};

    for (final part in parts) {
      final segment = part.trim();
      if (segment.isEmpty) continue;
      final index = segment.indexOf('=');
      if (index <= 0) continue;

      final name = segment.substring(0, index).trim();
      final value = segment.substring(index + 1).trim();
      if (name.isEmpty) continue;

      const urlsWithDomain = [
        ('https://bgm.tv/', '.bgm.tv'),
        ('https://bangumi.tv/', '.bangumi.tv'),
        ('https://chii.in/', '.chii.in'),
      ];

      var planted = false;
      for (final (url, domain) in urlsWithDomain) {
        try {
          await manager.setCookie(
            url: WebUri(url),
            name: name,
            value: value,
            domain: importantNames.contains(name) ? domain : null,
            path: '/',
          );
          planted = true;
        } catch (_) {}
      }

      if (planted) {
        successCount++;
      }
    }

    if (kDebugMode) {
      print('[WebReplyService] Cookie Header 补种成功: $successCount');
    }

    await _verifyCookies(manager);
  }

  static Future<List<String>> _verifyCookies(CookieManager manager) async {
    try {
      final allCookies = <String, Cookie>{};
      const urlsToCheck = [
        'https://bgm.tv/',
        'https://www.bgm.tv/',
        'https://bangumi.tv/',
        'https://www.bangumi.tv/',
        'https://chii.in/',
        'https://www.chii.in/',
      ];

      for (final url in urlsToCheck) {
        try {
          final cookies = await manager.getCookies(url: WebUri(url));
          for (final cookie in cookies) {
            allCookies[cookie.name] = cookie;
          }
        } catch (_) {}
      }

      const importantCookies = ['chii_auth', 'chii_sec_id', 'chii_sid'];
      final missing = importantCookies
          .where((name) => !allCookies.containsKey(name))
          .toList();

      if (kDebugMode) {
        if (missing.isEmpty) {
          print('[WebReplyService] 关键 Cookie 已齐全');
        } else {
          print('[WebReplyService] 缺少关键 Cookie: ${missing.join(", ")}');
        }
      }

      return missing;
    } catch (e) {
      if (kDebugMode) {
        print('[WebReplyService] 验证 Cookie 失败: $e');
      }
      return ['chii_auth', 'chii_sec_id', 'chii_sid'];
    }
  }

  static List<String> _getCookieUrls(String domain) {
    final normalized = domain.trim().replaceFirst(RegExp(r'^\.+'), '');
    if (normalized.isEmpty) {
      return ['https://bgm.tv/', 'https://bangumi.tv/', 'https://chii.in/'];
    }
    if (normalized.endsWith('bgm.tv') || normalized.endsWith('bangumi.tv')) {
      return ['https://bgm.tv/', 'https://bangumi.tv/', 'https://$normalized/'];
    }
    if (normalized.endsWith('chii.in')) {
      return ['https://chii.in/', 'https://$normalized/'];
    }
    return [];
  }

  static String _buildReplyScript(String content) {
    final encoded = jsonEncode(content);
    return '''
(() => {
  const cookies = document.cookie || '';
  const hasAuthCookie =
    cookies.includes('chii_auth') ||
    cookies.includes('chii_sec_id') ||
    cookies.includes('chii_sid');

  const uid = typeof CHOBITS_UID !== 'undefined'
    ? Number.parseInt(CHOBITS_UID, 10) || 0
    : (typeof CHOBITS_USER_UID !== 'undefined'
        ? Number.parseInt(CHOBITS_USER_UID, 10) || 0
        : 0);
  const username = typeof CHOBITS_USERNAME !== 'undefined'
    ? String(CHOBITS_USERNAME || '')
    : '';

  if (uid <= 0 && !hasAuthCookie) {
    return {
      status: 'login_required',
      detail: 'uid=' + uid + ', cookieCount=' + cookies.split(';').filter(Boolean).length + ', url=' + location.href
    };
  }

  const submit =
    document.querySelector('#ReplyForm input[type="submit"]') ||
    Array.from(document.querySelectorAll('input[type="submit"], button[type="submit"], input.inputBtn')).find((item) => {
      const value = (item.value || item.textContent || '').trim();
      return value.includes('加上去') || value.includes('写好了') || item.getAttribute('name') === 'submit';
    });

  const form =
    document.querySelector('#ReplyForm') ||
    submit?.closest('form') ||
    Array.from(document.forms).find((item) => {
      return !!(
        item.querySelector('textarea[name="content"]') ||
        item.querySelector('textarea')
      );
    });

  if (!form) {
    return {
      status: 'form_missing',
      detail: 'reply_form_missing:title=' + (document.title || location.href),
    };
  }

  const textarea =
    form.querySelector('textarea[name="content"]') ||
    form.querySelector('textarea') ||
    document.querySelector('#content');

  if (!textarea) {
    return {
      status: 'form_missing',
      detail: 'reply_textarea_missing',
    };
  }

  textarea.value = $encoded;
  textarea.dispatchEvent(new Event('input', { bubbles: true }));
  textarea.dispatchEvent(new Event('change', { bubbles: true }));

  const formSubmit =
    submit ||
    form.querySelector('input[type="submit"]') ||
    form.querySelector('button[type="submit"]');

  if (formSubmit) {
    formSubmit.click();
  } else if (typeof form.requestSubmit === 'function') {
    form.requestSubmit();
  } else {
    form.submit();
  }

  return { status: 'submitted' };
})()
''';
  }

  static String _buildSubReplyScript({
    required String content,
    required String postId,
    required String subReplyAction,
  }) {
    final encodedContent = jsonEncode(content);
    final encodedPostId = jsonEncode(postId);
    final encodedAction = jsonEncode(subReplyAction);
    return '''
(() => {
  const postId = String($encodedPostId);
  const action = $encodedAction;
  const post = document.querySelector('#post_' + postId);
  if (!post) {
    return { status: 'form_missing', detail: 'post_not_found:' + postId };
  }

  try {
    (0, eval)(action);
  } catch (error) {
    return { status: 'form_missing', detail: 'sub_reply_eval_failed:' + error };
  }

  const form =
    document.querySelector('#ReplysForm') ||
    document.querySelector('form[name="new_comment"] input[name="post_id"][value="' + postId + '"]')?.closest('form') ||
    Array.from(document.querySelectorAll('form')).find((item) => {
      const postIdInput = item.querySelector('input[name="post_id"]');
      return postIdInput && String(postIdInput.value || '') === postId;
    }) ||
    post.querySelector('.topic_sub_reply form') ||
    post.querySelector('form') ||
    document.querySelector('#reply_wrapper form') ||
    document.querySelector('form[name="sub_reply"]');

  if (!form) {
    return { status: 'form_missing', detail: 'sub_reply_form_missing:' + postId };
  }

  const textarea =
    document.querySelector('#content_' + postId) ||
    form.querySelector('textarea.reply.sub_reply') ||
    form.querySelector('textarea[name="content"]') ||
    form.querySelector('textarea') ||
    post.querySelector('textarea');

  if (!textarea) {
    return { status: 'form_missing', detail: 'sub_reply_textarea_missing:' + postId };
  }

  textarea.value = $encodedContent;
  textarea.dispatchEvent(new Event('input', { bubbles: true }));
  textarea.dispatchEvent(new Event('change', { bubbles: true }));

  const submit =
    form.querySelector('input[type="submit"]') ||
    form.querySelector('button[type="submit"]') ||
    post.querySelector('input.inputBtn');

  if (submit) {
    submit.click();
  } else if (typeof form.requestSubmit === 'function') {
    form.requestSubmit();
  } else {
    form.submit();
  }

  return { status: 'submitted', detail: 'sub_reply_submitted:' + postId };
})()
''';
  }

  static Future<bool> _waitForSubReplySuccess({
    required InAppWebViewController controller,
    required String postId,
    required String content,
  }) async {
    final encodedPostId = jsonEncode(postId);
    final encodedContent = jsonEncode(content.trim());

    for (var i = 0; i < 12; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        final raw = await controller.evaluateJavascript(
          source: '''
(() => {
  const postId = String($encodedPostId);
  const expected = String($encodedContent).replace(/\\s+/g, ' ').trim();
  const post = document.querySelector('#post_' + postId);
  if (!post) {
    return { success: false, detail: 'post_missing' };
  }

  const form =
    document.querySelector('#ReplysForm') ||
    Array.from(document.querySelectorAll('form')).find((item) => {
      const postIdInput = item.querySelector('input[name="post_id"]');
      return postIdInput && String(postIdInput.value || '') === postId;
    });

  const text = (post.innerText || '').replace(/\\s+/g, ' ').trim();
  const hasContent = expected.length > 0 && text.includes(expected);

  return {
    success: hasContent || !form,
    hasContent,
    formPresent: !!form,
  };
})()
''',
        );
        final normalized = _normalizeJsResult(raw);
        if (normalized?['success'] == true) {
          return true;
        }
      } catch (_) {
        // Ignore transient DOM errors while the page is updating.
      }
    }
    return false;
  }

  static Map<String, dynamic>? _normalizeJsResult(dynamic raw) {
    if (raw is Map) {
      return raw.map((key, value) => MapEntry('$key', value));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry('$key', value));
        }
      } catch (_) {
        // Ignore non-JSON strings.
      }
    }
    return null;
  }
}
