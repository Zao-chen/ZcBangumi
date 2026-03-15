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
  RakuenPost? _replyTarget;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _replyScrollController = ScrollController();
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
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
    _replyController.dispose();
    _replyFocusNode.dispose();
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

  bool get _canShowReplyAction {
    final detail = _detail;
    return detail != null && detail.canReply;
  }

  String _replyDraftPrefixFor(RakuenPost post) {
    final username = post.username.trim();
    if (username.isNotEmpty) {
      return '@$username ';
    }
    final nickname = post.nickname.trim();
    if (nickname.isNotEmpty) {
      return '回复 ${post.floor} $nickname：\n';
    }
    return '回复 ${post.floor}：\n';
  }

  String _replyTargetTitle(RakuenPost? post) {
    if (post == null) return '添加新回复';
    final nickname = post.nickname.trim();
    final label = nickname.isNotEmpty ? nickname : post.username.trim();
    return label.isNotEmpty ? '回复 ${post.floor} $label' : '回复 ${post.floor}';
  }

  String? _replyTargetSubtitle(RakuenPost? post) {
    if (post == null) return null;
    final username = post.username.trim();
    if (username.isNotEmpty) {
      return '@$username';
    }
    final nickname = post.nickname.trim();
    return nickname.isNotEmpty ? '发送给 $nickname' : null;
  }

  void _prepareReplyDraft(RakuenPost? target) {
    final previousTarget = _replyTarget;
    final previousPrefix = previousTarget == null
        ? ''
        : _replyDraftPrefixFor(previousTarget);
    final nextPrefix = target == null ? '' : _replyDraftPrefixFor(target);

    var nextText = _replyController.text;
    if (nextText.isEmpty) {
      nextText = nextPrefix;
    } else if (previousPrefix.isNotEmpty &&
        nextText.startsWith(previousPrefix)) {
      nextText = '$nextPrefix${nextText.substring(previousPrefix.length)}';
    } else if (nextPrefix.isNotEmpty && !nextText.startsWith(nextPrefix)) {
      nextText = '$nextPrefix$nextText';
    }

    _replyTarget = target;
    _replyController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
  }

  Future<void> _openReplyComposer([RakuenPost? target]) async {
    final detail = _detail;
    if (detail == null) return;
    if (!context.read<ApiClient>().hasWebCookie) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在设置中登录 Bangumi 网页会话')));
      return;
    }
    if (!detail.canReply) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前主题没有可用的回复表单')));
      return;
    }
    _prepareReplyDraft(target);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _RakuenInlineReplyCard(
              title: _replyTargetTitle(target),
              subtitle: _replyTargetSubtitle(target),
              controller: _replyController,
              focusNode: _replyFocusNode,
              submitting: _replySubmitting,
              onSubmit: () async {
                final ok = await _submitInlineReply();
                if (ok && sheetContext.mounted) {
                  Navigator.of(sheetContext).pop();
                }
              },
            ),
          ),
        );
      },
    );
  }

  Future<bool> _submitInlineReply() async {
    if (_replySubmitting) return false;
    if (!context.read<ApiClient>().hasWebCookie) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在设置中登录 Bangumi 网页会话')));
      return false;
    }

    final content = _replyController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('回复内容不能为空')));
      return false;
    }

    setState(() => _replySubmitting = true);

    try {
      final submitTopicUrl = _detail?.canonicalUrl ?? widget.topic.topicUrl;
      await context.read<ApiClient>().submitRakuenReply(
        topicUrl: submitTopicUrl,
        content: content,
        replyToPost: _replyTarget,
      );
      if (!mounted) return false;
      _replyTarget = null;
      _replyController.clear();
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('回复已发送')));
      await _load();
      return true;
    } catch (e) {
      if (!mounted) return false;
      final msg = e.toString();
      var displayMsg = '发送回复失败: $e';
      if (msg.contains('login_required') || msg.contains('未登录')) {
        displayMsg = '当前网页会话未登录或已过期，请在设置中重新登录';
      } else if (msg.contains('form_missing') || msg.contains('没有可用的回复表单')) {
        displayMsg = '当前主题没有可用的回复表单';
      } else if (msg.contains('网页回复超时')) {
        displayMsg = '回复超时，请检查网络后重试';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(displayMsg),
          duration: const Duration(seconds: 4),
        ),
      );
      return false;
    } finally {
      if (mounted) setState(() => _replySubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _detail?.title ?? widget.topic.title;
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
      floatingActionButton: _canShowReplyAction
          ? FloatingActionButton.extended(
              onPressed: _replySubmitting ? null : () => _openReplyComposer(),
              icon: _replySubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.reply_rounded),
              label: Text(_replySubmitting ? '发送中' : '回复'),
            )
          : null,
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
                onReply: (post) => _openReplyComposer(post),
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
                  onReply: (post) => _openReplyComposer(post),
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
                          originalPost: detail.originalPost,
                          onReply: (post) => _openReplyComposer(post),
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
                controller: _replyScrollController,
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
                            onReply: (post) => _openReplyComposer(post),
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

  const _RakuenTopicHeader({required this.detail, required this.fallbackTopic});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subjectId = _extractSubjectId(detail.sourceUrl);
    final coverUrl = detail.coverUrl ?? fallbackTopic.avatarUrl;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CoverImage(url: coverUrl, size: 60, icon: Icons.article_outlined),
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
  final ValueChanged<RakuenPost>? onReply;

  const _RakuenLeadPane({
    required this.detail,
    required this.fallbackTopic,
    required this.originalPost,
    this.onReply,
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
                      detail.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
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
              onReply: onReply,
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
  final ValueChanged<RakuenPost>? onReply;

  const _RakuenPostCard({
    required this.post,
    this.emphasize = false,
    this.onReply,
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
          onReply: onReply,
        ),
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
  final ValueChanged<RakuenPost>? onReply;

  const _RakuenPostBlock({
    required this.post,
    required this.avatarSize,
    required this.titleFontSize,
    required this.metaFontSize,
    required this.contentFontSize,
    required this.contentHeight,
    this.onReply,
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
                onReply: onReply == null ? null : () => onReply!(post),
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
                          onReply: onReply == null
                              ? null
                              : () => onReply!(reply),
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

class _RakuenInlineReplyCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool submitting;
  final Future<void> Function() onSubmit;

  const _RakuenInlineReplyCard({
    required this.title,
    this.subtitle,
    required this.controller,
    required this.focusNode,
    required this.submitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 8,
              maxLines: 12,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: '输入回复内容',
                filled: true,
                fillColor: colorScheme.surfaceContainerLowest,
                contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 1.4,
                  ),
                ),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: submitting ? null : onSubmit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('发送回复'),
              ),
            ),
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
  final VoidCallback? onReply;

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
    this.onReply,
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
                if (onReply != null)
                  TextButton(
                    onPressed: onReply,
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text('回复', style: TextStyle(fontSize: metaFontSize)),
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
