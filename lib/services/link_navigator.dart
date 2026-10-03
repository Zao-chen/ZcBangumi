import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import 'internal_link_handler.dart';
import 'bangumi_endpoint_service.dart';

class LinkNavigator {
  const LinkNavigator._();

  /// 优先尝试站内实现，未支持时再外部浏览器打开。
  static Future<bool> open(BuildContext context, Uri uri) async {
    final result = InternalLinkHandler.handleLink(uri, context);
    if (result == InternalLinkResult.handled) {
      return true;
    }
    final endpoints = context.read<BangumiEndpointService?>();
    return launchUrl(
      endpoints?.resolveUri(uri) ?? uri,
      mode: LaunchMode.externalApplication,
    );
  }

  /// 直接使用系统浏览器打开，不做任何站内链接拦截。
  static Future<bool> openBrowser(
    Uri uri, {
    BangumiEndpointService? endpoints,
  }) {
    return launchUrl(
      endpoints?.resolveUri(uri) ?? uri,
      mode: LaunchMode.externalApplication,
    );
  }

  static Future<bool> openBrowserFromContext(BuildContext context, Uri uri) {
    return openBrowser(uri, endpoints: context.read<BangumiEndpointService?>());
  }
}
