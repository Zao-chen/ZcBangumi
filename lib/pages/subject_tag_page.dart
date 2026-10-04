import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models/subject_browse.dart';
import '../models/subject_search.dart';
import '../models/subject_tag_query.dart';
import '../models/unified_search.dart';
import '../providers/subject_tag_provider.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../widgets/search_filter_drawer.dart';
import '../widgets/search_result_cards.dart';

class SubjectTagPage extends StatefulWidget {
  final String? initialTag;
  final int? initialSubjectType;

  const SubjectTagPage({
    super.key,
    this.initialTag,
    this.initialSubjectType = BgmConst.subjectAnime,
  });

  @override
  State<SubjectTagPage> createState() => _SubjectTagPageState();
}

class _SubjectTagPageState extends State<SubjectTagPage> {
  final _scrollController = ScrollController();
  final _tagsController = TextEditingController();
  final _keywordController = TextEditingController();
  late final SubjectTagProvider _provider;

  @override
  void initState() {
    super.initState();
    final tag = widget.initialTag?.trim() ?? '';
    final query = SubjectTagQuery(
      subjectType: widget.initialSubjectType,
      options: UnifiedSearchOptions(tags: tag.isEmpty ? const [] : [tag]),
    );
    _provider = SubjectTagProvider(
      api: context.read<ApiClient>(),
      storage: context.read<StorageService>(),
      initialQuery: query,
    );
    _syncInputs(query);
    _scrollController.addListener(_onScroll);
    if (tag.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _provider.search(query);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tagsController.dispose();
    _keywordController.dispose();
    _provider.dispose();
    super.dispose();
  }

  SubjectTagQuery get _draftQuery {
    final query = _provider.query;
    final tags = _tagsController.text == query.options.tags.join('，')
        ? query.options.tags
        : parseSubjectTags(_tagsController.text);
    return query
        .copyWith(keyword: _keywordController.text.trim())
        .withTags(tags);
  }

  void _syncInputs(SubjectTagQuery query) {
    _tagsController.text = query.options.tags.join('，');
    _keywordController.text = query.keyword;
  }

  void _jumpToTop() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _search(SubjectTagQuery query) {
    if (query.keyword.trim().isEmpty && query.filter.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入标签、关键词或至少一项筛选条件')));
      return;
    }
    FocusScope.of(context).unfocus();
    _syncInputs(query);
    _provider.search(query);
    _jumpToTop();
  }

  void _removeTag(String tag) {
    _applyQuery(
      _provider.query.withTags(
        _provider.query.options.tags.where((entry) => entry != tag),
      ),
    );
  }

  void _applyQuery(SubjectTagQuery query) {
    if (query.keyword.trim().isEmpty && query.filter.isEmpty) {
      _showHome(query: query);
    } else {
      _search(query);
    }
  }

  void _showHome({SubjectTagQuery? query}) {
    final homeQuery =
        query ?? SubjectTagQuery(subjectType: _provider.query.subjectType);
    _syncInputs(homeQuery);
    _provider.showHome(query: homeQuery);
    _jumpToTop();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _provider.loadMoreError != null) {
      return;
    }
    if (_scrollController.position.extentAfter < 360) _provider.loadMore();
  }

  void _changeType(int type) {
    final query = _draftQuery.copyWith(
      subjectType: type == 0 ? null : type,
      clearSubjectType: type == 0,
    );
    if (_provider.hasSearched) {
      _applyQuery(query);
    } else {
      _provider.showHome(query: query);
    }
  }

  void _changeSort(SubjectSearchSort sort) {
    final query = _draftQuery.copyWith(sort: sort);
    if (_provider.hasSearched) {
      _applyQuery(query);
    } else {
      _provider.showHome(query: query);
    }
  }

