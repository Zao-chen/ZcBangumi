import 'package:flutter/material.dart';

import 'package:zc_bangumi/models/rakuen_topic.dart';
import 'package:zc_bangumi/pages/character_page.dart';
import 'package:zc_bangumi/pages/profile_page.dart';
import 'package:zc_bangumi/pages/rakuen_topic_page.dart';
import 'package:zc_bangumi/pages/subject_page.dart';

enum InternalLinkResult { handled, openInBrowser, failed }

/// 处理Bangumi站内链接，判断是否需要应用内跳转或外部浏览器打开
class InternalLinkHandler {
  static const String bangumiDomainAlias = 'bgm.tv';
  static const String bangumiDomain = 'bangumi.tv';

  /// 处理链接并进行相应的导航
  /// 返回 InternalLinkResult 来表示处理结果
  static InternalLinkResult handleLink(Uri uri, BuildContext? context) {
    // 检查是否是bangumi站内链接
    if (!_isBangumiUrl(uri)) {
      return InternalLinkResult.openInBrowser;
    }

    // 解析链接路径
    final segments = uri.pathSegments;

    // 条目链接: /subject/{id}, /anime/{id}, /book/{id}, /music/{id}, /game/{id}, /real/{id}
    if (segments.length >= 2) {
      final type = segments[0].toLowerCase();
      if ([
        'subject',
        'anime',
        'book',
        'music',
        'game',
        'real',
      ].contains(type)) {
        final id = segments[1];
        if (_isValidId(id)) {
          return _handleSubjectLink(id, context);
        }
      }

      // 角色链接: /character/{id}
      if (type == 'character') {
        final id = segments[1];
        if (_isValidId(id)) {
          return _handleCharacterLink(id, context);
        }
      }

      // 用户资料: /user/{username}
      if (type == 'user') {
        final username = segments[1];
        return _handleUserLink(username, context);
      }

      // 小组话题: /group/topic/{topicId}
      if (type == 'group' && segments[1].toLowerCase() == 'topic') {
        final topicId = segments.length >= 3 ? segments[2] : '';
        if (_isValidId(topicId)) {
          return _handleTopicLink(topicId, 'group', uri, context);
        }
      }

      // 超展开话题: /rakuen/topic/{topicType}/{topicId}
      if (type == 'rakuen' && segments.length >= 4) {
        final section = segments[1].toLowerCase();
        final topicType = segments[2].toLowerCase();
        final topicId = segments[3];
        if (section == 'topic' && _isValidId(topicId)) {
          return _handleTopicLink(topicId, topicType, uri, context);
        }
      }
    }

    // 其他站内链接，用浏览器打开
    return InternalLinkResult.openInBrowser;
  }

  /// 检查URL是否是Bangumi站内链接
  static bool _isBangumiUrl(Uri uri) {
    final host = uri.host.toLowerCase();
    return host.endsWith(bangumiDomainAlias) || host.endsWith(bangumiDomain);
  }

  /// 检查ID是否有效（数字）
  static bool _isValidId(String id) {
    return RegExp(r'^\d+$').hasMatch(id);
  }

  /// 处理条目链接
  static InternalLinkResult _handleSubjectLink(
    String id,
    BuildContext? context,
  ) {
    if (context == null) {
      return InternalLinkResult.failed;
    }

    try {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SubjectPage(subjectId: int.parse(id)),
        ),
      );
      return InternalLinkResult.handled;
    } catch (e) {
      return InternalLinkResult.failed;
    }
  }

  /// 处理角色链接
  static InternalLinkResult _handleCharacterLink(
    String id,
    BuildContext? context,
  ) {
    if (context == null) {
      return InternalLinkResult.failed;
    }

    try {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CharacterPage(characterId: int.parse(id)),
        ),
      );
      return InternalLinkResult.handled;
    } catch (e) {
      return InternalLinkResult.failed;
    }
  }

  /// 处理用户链接
  static InternalLinkResult _handleUserLink(
    String username,
    BuildContext? context,
  ) {
    if (context == null) {
      return InternalLinkResult.failed;
    }

    try {
      final safeUsername = username.trim();
      if (safeUsername.isEmpty) {
        return InternalLinkResult.failed;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtherUserProfilePage(username: safeUsername),
        ),
      );
      return InternalLinkResult.handled;
    } catch (e) {
      return InternalLinkResult.failed;
    }
  }

  /// 处理小组话题链接
  static InternalLinkResult _handleTopicLink(
    String topicId,
    String topicType,
    Uri uri,
    BuildContext? context,
  ) {
    if (context == null) {
      return InternalLinkResult.failed;
    }

    try {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RakuenTopicPage(
            topic: RakuenTopic(
              id: '${topicType}_$topicId',
              type: topicType,
              title: '帖子 #$topicId',
              topicUrl: uri.toString(),
              avatarUrl: '',
              replyCount: 0,
              timeText: '',
            ),
          ),
        ),
      );
      return InternalLinkResult.handled;
    } catch (e) {
      return InternalLinkResult.failed;
    }
  }
}
