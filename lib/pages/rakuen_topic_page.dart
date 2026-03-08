import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/rakuen_topic.dart';
import '../models/rakuen_topic_detail.dart';
import '../pages/subject_page.dart';
import '../services/api_client.dart';

class RakuenTopicPage extends StatefulWidget {
  final RakuenTopic topic;

  const RakuenTopicPage({super.key, required this.topic});

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
    setState(() {
      _showCollapsedTitle = shouldShow;
    });
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
      setState(() {
        _headerRevealOffset = nextOffset;
      });
      _handleScroll();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = context.read<ApiClient>();
      final detail = await api.getRakuenTopicDetail(
        topicUrl: widget.topic.topicUrl,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
      });
      _updateHeaderRevealOffset();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _detail?.title ?? widget.topic.title;

    return Scaffold(
      appBar: AppBar(
        title: _showCollapsedTitle
            ? Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        actions: [
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

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            sliver: SliverToBoxAdapter(
              child: KeyedSubtree(
                key: _headerKey,
                child: _RakuenTopicHeader(
                  detail: detail,
                  fallbackTopic: widget.topic,
                ),
              ),
            ),
          ),
          if (detail.originalPost != null) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              sliver: SliverToBoxAdapter(
                child: _SectionTitle(
                  label: '楼主',
                  trailing: detail.originalPost!.timeText,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              sliver: SliverToBoxAdapter(
                child: _RakuenPostCard(
                  post: detail.originalPost!,
                  emphasize: true,
                ),
              ),
            ),
          ],
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            sliver: SliverToBoxAdapter(
              child: _SectionTitle(
                label: '回复',
                trailing: '${detail.replies.length} 条',
              ),
            ),
          ),
          if (detail.replies.isEmpty)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 24),
              sliver: SliverToBoxAdapter(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('暂无回复'),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  return _RakuenPostCard(post: detail.replies[index]);
                }, childCount: detail.replies.length),
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

class _RakuenTopicHeader extends StatelessWidget {
  final RakuenTopicDetail detail;
  final RakuenTopic fallbackTopic;

  const _RakuenTopicHeader({required this.detail, required this.fallbackTopic});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subjectId = _extractSubjectId(detail.sourceUrl);

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 60,
                height: 60,
                child: (detail.coverUrl ?? fallbackTopic.avatarUrl).isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: detail.coverUrl ?? fallbackTopic.avatarUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: colorScheme.surfaceContainerHighest,
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.article_outlined),
                        ),
                      )
                    : Container(
                        color: colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.article_outlined),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (detail.sourceTitle != null &&
                      detail.sourceTitle!.isNotEmpty)
                    Text(
                      detail.sourceTitle!,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (detail.sectionTitle != null &&
                      detail.sectionTitle!.isNotEmpty) ...[
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
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
                ],
              ),
            ),
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

class _RakuenPostCard extends StatelessWidget {
  final RakuenPost post;
  final bool emphasize;

  const _RakuenPostCard({required this.post, this.emphasize = false});

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(url: post.avatarUrl, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: _PostBody(
                    nickname: post.nickname,
                    sign: post.sign,
                    floorText: post.floor,
                    timeText: post.timeText,
                    content: post.content,
                    titleFontSize: 14,
                    metaFontSize: 11,
                    contentFontSize: 14,
                    contentHeight: 1.42,
                    colorScheme: colorScheme,
                  ),
                ),
              ],
            ),
            if (post.subReplies.isNotEmpty) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 56),
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
        ),
      ),
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
                    if (sign != null && sign!.isNotEmpty)
                      TextSpan(
                        text: ' (${sign!})',
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
            Text(
              '$floorText  $timeText',
              style: TextStyle(
                fontSize: metaFontSize,
                color: colorScheme.onSurfaceVariant,
              ),
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
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