  Future<void> _showFilters() async {
    final draft = _draftQuery;
    final result = await showGeneralDialog<SearchFilterSelection>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black45,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final width = MediaQuery.sizeOf(dialogContext).width;
        return Align(
          alignment: Alignment.centerRight,
          child: SafeArea(
            minimum: const EdgeInsets.all(12),
            child: Material(
              color: Theme.of(dialogContext).colorScheme.surface,
              elevation: 12,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: width < 404 ? width - 24 : 380,
                child: SearchFilterDrawer(
                  scope: SearchScope.subjects,
                  initialSort: draft.sort,
                  initialOptions: draft.options,
                ),
              ),
            ),
          ),
        );
      },
    );
    if (result == null || !mounted) return;
    _applyQuery(draft.copyWith(sort: result.sort, options: result.options));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _provider,
    builder: (context, child) => Scaffold(
      appBar: AppBar(
        title: Text('${_provider.query.typeLabel}标签'),
        centerTitle: false,
        actions: [
          if (_provider.hasSearched) ...[
            IconButton(
              key: const Key('tag_save_search'),
              tooltip: _provider.isFavorite ? '取消收藏此筛选' : '收藏此筛选',
              icon: Icon(_provider.isFavorite ? Icons.star : Icons.star_border),
              onPressed: _provider.toggleFavorite,
            ),
            IconButton(
              key: const Key('tag_home_button'),
              tooltip: '标签首页',
              icon: const Icon(Icons.sell_outlined),
              onPressed: _showHome,
            ),
          ],
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final horizontalPadding = wide
              ? ((constraints.maxWidth - 1180) / 2).clamp(24.0, double.infinity)
              : 16.0;
          return RefreshIndicator(
            onRefresh: _provider.hasSearched
                ? _provider.refresh
                : () async => setState(() {}),
            child: CustomScrollView(
              key: const Key('tag_results_scroll'),
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    12,
                    horizontalPadding,
                    16,
                  ),
                  sliver: SliverToBoxAdapter(child: _buildControls()),
                ),
                if (!_provider.hasSearched)
                  SliverPadding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    sliver: SliverToBoxAdapter(child: _buildHome()),
                  )
                else ...[
                  SliverPadding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    sliver: SliverToBoxAdapter(child: _buildResultHeader()),
                  ),
                  if (_provider.loading)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(48),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  else if (_provider.error != null)
                    SliverToBoxAdapter(
                      child: _buildMessage(
                        _provider.error!,
                        retry: _provider.refresh,
                      ),
                    )
                  else if (_provider.subjects.isEmpty)
                    SliverToBoxAdapter(
                      child: _buildMessage('没有符合条件的条目，可减少标签或放宽筛选条件'),
                    )
                  else ...[
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      sliver: wide
                          ? SliverList.builder(
                              itemCount: (_provider.subjects.length + 1) ~/ 2,
                              itemBuilder: _buildSubjectRow,
                            )
                          : SliverList.builder(
                              itemCount: _provider.subjects.length,
                              itemBuilder: _buildSubject,
                            ),
                    ),
                    SliverToBoxAdapter(child: _buildPagination()),
                  ],
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          );
        },
      ),
    ),
  );

  Widget _buildControls() {
    final activeFilters = _provider.query.options.activeLabelsFor(
      SearchScope.subjects,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('tag_input'),
                controller: _tagsController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(_draftQuery),
                decoration: InputDecoration(
                  labelText: '用户标签',
                  hintText: '例如：治愈，校园',
                  helperText: '多个标签用逗号分隔，按「且」匹配',
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    key: const Key('tag_search_submit'),
                    tooltip: '搜索',
                    onPressed: () => _search(_draftQuery),
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: const Key('tag_filter_button'),
              tooltip: '筛选与排序',
              onPressed: _showFilters,
              icon: Badge(
                isLabelVisible: activeFilters.isNotEmpty,
                label: Text('${activeFilters.length}'),
                child: const Icon(Icons.tune),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('tag_keyword_input'),
          controller: _keywordController,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(_draftQuery),
          decoration: const InputDecoration(
            labelText: '关键词（可选，可与标签组合）',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButton<int>(
          key: const Key('tag_subject_type'),
          value: _provider.query.subjectType ?? 0,
          items: [
            const DropdownMenuItem(value: 0, child: Text('全部类型')),
            for (final type in subjectBrowseTypes)
              DropdownMenuItem(
                value: type,
                child: Text(subjectTypeLabel(type)),
              ),
          ],
          onChanged: (type) {
            if (type != null) _changeType(type);
          },
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final sort in SubjectSearchSort.values)
              ChoiceChip(
                key: Key('tag_sort_${sort.name}'),
                selected: _provider.query.sort == sort,
                label: Text(subjectTagSortLabel(sort)),
                onSelected: (_) => _changeSort(sort),
              ),
          ],
        ),
        if (_provider.storageError != null) ...[
          const SizedBox(height: 8),
          Text(
            _provider.storageError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  Widget _buildHome() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '使用公开 API 搜索条目。常用标签由应用预置，不是 Bangumi 全站标签目录或热门榜。',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 16),
      _sectionTitle('常用标签'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tag in commonSubjectTags(_provider.query.subjectType))
            ActionChip(
              label: Text(tag),
              onPressed: () => _search(_draftQuery.withTags([tag])),
            ),
        ],
      ),
      if (_provider.favorites.isNotEmpty) ...[
        const SizedBox(height: 20),
        _sectionTitle('收藏的筛选'),
        for (final query in _provider.favorites)
          _buildSavedQuery(query, favorite: true),
      ],
      if (_provider.recentSearches.isNotEmpty) ...[
        const SizedBox(height: 20),
        Row(
          children: [
            _sectionTitle('最近搜索'),
            const Spacer(),
            TextButton(
              key: const Key('tag_clear_history'),
              onPressed: _provider.clearRecentSearches,
              child: const Text('清空'),
            ),
          ],
        ),
        for (final query in _provider.recentSearches) _buildSavedQuery(query),
      ],
    ],
  );

  Widget _sectionTitle(String title) =>
      Text(title, style: Theme.of(context).textTheme.titleSmall);

  Widget _buildSavedQuery(SubjectTagQuery query, {bool favorite = false}) {
    final saved = _provider.favorites.any(
      (entry) => entry.identity == query.identity,
    );
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(favorite ? Icons.star_outline : Icons.history),
      title: Text(query.label, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        query.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: saved ? '取消收藏此筛选' : '收藏此筛选',
        icon: Icon(saved ? Icons.star : Icons.star_border),
        onPressed: () => _provider.toggleFavorite(query),
      ),
      onTap: () => _search(query),
    );
  }

  Widget _buildResultHeader() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_provider.query.options.tags.isNotEmpty) ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in _provider.query.options.tags)
              InputChip(
                label: Text(tag),
                selected: true,
                showCheckmark: false,
                onSelected: (_) => _removeTag(tag),
                onDeleted: () => _removeTag(tag),
                deleteButtonTooltipMessage: '移除标签：$tag',
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
      Text(
        _provider.query.description,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if (_provider.query.options.metaTags.isNotEmpty)
        Text('公共标签：${_provider.query.options.metaTags.join(' + ')}'),
      if (_provider.query.keyword.isNotEmpty)
        Text('关键词：${_provider.query.keyword}'),
      const SizedBox(height: 8),
      if (!_provider.loading && _provider.error == null)
        Text(
          'API 返回 ${_provider.total} 条匹配结果 · 已加载 ${_provider.subjects.length} 条',
        ),
      if (_provider.relatedTags.isNotEmpty) ...[
        const SizedBox(height: 16),
        _sectionTitle('相关标签（当前已加载条目）'),
        const SizedBox(height: 4),
        Text(
          '数字为当前结果中出现该标签的条目数，点击追加筛选，不代表全站热度。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in _provider.relatedTags)
              ActionChip(
                key: Key('tag_related_${tag.name}'),
                label: Text('${tag.name} · ${tag.subjectCount}'),
                onPressed: () => _search(
                  _provider.query.withTags([
                    ..._provider.query.options.tags,
                    tag.name,
                  ]),
                ),
              ),
          ],
        ),
      ],
      const SizedBox(height: 8),
    ],
  );

  Widget _buildSubject(BuildContext context, int index) =>
      SubjectSearchResultCard(
        subject: _provider.subjects[index],
        showSearchDetails: true,
      );

  Widget _buildSubjectRow(BuildContext context, int rowIndex) {
    final index = rowIndex * 2;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildSubject(context, index)),
          const SizedBox(width: 12),
          Expanded(
            child: index + 1 < _provider.subjects.length
                ? _buildSubject(context, index + 1)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildPagination() {
    if (_provider.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_provider.loadMoreError != null) {
      return _buildMessage(_provider.loadMoreError!, retry: _provider.loadMore);
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: _provider.hasMore
            ? OutlinedButton(
                key: const Key('tag_load_more'),
                onPressed: _provider.loadMore,
                child: const Text('加载更多'),
              )
            : const Text('已加载全部可用结果'),
      ),
    );
  }

  Widget _buildMessage(String message, {Future<void> Function()? retry}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            Text(message, textAlign: TextAlign.center),
            if (retry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: retry, child: const Text('重试')),
            ],
          ],
        ),
      );
}
