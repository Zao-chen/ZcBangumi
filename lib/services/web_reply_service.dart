import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../constants.dart';
import '../models/bangumi_web_session.dart';
import 'webview_environment_service.dart';

class WebReplyService {
  static Future<void> submitReply({
    required String topicUrl,
    required String content,
    required BangumiWebSession session,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw Exception('回复内容不能为空');
    }
    final cookie = session.buildCookieHeaderForUri(Uri.parse(BgmConst.webBaseUrl));
    final cookieJar = session.cookies
        .map((item) => item.toJson())
        .cast<Map<String, dynamic>>()
        .toList();

    final replyPageUrl = _buildReplyPageUrl(topicUrl);
    if (replyPageUrl == null) {
      throw Exception('当前主题暂不支持回复');
    }

    if (kDebugMode) {
      print('');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🔄 [回复流程开始]');
      print('   目标URL: $replyPageUrl');
      print('   Cookie长度: ${cookie?.length ?? 0}');
      print('   CookieJar: ${cookieJar?.length ?? 0} 条');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    }

    final environment = await WebViewEnvironmentService.getSharedEnvironment();

    // 先种植Cookie
    await _seedCookies(
      cookie: cookie,
      cookieJar: cookieJar,
      environment: environment,
    );

    // 额外延迟确保Cookie生效
    await Future.delayed(const Duration(milliseconds: 500));

    final completer = Completer<void>();
    HeadlessInAppWebView? headlessWebView;
    Timer? timeoutTimer;
    bool submitted = false;
    bool cookiesInjected = false; // 标记是否已注入Cookie

    Future<void> finishSuccess() async {
      if (completer.isCompleted) return;
      if (kDebugMode) {
        print('');
        print('✅ [回复成功]');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('');
      }
      timeoutTimer?.cancel();
      await headlessWebView?.dispose();
      completer.complete();
    }

    Future<void> finishError(Object error) async {
      if (completer.isCompleted) return;
      if (kDebugMode) {
        print('');
        print('❌ [回复失败]');
        print('   错误: $error');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('');
      }
      timeoutTimer?.cancel();
      await headlessWebView?.dispose();
      completer.completeError(error);
    }

    Future<void> handlePage(InAppWebViewController controller) async {
      final currentUrl =
          (await controller.getUrl())?.toString() ?? replyPageUrl;

      if (kDebugMode) {
        print('[WebReplyService] 页面加载完成: $currentUrl');

        // 检查页面实际可用的Cookie
        try {
          final cookieCheck = await controller.evaluateJavascript(
            source: '''
            (() => {
              const cookies = document.cookie;
              const cookieList = cookies.split(';').map(c => c.trim().split('=')[0]);
              return {
                hasCookie: cookies.length > 0,
                cookieCount: cookieList.length,
                hasAuth: cookieList.includes('chii_auth'),
                hasSec: cookieList.includes('chii_sec_id'),
                hasSid: cookieList.includes('chii_sid'),
                uid: typeof CHOBITS_UID !== 'undefined' ? CHOBITS_UID : null
              };
            })();
          ''',
          );
          print('[WebReplyService] Cookie检查: $cookieCheck');
        } catch (e) {
          print('[WebReplyService] Cookie检查失败: $e');
        }
      }

      // 如果当前在主题页面（不是回复页），导航到回复页
      if (!currentUrl.endsWith('/new_reply')) {
        if (currentUrl.contains('/group/topic/') ||
            currentUrl.contains('/subject/topic/')) {
          if (kDebugMode) {
            print('[WebReplyService] 从主题页导航到回复页');
          }
          await controller.loadUrl(
            urlRequest: URLRequest(url: WebUri(replyPageUrl)),
          );
          return;
        }
      }

      final result = await controller.evaluateJavascript(
        source: _buildReplyScript(trimmed),
      );

      if (kDebugMode) {
        print('[WebReplyService] JavaScript 执行结果: $result');
      }

      if (result is! Map) {
        throw Exception('未能识别网页回复状态，返回值类型: ${result.runtimeType}');
      }

      final status = '${result['status'] ?? ''}';
      final detail = '${result['detail'] ?? '-'}';

      if (kDebugMode) {
        print('[WebReplyService] 状态: $status, 详情: $detail');
      }

      switch (status) {
        case 'submitted':
          submitted = true;
          if (kDebugMode) {
            print('[WebReplyService] 表单已提交，等待跳转');
          }
          return;
        case 'success':
          await finishSuccess();
          return;
        case 'login_required':
          throw Exception('当前网页 Cookie 未登录，请先在设置中重新自动获取 Bangumi 网页 Cookie');
        case 'form_missing':
          throw Exception('当前主题暂时没有可用的回复表单 | 详情: $detail');
        default:
          throw Exception(
            '网页回复失败 | 状态: $status | URL: $currentUrl | 详情: $detail',
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
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      ),
      onLoadStop: (controller, url) async {
        // 先检查Cookie，如果没有就注入
        if (!cookiesInjected && cookie != null && cookie.trim().isNotEmpty) {
          try {
            final check = await controller.evaluateJavascript(
              source: '''
              (() => {
                const cookies = document.cookie;
                return cookies.includes('chii_auth');
              })();
            ''',
            );

            if (check != true) {
              if (kDebugMode) {
                print('[WebReplyService] 检测到Cookie缺失，注入中...');
              }

              // 注入Cookie
              final parts = cookie.trim().split(';');
              for (final part in parts) {
                final segment = part.trim();
                if (segment.isEmpty) continue;
                final index = segment.indexOf('=');
                if (index <= 0) continue;
                final name = segment.substring(0, index).trim();
                final value = segment.substring(index + 1).trim();
                if (name.isEmpty) continue;

                await controller.evaluateJavascript(
                  source:
                      '''
                  document.cookie = "$name=$value; path=/; domain=.bgm.tv; max-age=86400";
                ''',
                );
              }

              cookiesInjected = true;

              // 重新加载当前页面
              if (kDebugMode) {
                print('[WebReplyService] Cookie注入完成，重新加载页面');
              }
              await controller.reload();
              return;
            }
          } catch (e) {
            if (kDebugMode) {
              print('[WebReplyService] Cookie检查/注入失败: $e');
            }
          }
        }

        // Cookie已就位，正常处理页面
        try {
          await handlePage(controller);
        } catch (e) {
          await finishError(e);
        }
      },
      onUpdateVisitedHistory: (controller, url, isReload) async {
        if (!submitted || completer.isCompleted) return;
        final currentUrl = url?.toString() ?? '';
        // 提交后返回主题页（不带/new_reply），说明回复成功
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
    // 从回复页URL提取主题页URL（去掉 /new_reply 后缀）
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
      print('🍪 [Cookie种植]');
    }

    // 先清除旧的Cookie，确保干净的环境
    try {
      final oldCookies = await manager.getCookies(
        url: WebUri('https://bgm.tv/'),
      );
      if (oldCookies.isNotEmpty && kDebugMode) {
        print('   清除 ${oldCookies.length} 个旧Cookie');
      }
      for (final oldCookie in oldCookies) {
        await manager.deleteCookie(
          url: WebUri('https://bgm.tv/'),
          name: oldCookie.name,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('   清除旧Cookie失败（可忽略）');
      }
    }

    // 优先使用 cookieJar（包含完整的 cookie 信息）
    if (cookieJar != null && cookieJar.isNotEmpty) {
      if (kDebugMode) {
        print('   使用 CookieJar (${cookieJar.length} 条)');
        // 输出关键Cookie的详细信息用于调试
        final importantNames = ['chii_auth', 'chii_sec_id', 'chii_sid'];
        for (final item in cookieJar) {
          final name = '${item['name'] ?? ''}'.trim();
          if (importantNames.contains(name)) {
            final value = '${item['value'] ?? ''}';
            final domain = '${item['domain'] ?? ''}';
            final path = '${item['path'] ?? '/'}';
            final valuePreview = value.length > 20
                ? '${value.substring(0, 20)}...'
                : value;
            print('   > $name: $valuePreview (domain: $domain, path: $path)');
          }
        }
      }
      int successCount = 0;
      final failedCookies = <String>[];
      for (final item in cookieJar) {
        try {
          final name = '${item['name'] ?? ''}'.trim();
          final value = '${item['value'] ?? ''}';
          if (name.isEmpty) continue;

          final domain = '${item['domain'] ?? ''}'.trim();
          final path = '${item['path'] ?? '/'}'.trim();

          // 根据cookie的domain获取应该种植的URLs
          final urls = _getCookieUrls(domain);
          if (urls.isEmpty) {
            continue;
          }

          // 为每个相关URL种植cookie（明确指定domain）
          bool planted = false;
          for (final url in urls) {
            try {
              // 对于带前导点的domain（如.bgm.tv），需要明确指定
              final cookieDomain = domain.isNotEmpty ? domain : null;

              await manager.setCookie(
                url: WebUri(url),
                name: name,
                value: value,
                domain: cookieDomain,
                path: path.isEmpty ? '/' : path,
                expiresDate: item['expiresDate'] as int?,
                isSecure: item['isSecure'] as bool?,
                isHttpOnly: item['isHttpOnly'] as bool?,
              );
              planted = true;
            } catch (e) {
              if (kDebugMode && name == 'chii_auth') {
                print('   ! 种植 $name 失败: $e');
              }
            }
          }
          if (planted) {
            successCount++;
          } else {
            failedCookies.add(name);
          }
        } catch (e) {
          // 静默失败
        }
      }
      if (kDebugMode) {
        print('   ✓ 种植成功: $successCount/${cookieJar.length}');
        if (failedCookies.isNotEmpty) {
          print('   ! 失败: ${failedCookies.join(", ")}');
        }
      }

      // 验证关键Cookie
      final missingCookies = await _verifyCookies(manager);

      // 如果有关键Cookie缺失，且提供了cookie字符串，则补种
      if (missingCookies.isNotEmpty &&
          cookie != null &&
          cookie.trim().isNotEmpty) {
        if (kDebugMode) {
          print('   ⚠️  使用Cookie字符串补种缺失的: ${missingCookies.join(", ")}');
        }
        await _seedCookiesFromString(cookie, manager, environment);
        await _verifyCookies(manager);
      }
      return;
    }

    // 使用简单的 cookie 字符串
    await _seedCookiesFromString(cookie, manager, environment);
  }

  /// 使用Cookie字符串种植
  static Future<void> _seedCookiesFromString(
    String? cookie,
    CookieManager manager,
    WebViewEnvironment? environment,
  ) async {
    final normalized = (cookie ?? '').trim();
    if (normalized.isEmpty) {
      if (kDebugMode) {
        print('   ⚠️  没有可用的 Cookie');
      }
      return;
    }

    if (kDebugMode) {
      print('   使用 Cookie 字符串补种');
    }

    final parts = normalized.split(';');
    int successCount = 0;
    final importantNames = ['chii_auth', 'chii_sec_id', 'chii_sid'];

    for (final part in parts) {
      final segment = part.trim();
      if (segment.isEmpty) continue;
      final index = segment.indexOf('=');
      if (index <= 0) continue;
      final name = segment.substring(0, index).trim();
      final value = segment.substring(index + 1).trim();
      if (name.isEmpty) continue;

      // 为所有相关域名和子域名种植
      final urlsWithDomain = [
        ('https://bgm.tv/', '.bgm.tv'),
        ('https://bangumi.tv/', '.bangumi.tv'),
        ('https://chii.in/', '.chii.in'),
      ];

      bool planted = false;
      for (final (url, domain) in urlsWithDomain) {
        try {
          // 对关键Cookie，明确设置domain为.bgm.tv等
          await manager.setCookie(
            url: WebUri(url),
            name: name,
            value: value,
            domain: importantNames.contains(name) ? domain : null,
            path: '/',
          );
          planted = true;

          if (kDebugMode && importantNames.contains(name)) {
            print('   > 补种 $name @ $domain');
          }
        } catch (e) {
          if (kDebugMode && importantNames.contains(name)) {
            print('   ! 补种 $name @ $domain 失败: $e');
          }
        }
      }
      if (planted) successCount++;
    }
    if (kDebugMode) {
      print('   ✓ 补种成功: $successCount 个');
    }

    // 验证关键Cookie
    await _verifyCookies(manager);
  }

  /// 验证关键Cookie是否存在，返回缺失的Cookie列表
  static Future<List<String>> _verifyCookies(CookieManager manager) async {
    try {
      // 检查所有相关域名的Cookie（包括根域和带点的域）
      final allCookies = <String, Cookie>{};
      final urlsToCheck = [
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
            // 使用 name 作为key，后面的会覆盖前面的
            allCookies[cookie.name] = cookie;
          }
        } catch (_) {}
      }

      final importantCookies = ['chii_auth', 'chii_sec_id', 'chii_sid'];
      final foundCookies = <String>[];

      for (final name in importantCookies) {
        if (allCookies.containsKey(name)) {
          foundCookies.add(name);
        }
      }

      final missing = importantCookies
          .where((name) => !foundCookies.contains(name))
          .toList();

      if (kDebugMode) {
        if (missing.isEmpty) {
          print('   ✓ 关键Cookie已就位');
        } else {
          print('   ⚠️  缺失: ${missing.join(", ")}');
        }
      }

      return missing;
    } catch (e) {
      if (kDebugMode) {
        print('   ⚠️  Cookie验证失败');
      }
      return ['chii_auth', 'chii_sec_id', 'chii_sid'];
    }
  }

  /// 根据domain获取应该设置Cookie的URLs
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
  // 检查Cookie
  const cookies = document.cookie;
  const hasAuthCookie = cookies.includes('chii_auth') || cookies.includes('chii_sec_id') || cookies.includes('chii_sid');
  
  // 检查登录状态
  const uid = typeof CHOBITS_UID !== 'undefined'
    ? Number.parseInt(CHOBITS_UID, 10) || 0
    : 0;
  const username = typeof CHOBITS_USERNAME !== 'undefined'
    ? String(CHOBITS_USERNAME || '')
    : '';
  
  if (uid <= 0) {
    return { 
      status: 'login_required',
      detail: 'uid=' + uid + ', hasCookie=' + hasAuthCookie + ', cookieCount=' + cookies.split(';').length + ', url=' + location.href
    };
  }
  if (location.pathname === '/' || location.pathname === '') {
    return { 
      status: 'login_required', 
      detail: 'redirected_home, uid=' + uid + ', username=' + username
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
      return (
        item.querySelector('textarea[name="content"]') ||
        item.querySelector('textarea') ||
        item.querySelector('input[type="submit"]') ||
        item.querySelector('button[type="submit"]')
      );
    });
  if (!form) {
    return {
      status: 'form_missing',
      detail: 'form_missing:title=' + (document.title || location.href),
    };
  }
  const textarea =
    form.querySelector('textarea[name="content"]') ||
    form.querySelector('textarea') ||
    form.querySelector('[contenteditable="true"]') ||
    document.querySelector('#content');
  if (!textarea) {
    return {
      status: 'form_missing',
      detail:
        'textarea_missing:submit=' +
        (submit ? submit.outerHTML.slice(0, 240) : '-'),
    };
  }
  if ('value' in textarea) {
    textarea.value = $encoded;
  } else {
    textarea.innerHTML = $encoded.replace(/\\n/g, '<br>');
  }
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
}
