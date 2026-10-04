import 'bangumi_network_image.dart';
import 'package:flutter/material.dart';

import '../models/comment.dart';
import 'bangumi_content_view.dart';

String formatBangumiPostTime({DateTime? dateTime, String rawTime = ''}) {
  String format(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-${local.month}-${local.day} $hour:$minute';
  }

  if (dateTime != null && dateTime.millisecondsSinceEpoch > 0) {
    return format(dateTime);
  }

  final normalized = rawTime.trim();
  if (normalized.isEmpty) return '';
  final parsed = DateTime.tryParse(normalized);
  if (parsed != null) return format(parsed);

  final match = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{1,2}))?$',
  ).firstMatch(normalized);
  if (match == null) return normalized;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.tryParse(match.group(4) ?? '') ?? 0;
  final minute = int.tryParse(match.group(5) ?? '') ?? 0;
  return format(DateTime(year, month, day, hour, minute));
}

String formatBangumiPostMeta({
  String floorText = '',
  DateTime? dateTime,
  String rawTime = '',
}) {
  final timeText = formatBangumiPostTime(dateTime: dateTime, rawTime: rawTime);
  return [
    floorText.trim(),
    timeText,
  ].where((part) => part.isNotEmpty).join('  ');
}

/// 帖子与楼中楼共用的轻量展示模型。
class BangumiPostData {
  final String id;
  final String authorKey;
  final String authorName;
  final String avatarUrl;
  final String? sign;
  final String metaText;
  final String content;
  final String? contentHtml;
  final String? emptyContentLabel;
  final int rating;
  final bool spoiler;
  final int replyCount;

  const BangumiPostData({
    required this.id,
    required this.authorKey,
    required this.authorName,
    required this.avatarUrl,
    this.sign,
    required this.metaText,
    required this.content,
    this.contentHtml,
    this.emptyContentLabel,
    this.rating = 0,
    this.spoiler = false,
    this.replyCount = 0,
  });

  factory BangumiPostData.fromComment(
    Comment comment, {
    String floorText = '',
    DateTime? dateTime,
    String? emptyContentLabel,
  }) {
    final rawId = comment.user['id'];
    final userId = rawId is num
        ? rawId.toInt()
        : int.tryParse(rawId?.toString() ?? '') ?? 0;
    return BangumiPostData(
      id: comment.id.toString(),
      authorKey: userId > 0 ? userId.toString() : '',
      authorName: comment.userName,
      avatarUrl: comment.userAvatar,
      metaText: formatBangumiPostMeta(
        floorText: floorText,
        dateTime: dateTime ?? comment.createdAt,
      ),
      content: comment.content,
      contentHtml: comment.contentHtml,
      emptyContentLabel:
          emptyContentLabel ?? (comment.state == 6 ? '该评论已删除' : null),
      rating: comment.rating,
      spoiler: comment.spoiler == 1,
      replyCount: comment.replyItems.isEmpty ? comment.replies : 0,
    );
  }
}

class BangumiPostAvatar extends StatelessWidget {
  final String url;
  final double size;

  const BangumiPostAvatar({super.key, required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: SizedBox(
        width: size,
        height: size,
        child: url.isNotEmpty
            ? BangumiNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    Container(color: colorScheme.surfaceContainerHighest),
                errorWidget: (context, url, error) => Container(
                  color: colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.person_outline, size: size * 0.45),
                ),
              )
            : Container(
                color: colorScheme.surfaceContainerHighest,
                child: Icon(Icons.person_outline, size: size * 0.45),
              ),
      ),
    );
  }
}

class BangumiPostBody extends StatelessWidget {
  final BangumiPostData post;
  final double titleFontSize;
  final double metaFontSize;
  final double contentFontSize;
  final double contentHeight;
  final VoidCallback? onUserTap;

