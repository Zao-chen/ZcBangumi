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
  bool _replySubmitting = false;
  bool _topicSubmitting = false;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _replyScrollController = ScrollController();
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
    _replyScrollController.dispose();
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
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FloatingActionButton.extended(
          onPressed: _replySubmitting ? null : _showReplyComposer,
          icon: _replySubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.reply_rounded),
          label: Text(_replySubmitting ? '发送中' : '回复'),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Future<void> _showReplyComposer() async {
    if (!context.read<ApiClient>().hasWebCookie) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在设置中导入网页 Cookie')));
      return;
    }
    final result = await showModalBottomSheet<_RakuenComposeResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          const _RakuenComposerSheet(title: '回复主题', submitLabel: '发送回复'),
    );
    if (!mounted || result == null) return;

    setState(() {
      _replySubmitting = true;
    });

    try {
      final submitTopicUrl = _detail?.canonicalUrl ?? widget.topic.topicUrl;
      final api = context.read<ApiClient>();
      await api.createRakuenReply(
        topicUrl: submitTopicUrl,
        content: result.content,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('回复已发送')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e.toString();
      String displayMsg = '发送回复失败: $e';

      // 提供更友好的错误提示
      if (errorMsg.contains('login_required') || errorMsg.contains('未登录')) {
        displayMsg = 'Cookie 未登录或已过期\n请在设置中重新"自动获取 Cookie"';
      } else if (errorMsg.contains('form_missing')) {
        displayMsg = '未找到回复表单\n该主题可能不支持回复';
      } else if (errorMsg.contains('网页回复超时')) {
        displayMsg = '回复超时，请检查网络连接后重试';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(displayMsg),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _replySubmitting = false;
        });
      }
    }
  }

  Future<void> _showNewTopicComposer() async {
    if (!context.read<ApiClient>().hasWebCookie) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在设置中导入网页 Cookie')));
      return;
    }
    final detail = _detail;
    final sourceUrl = detail?.sourceUrl;
    if (sourceUrl == null || !_canCreateTopic(sourceUrl)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前来源暂不支持发帖')));
      return;
    }

    final result = await showModalBottomSheet<_RakuenComposeResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _RakuenComposerSheet(
        title: '发表新主题',
        submitLabel: '发帖',
        showTitleField: true,
        initialTitle: detail?.sourceTitle,
      ),
    );
    if (!mounted || result == null) return;

    setState(() {
      _topicSubmitting = true;
    });

    try {
      final createdUrl = await context.read<ApiClient>().createRakuenTopic(
        sourceUrl: sourceUrl,
        title: result.title,
        content: result.content,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('主题已发表')));
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RakuenTopicPage(
            topic: RakuenTopic(
              id: '',
              type: _inferTopicTypeFromUrl(createdUrl),
              title: result.title,
              topicUrl: createdUrl,
              avatarUrl: detail?.coverUrl ?? widget.topic.avatarUrl,
              replyCount: 0,
              timeText: '',
              sourceTitle: detail?.sourceTitle,
              sourceUrl: sourceUrl,
              authorName: null,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e.toString();
      String displayMsg = '发帖失败: $e';

      // 提供更友好的错误提示
      if (errorMsg.contains('login_required') || errorMsg.contains('未登录')) {
        displayMsg = 'Cookie 未登录或已过期\n请在设置中重新"自动获取 Cookie"';
      } else if (errorMsg.contains('form_missing') ||
          errorMsg.contains('没有可用的发帖表单')) {
        displayMsg = '未找到发帖表单\n该来源可能不支持发帖';
      } else if (errorMsg.contains('暂不支持发帖')) {
        displayMsg = '当前来源不支持发帖功能';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(displayMsg),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _topicSubmitting = false;
        });
      }
    }
  }

  static bool _canCreateTopic(String? sourceUrl) {
    final value = sourceUrl ?? '';
    return RegExp(r'/group/[^/?#]+').hasMatch(value) ||
        RegExp(r'/subject/\d+').hasMatch(value);
  }

  static String _inferTopicTypeFromUrl(String url) {
    if (url.contains('/group/topic/')) return 'group';
    if (url.contains('/subject/topic/')) return 'subject';
    return 'group';
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
        final isLandscape = mediaQuery.orientation == Orientation.landscape;
        final useSplitLayout = isLandscape && constraints.maxWidth >= 960;

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

    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 0),
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
            padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 0),
            sliver: SliverToBoxAdapter(
              child: _SectionTitle(
                label: '楼主',
                trailing: detail.originalPost!.timeText,
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 0),
            sliver: SliverToBoxAdapter(
              child: _RakuenPostCard(
                post: detail.originalPost!,
                emphasize: true,
              ),
            ),
          ),
        ],
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 0),
          sliver: SliverToBoxAdapter(
            child: _SectionTitle(
              label: '回复',
              trailing: '${detail.replies.length} 条',
            ),
          ),
        ),
        if (detail.replies.isEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 24),
            sliver: const SliverToBoxAdapter(
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
            padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                return _RakuenPostCard(post: detail.replies[index]);
              }, childCount: detail.replies.length),
            ),
          ),
      ],
    );
  }

  Widget _buildSplitBody(RakuenTopicDetail detail, double maxWidth) {
    final outerPadding = maxWidth >= 1320 ? 20.0 : 12.0;
    const paneGap = 16.0;
    const scrollbarGutter = 14.0;

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
                    padding: const EdgeInsets.only(right: scrollbarGutter),
                    sliver: SliverToBoxAdapter(
                      child: KeyedSubtree(
                        key: _headerKey,
                        child: _RakuenLeadPane(
                          detail: detail,
                          fallbackTopic: widget.topic,
                          originalPost: detail.originalPost,
                        ),
                      ),
                    ),
                  ),
                  const SliverPadding(
                    padding: EdgeInsets.only(right: scrollbarGutter, bottom: 24),
                    sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
                  ),
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
                controller: _replyScrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.only(right: scrollbarGutter),
                    sliver: SliverToBoxAdapter(
                      child: _SectionTitle(
                        label: '回复',
                        trailing: '${detail.replies.length} 条',
                      ),
                    ),
                  ),
                  if (detail.replies.isEmpty)
                    const SliverPadding(
                      padding: EdgeInsets.only(top: 8, right: scrollbarGutter),
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
                      padding: const EdgeInsets.only(
                        top: 8,
                        right: scrollbarGutter,
                        bottom: 24,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          return _RakuenPostCard(post: detail.replies[index]);
                        }, childCount: detail.replies.length),
                      ),
                    ),
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

