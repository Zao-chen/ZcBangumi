import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/episode.dart';
import '../models/rakuen_topic.dart';
import '../models/rakuen_topic_detail.dart';
import '../pages/subject_page.dart';
import '../services/api_client.dart';

class RakuenTopicPage extends StatefulWidget {
  final RakuenTopic topic;
  final Episode? episode;

  const RakuenTopicPage({super.key, required this.topic, this.episode});

  @override
  State<RakuenTopicPage> createState() => _RakuenTopicPageState();
}

class _RakuenTopicPageState extends State<RakuenTopicPage> {
  RakuenTopicDetail? _detail;
  bool _loading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _headerKey = GlobalKey();
  double _headerRevealOffset = 160;
  bool _showCollapsedTitle = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    final shouldShow =
        _scrollController.hasClients &&
        _scrollController.offset >= _headerRevealOffset;
    if (shouldShow == _showCollapsedTitle) return;
    setState(() => _showCollapsedTitle = shouldShow);
  }

  void _updateHeaderRevealOffset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentContext = _headerKey.currentContext;
      if (currentContext == null || !mounted) return;
      final box = currentContext.findRenderObject() as RenderBox?;
      final height = box?.size.height;
      if (height == null) return;
      final nextOffset = height.clamp(120.0, 320.0);
      if ((nextOffset - _headerRevealOffset).abs() < 1) return;
      setState(() => _headerRevealOffset = nextOffset);
      _handleScroll();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final detail = await context.read<ApiClient>().getRakuenTopicDetail(
        topicUrl: widget.topic.topicUrl,
      );
      if (!mounted) return;
      setState(() => _detail = detail);
      _updateHeaderRevealOffset();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '加载失败: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _displayTitle(RakuenTopicDetail? detail) {
    final ep = widget.episode;
    if (ep != null) {
      final name = ep.displayName.trim().isEmpty
          ? '章节讨论'
          : ep.displayName.trim();
      return 'EP.${ep.sortLabel} $name';
    }

    final raw = (detail?.title ?? widget.topic.title).trim();
    if (raw.isEmpty || raw == '主题详情') {
      final fallback = widget.topic.title.trim();
      return fallback.isEmpty ? '讨论详情' : fallback;
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final title = _displayTitle(_detail);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      appBar: AppBar(
        title: _showCollapsedTitle
            ? Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        actions: [
          if (isLandscape)
            IconButton(
              tooltip: '刷新帖子',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          IconButton(
            tooltip: '浏览器打开',
            onPressed: () => _openExternal(widget.topic.topicUrl),
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _detail == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }

    final detail = _detail;
    if (detail == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        final useSplitLayout =
            mediaQuery.orientation == Orientation.landscape &&
            constraints.maxWidth >= 960;
        if (useSplitLayout) {
          return _buildSplitBody(detail, constraints.maxWidth);
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: _buildSingleColumnBody(detail, constraints.maxWidth),
        );
      },
    );
  }

  Widget _buildSingleColumnBody(RakuenTopicDetail detail, double maxWidth) {
    final horizontalPadding = maxWidth > 800
        ? (maxWidth - 900).clamp(0, maxWidth) / 2
        : 12.0;
    final displayTitle = _displayTitle(detail);

    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            12,
            horizontalPadding,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: KeyedSubtree(
              key: _headerKey,
              child: _RakuenTopicHeader(
                detail: detail,
                fallbackTopic: widget.topic,
                episode: widget.episode,
                displayTitle: displayTitle,
              ),
            ),
          ),
        ),
        if (detail.originalPost != null) ...[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12,
              horizontalPadding,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: _SectionTitle(
                label: '楼主',
                trailing: detail.originalPost!.timeText,
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              8,
              horizontalPadding,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: _RakuenPostCard(
                post: detail.originalPost!,
                emphasize: true,
              ),
            ),
          ),
        ],
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            12,
            horizontalPadding,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: _SectionTitle(
              label: '回复',
              trailing: '${detail.replies.length} 条',
            ),
          ),
        ),
        if (detail.replies.isEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              8,
              horizontalPadding,
              0,
            ),
            sliver: const SliverToBoxAdapter(child: _EmptyReplyCard()),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              8,
              horizontalPadding,
              0,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _RakuenPostCard(
                  post: detail.replies[index],
                ),
                childCount: detail.replies.length,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }

  Widget _buildSplitBody(RakuenTopicDetail detail, double maxWidth) {
    final outerPadding = maxWidth >= 1320 ? 20.0 : 12.0;
    const paneGap = 16.0;
    const gutter = 14.0;
    final displayTitle = _displayTitle(detail);

    return Padding(
      padding: EdgeInsets.fromLTRB(outerPadding, 12, outerPadding, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 15,
            child: RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.only(right: gutter),
                    sliver: SliverToBoxAdapter(
                      child: KeyedSubtree(
                        key: _headerKey,
                        child: _RakuenLeadPane(
                          detail: detail,
                          fallbackTopic: widget.topic,
                          episode: widget.episode,
                          displayTitle: displayTitle,
                          originalPost: detail.originalPost,
                        ),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ),
          const SizedBox(width: paneGap),
          Expanded(
            flex: 11,
            child: RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.only(right: gutter),
                    sliver: SliverToBoxAdapter(
                      child: _SectionTitle(
                        label: '回复',
                        trailing: '${detail.replies.length} 条',
                      ),
                    ),
                  ),
                  if (detail.replies.isEmpty)
                    const SliverPadding(
                      padding: EdgeInsets.only(top: 8, right: gutter),
                      sliver: SliverToBoxAdapter(child: _EmptyReplyCard()),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.only(top: 8, right: gutter),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _RakuenPostCard(
                            post: detail.replies[index],
                          ),
                          childCount: detail.replies.length,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _EmptyReplyCard extends StatelessWidget {
  const _EmptyReplyCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(padding: EdgeInsets.all(16), child: Text('暂无回复')),
    );
  }
}

class _RakuenTopicHeader extends StatelessWidget {
  final RakuenTopicDetail detail;
  final RakuenTopic fallbackTopic;
  final Episode? episode;
  final String displayTitle;

  const _RakuenTopicHeader({
    required this.detail,
    required this.fallbackTopic,
    this.episode,
    required this.displayTitle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subjectId = _extractSubjectId(detail.sourceUrl);
    final coverUrl = detail.coverUrl ?? fallbackTopic.avatarUrl;
    final showEpisodeInfo = detail.episodeDescription?.isNotEmpty == true;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CoverImage(
                  url: coverUrl,
                  size: 60,
                  icon: Icons.article_outlined,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayTitle,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                      if (episode != null) ...[
                        const SizedBox(height: 6),
                        _TitleMetaLine(
                          airdate: episode!.airdate,
                          duration: episode!.duration,
                          commentCount: episode!.comment,
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (detail.sourceTitle?.isNotEmpty == true)
                        Text(
                          detail.sourceTitle!,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (detail.sectionTitle?.isNotEmpty == true) ...[
                        const SizedBox(height: 2),
                        Text(
                          detail.sectionTitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (subjectId != null)
                        _HeaderAction(
                          icon: Icons.movie_outlined,
                          label: '条目',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SubjectPage(subjectId: subjectId),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (showEpisodeInfo) ...[
              const SizedBox(height: 12),
              Divider(color: colorScheme.outlineVariant, height: 1),
              const SizedBox(height: 12),
              _EpisodeInfoBlock(episode: episode, detail: detail),
            ],
          ],
        ),
      ),
    );
  }

  static int? _extractSubjectId(String? url) {
    final match = RegExp(r'/subject/(\d+)').firstMatch(url ?? '');
    return match != null ? int.tryParse(match.group(1) ?? '') : null;
  }
}

class _RakuenLeadPane extends StatelessWidget {
  final RakuenTopicDetail detail;
  final RakuenTopic fallbackTopic;
  final Episode? episode;
  final String displayTitle;
  final RakuenPost? originalPost;

  const _RakuenLeadPane({
    required this.detail,
    required this.fallbackTopic,
    this.episode,
    required this.displayTitle,
    required this.originalPost,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subjectId = _RakuenTopicHeader._extractSubjectId(detail.sourceUrl);
    final coverUrl = detail.coverUrl ?? fallbackTopic.avatarUrl;
    final showEpisodeInfo = detail.episodeDescription?.isNotEmpty == true;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CoverImage(
                url: coverUrl,
                size: 72,
                icon: Icons.article_outlined,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayTitle,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                    if (episode != null) ...[
                      const SizedBox(height: 8),
                      _TitleMetaLine(
                        airdate: episode!.airdate,
                        duration: episode!.duration,
                        commentCount: episode!.comment,
                      ),
                    ],
                    if (detail.sourceTitle?.isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Text(
                        detail.sourceTitle!,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (detail.sectionTitle?.isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail.sectionTitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (subjectId != null) ...[
            const SizedBox(height: 14),
            _HeaderAction(
              icon: Icons.movie_outlined,
              label: '条目',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SubjectPage(subjectId: subjectId),
                ),
              ),
            ),
          ],
          if (showEpisodeInfo) ...[
            const SizedBox(height: 16),
            Divider(color: colorScheme.outlineVariant, height: 1),
            const SizedBox(height: 14),
            _EpisodeInfoBlock(episode: episode, detail: detail),
          ],
          if (originalPost != null) ...[
            const SizedBox(height: 18),
            Divider(color: colorScheme.outlineVariant, height: 1),
            const SizedBox(height: 18),
            _RakuenPostBlock(
              post: originalPost!,
              avatarSize: 48,
              titleFontSize: 15,
              metaFontSize: 11,
              contentFontSize: 15,
              contentHeight: 1.5,
            ),
          ],
        ],
      ),
    );
  }
}

class _RakuenPostCard extends StatelessWidget {
  final RakuenPost post;
  final bool emphasize;

  const _RakuenPostCard({
    required this.post,
    this.emphasize = false,
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
        child: _RakuenPostBlock(
          post: post,
          avatarSize: 44,
          titleFontSize: 14,
          metaFontSize: 11,
          contentFontSize: 14,
          contentHeight: 1.42,
        ),
      ),
    );
  }
}

class _EpisodeInfoBlock extends StatelessWidget {
  final Episode? episode;
  final RakuenTopicDetail detail;

  const _EpisodeInfoBlock({this.episode, required this.detail});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final desc = detail.episodeDescription?.trim();
    final hasDesc = desc != null && desc.isNotEmpty;
    if (!hasDesc) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              desc,
              style: TextStyle(
                fontSize: 14,
                height: 1.42,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleMetaLine extends StatelessWidget {
  final String airdate;
  final String duration;
  final int commentCount;

  const _TitleMetaLine({
    required this.airdate,
    required this.duration,
    required this.commentCount,
  });

  @override
  Widget build(BuildContext context) {
    final safeAirdate = airdate.trim().isEmpty ? '未知' : airdate.trim();
    final safeDuration = duration.trim().isEmpty ? '未知' : duration.trim();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _MetaTag(
          icon: Icons.calendar_today_outlined,
          label: '首播: $safeAirdate',
        ),
        _MetaTag(icon: Icons.timer_outlined, label: '时长: $safeDuration'),
        _MetaTag(icon: Icons.forum_outlined, label: '讨论: $commentCount'),
      ],
    );
  }
}

class _MetaTag extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaTag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _RakuenPostBlock extends StatelessWidget {
  final RakuenPost post;
  final double avatarSize;
  final double titleFontSize;
  final double metaFontSize;
  final double contentFontSize;
  final double contentHeight;

  const _RakuenPostBlock({
    required this.post,
    required this.avatarSize,
    required this.titleFontSize,
    required this.metaFontSize,
    required this.contentFontSize,
    required this.contentHeight,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(url: post.avatarUrl, size: avatarSize),
            const SizedBox(width: 12),
            Expanded(
              child: _PostBody(
                nickname: post.nickname,
                sign: post.sign,
                floorText: post.floor,
                timeText: post.timeText,
                content: post.content,
                titleFontSize: titleFontSize,
                metaFontSize: metaFontSize,
                contentFontSize: contentFontSize,
                contentHeight: contentHeight,
                colorScheme: colorScheme,
              ),
            ),
          ],
        ),
        if (post.subReplies.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: EdgeInsets.only(left: avatarSize + 12),
            child: Column(
              children: post.subReplies.map((reply) {
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
                      _Avatar(url: reply.avatarUrl, size: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PostBody(
                          nickname: reply.nickname,
                          sign: reply.sign,
                          floorText: reply.floor,
                          timeText: reply.timeText,
                          content: reply.content,
                          titleFontSize: 13,
                          metaFontSize: 10,
                          contentFontSize: 13,
                          contentHeight: 1.4,
                          colorScheme: colorScheme,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _PostBody extends StatelessWidget {
  final String nickname;
  final String? sign;
  final String floorText;
  final String timeText;
  final String content;
  final double titleFontSize;
  final double metaFontSize;
  final double contentFontSize;
  final double contentHeight;
  final ColorScheme colorScheme;

  const _PostBody({
    required this.nickname,
    required this.sign,
    required this.floorText,
    required this.timeText,
    required this.content,
    required this.titleFontSize,
    required this.metaFontSize,
    required this.contentFontSize,
    required this.contentHeight,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: DefaultTextStyle.of(context).style,
                  children: [
                    TextSpan(
                      text: nickname,
                      style: TextStyle(
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (sign?.isNotEmpty == true)
                      TextSpan(
                        text: ' ($sign)',
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
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$floorText  $timeText',
                  style: TextStyle(
                    fontSize: metaFontSize,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        SelectableText(
          content.isEmpty ? ' ' : content,
          style: TextStyle(fontSize: contentFontSize, height: contentHeight),
        ),
      ],
    );
  }
}

class _CoverImage extends StatelessWidget {
  final String url;
  final double size;
  final IconData icon;

  const _CoverImage({
    required this.url,
    required this.size,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.2),
      child: SizedBox(
        width: size,
        height: size,
        child: url.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    Container(color: colorScheme.surfaceContainerHighest),
                errorWidget: (context, url, error) => Container(
                  color: colorScheme.surfaceContainerHighest,
                  child: Icon(icon),
                ),
              )
            : Container(
                color: colorScheme.surfaceContainerHighest,
                child: Icon(icon),
              ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String url;
  final double size;

  const _Avatar({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.25),
      child: SizedBox(
        width: size,
        height: size,
        child: url.isNotEmpty
            ? CachedNetworkImage(
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

class _SectionTitle extends StatelessWidget {
  final String label;
  final String trailing;

  const _SectionTitle({required this.label, required this.trailing});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        Text(
          trailing,
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _HeaderAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onTap,
    );
  }
}