  const BangumiPostBody({
    super.key,
    required this.post,
    required this.titleFontSize,
    required this.metaFontSize,
    required this.contentFontSize,
    required this.contentHeight,
    this.onUserTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayName = post.authorName.trim().isEmpty
        ? post.authorKey
        : post.authorName;
    final emptyLabel = post.emptyContentLabel?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: onUserTap,
                child: RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: DefaultTextStyle.of(context).style,
                    children: [
                      TextSpan(
                        text: displayName,
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.primary,
                        ),
                      ),
                      if (post.sign?.isNotEmpty == true)
                        TextSpan(
                          text: ' (${post.sign})',
                          style: TextStyle(
                            fontSize: metaFontSize,
                            fontWeight: FontWeight.w400,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.72,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (post.metaText.trim().isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                post.metaText,
                style: TextStyle(
                  fontSize: metaFontSize,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        if (post.rating > 0 || post.spoiler) ...[
          const SizedBox(height: 2),
          _BangumiCommentBadges(post: post),
        ],
        const SizedBox(height: 4),
        if (post.content.trim().isEmpty && emptyLabel?.isNotEmpty == true)
          Text(
            emptyLabel!,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: contentFontSize,
              height: contentHeight,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          BangumiContentView(
            text: post.content,
            html: post.contentHtml,
            style: TextStyle(fontSize: contentFontSize, height: contentHeight),
          ),
        if (post.replyCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            '${post.replyCount} 条回复',
            style: TextStyle(
              fontSize: metaFontSize,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _BangumiCommentBadges extends StatelessWidget {
  final BangumiPostData post;

  const _BangumiCommentBadges({required this.post});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (post.rating > 0)
          Semantics(
            label: '评分 ${post.rating} 分',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                5,
                (starIndex) => Icon(
                  starIndex < post.rating ~/ 2 ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                  size: 12,
                ),
              ),
            ),
          ),
        if (post.spoiler)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red[100],
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '剧透',
              style: TextStyle(color: Colors.red[700], fontSize: 10),
            ),
          ),
      ],
    );
  }
}

class BangumiPostBlock extends StatelessWidget {
  final BangumiPostData post;
  final List<BangumiPostData> replies;
  final double avatarSize;
  final double titleFontSize;
  final double metaFontSize;
  final double contentFontSize;
  final double contentHeight;
  final String nestedReplyKeyPrefix;
  final Key? nestedRepliesKey;
  final ValueChanged<BangumiPostData>? onUserTap;

  const BangumiPostBlock({
    super.key,
    required this.post,
    this.replies = const [],
    required this.avatarSize,
    required this.titleFontSize,
    required this.metaFontSize,
    required this.contentFontSize,
    required this.contentHeight,
    this.nestedReplyKeyPrefix = 'bangumi_nested_reply',
    this.nestedRepliesKey,
    this.onUserTap,
  });

  @override
  Widget build(BuildContext context) {
    final canOpenUser = onUserTap != null && post.authorKey.trim().isNotEmpty;
    final openUser = canOpenUser ? () => onUserTap!(post) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: openUser,
              child: BangumiPostAvatar(url: post.avatarUrl, size: avatarSize),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: BangumiPostBody(
                post: post,
                titleFontSize: titleFontSize,
                metaFontSize: metaFontSize,
                contentFontSize: contentFontSize,
                contentHeight: contentHeight,
                onUserTap: openUser,
              ),
            ),
          ],
        ),
        if (replies.isNotEmpty) ...[
          const SizedBox(height: 12),
          BangumiNestedReplyList(
            key: nestedRepliesKey,
            replies: replies,
            leftIndent: avatarSize + 12,
            itemKeyPrefix: nestedReplyKeyPrefix,
            onUserTap: onUserTap,
          ),
        ],
      ],
    );
  }
}

class BangumiPostCard extends StatelessWidget {
  final BangumiPostData post;
  final List<BangumiPostData> replies;
  final bool emphasize;
  final String nestedReplyKeyPrefix;
  final Key? nestedRepliesKey;
  final ValueChanged<BangumiPostData>? onUserTap;

  const BangumiPostCard({
    super.key,
    required this.post,
    this.replies = const [],
    this.emphasize = false,
    this.nestedReplyKeyPrefix = 'bangumi_nested_reply',
    this.nestedRepliesKey,
    this.onUserTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: emphasize
          ? colorScheme.primaryContainer.withValues(alpha: 0.35)
          : colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: BangumiPostBlock(
          post: post,
          replies: replies,
          avatarSize: 44,
          titleFontSize: 14,
          metaFontSize: 11,
          contentFontSize: 14,
          contentHeight: 1.42,
          nestedReplyKeyPrefix: nestedReplyKeyPrefix,
          nestedRepliesKey: nestedRepliesKey,
          onUserTap: onUserTap,
        ),
      ),
    );
  }
}

class BangumiNestedReplyList extends StatelessWidget {
  final List<BangumiPostData> replies;
  final double leftIndent;
  final String itemKeyPrefix;
  final ValueChanged<BangumiPostData>? onUserTap;

  const BangumiNestedReplyList({
    super.key,
    required this.replies,
    required this.leftIndent,
    this.itemKeyPrefix = 'bangumi_nested_reply',
    this.onUserTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: leftIndent),
      child: Column(
        children: [
          for (final reply in replies)
            _NestedReplyCard(
              key: ValueKey('${itemKeyPrefix}_${reply.id}'),
              reply: reply,
              onUserTap: onUserTap,
            ),
        ],
      ),
    );
  }
}

class _NestedReplyCard extends StatelessWidget {
  final BangumiPostData reply;
  final ValueChanged<BangumiPostData>? onUserTap;

  const _NestedReplyCard({
    super.key,
    required this.reply,
    required this.onUserTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canOpenUser = onUserTap != null && reply.authorKey.trim().isNotEmpty;
    final openUser = canOpenUser ? () => onUserTap!(reply) : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: openUser,
            child: BangumiPostAvatar(url: reply.avatarUrl, size: 32),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: BangumiPostBody(
              post: reply,
              titleFontSize: 13,
              metaFontSize: 10,
              contentFontSize: 13,
              contentHeight: 1.4,
              onUserTap: openUser,
            ),
          ),
        ],
      ),
    );
  }
}