class _RakuenLeadPane extends StatelessWidget {
  final RakuenTopicDetail detail;
  final RakuenTopic fallbackTopic;
  final RakuenPost? originalPost;

  const _RakuenLeadPane({
    required this.detail,
    required this.fallbackTopic,
    required this.originalPost,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subjectId = _RakuenTopicHeader._extractSubjectId(detail.sourceUrl);
    final coverUrl = detail.coverUrl ?? fallbackTopic.avatarUrl;

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
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: coverUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: coverUrl,
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
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                    if (detail.sourceTitle != null &&
                        detail.sourceTitle!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        detail.sourceTitle!,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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
          if (originalPost != null) ...[
            const SizedBox(height: 18),
            Divider(color: colorScheme.outlineVariant, height: 1),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(url: originalPost!.avatarUrl, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: _PostBody(
                    nickname: originalPost!.nickname,
                    sign: originalPost!.sign,
                    floorText: originalPost!.floor,
                    timeText: originalPost!.timeText,
                    content: originalPost!.content,
                    titleFontSize: 15,
                    metaFontSize: 11,
                    contentFontSize: 15,
                    contentHeight: 1.5,
                    colorScheme: colorScheme,
                  ),
                ),
              ],
            ),
            if (originalPost!.subReplies.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(left: 60),
                child: Column(
                  children: originalPost!.subReplies.map((reply) {
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
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
        ],
      ),
    );
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

class _RakuenComposeResult {
  final String title;
  final String content;

  const _RakuenComposeResult({this.title = '', required this.content});
}

class _RakuenComposerSheet extends StatefulWidget {
  final String title;
  final String submitLabel;
  final bool showTitleField;
  final String? initialTitle;

  const _RakuenComposerSheet({
    required this.title,
    required this.submitLabel,
    this.showTitleField = false,
    this.initialTitle,
  });

  @override
  State<_RakuenComposerSheet> createState() => _RakuenComposerSheetState();
}

class _RakuenComposerSheetState extends State<_RakuenComposerSheet> {
  late final TextEditingController _titleController;
  final TextEditingController _contentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (widget.showTitleField && title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('标题不能为空')));
      return;
    }
    if (content.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('正文不能为空')));
      return;
    }
    Navigator.of(
      context,
    ).pop(_RakuenComposeResult(title: title, content: content));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (widget.showTitleField) ...[
            TextField(
              controller: _titleController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '标题',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _contentController,
            minLines: 6,
            maxLines: 10,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              labelText: '正文',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submit,
              child: Text(widget.submitLabel),
            ),
          ),
        ],
      ),
    );
  }
}
