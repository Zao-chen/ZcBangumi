import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'internal_link_handler.dart';

class LinkNavigator {
  const LinkNavigator._();

  /// 优先尝试站内实现，未支持时再外部浏览器打开。
  static Future<bool> open(BuildContext context, Uri uri) async {
    final result = InternalLinkHandler.handleLink(uri, context);
    if (result == InternalLinkResult.handled) {
      return true;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// 直接使用系统浏览器打开，不做任何站内链接拦截。
  static Future<bool> openBrowser(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
