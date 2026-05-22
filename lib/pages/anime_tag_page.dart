import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bangumi_tag.dart';
import '../pages/subject_page.dart';
import '../providers/app_state_provider.dart';
import '../services/api_client.dart';

enum _AnimeTagSort {
  collects('collects', '标注数'),
  rank('rank', '排名'),
  date('date', '日期'),
  title('title', '名称');

  final String value;
  final String label;
  const _AnimeTagSort(this.value, this.label);
}

class AnimeTagPage extends StatefulWidget {
  final String? initialTag;

  const AnimeTagPage({super.key, this.initialTag});

  @override
  State<AnimeTagPage> createState() => _AnimeTagPageState();
}

class _AnimeTagPageState extends State<AnimeTagPage> {
  final ScrollController _scrollController = ScrollController();
  List<BangumiTag> _tags = const [];
  List<BangumiTagSubject> _subjects = const [];
  String? _selectedTag;
  _AnimeTagSort _sort = _AnimeTagSort.collects;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _selectedTag = widget.initialTag?.trim().isEmpty == true
        ? null
        : widget.initialTag?.trim();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_selectedTag == null) {
        _loadTags();
      } else {
        _loadSubjects(refresh: true);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_selectedTag == null || _loading || _loadingMore) return;
    if (_page >= _totalPages) return;
    final position = _scrollController.position;
    if (position.pixels > position.maxScrollExtent - 360) {
      _loadSubjects(refresh: false);
    }
  }

  Future<void> _loadTags() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _selectedTag = null;
      _subjects = const [];
      _page = 1;
      _totalPages = 1;
    });

    try {
      final result = await context.read<ApiClient>().getAnimeTags();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _tags = result.tags;
        _page = result.page;
        _totalPages = result.totalPages;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = '标签加载失败，请稍后重试';
        _loading = false;
      });
    }
  }

  Future<void> _loadSubjects({required bool refresh}) async {
    final tag = _selectedTag;
    if (tag == null || tag.isEmpty) return;
    final generation = refresh ? ++_loadGeneration : _loadGeneration;
    final nextPage = refresh ? 1 : _page + 1;

    setState(() {
      if (refresh) {
        _loading = true;
        _subjects = const [];
        _page = 1;
        _totalPages = 1;
      } else {
        _loadingMore = true;
      }
      _error = null;
    });

    try {
      final result = await context.read<ApiClient>().getAnimeTagSubjects(
        tag: tag,
        sort: _sort.value,
        page: nextPage,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _subjects = refresh
            ? result.subjects
            : [..._subjects, ...result.subjects];
        _page = result.page;
        _totalPages = result.totalPages;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = '条目加载失败，请稍后重试';
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _openTag(String tag) {
    setState(() {
      _selectedTag = tag;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _loadSubjects(refresh: true);
  }

  void _showAllTags() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _loadTags();
  }

  void _changeSort(_AnimeTagSort sort) {
    if (_sort == sort) return;
    setState(() => _sort = sort);
    _loadSubjects(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final selectedTag = _selectedTag;
    return Scaffold(
      appBar: AppBar(
        title: Text(selectedTag == null ? '动画标签' : '动画标签：$selectedTag'),
        centerTitle: false,
        actions: [
          if (selectedTag != null)
            IconButton(
              icon: const Icon(Icons.sell_outlined),
              tooltip: '全部标签',
              onPressed: _showAllTags,
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          final padding = isWide
              ? EdgeInsets.symmetric(
                  horizontal: ((constraints.maxWidth - 1180) / 2).clamp(
                    24.0,
                    constraints.maxWidth,
                  ),
                  vertical: 16,
                )
              : const EdgeInsets.fromLTRB(16, 12, 16, 16);
          return RefreshIndicator(
            onRefresh: selectedTag == null
                ? _loadTags
                : () => _loadSubjects(refresh: true),
            child: selectedTag == null
                ? _buildTagsContent(padding, isWide)
                : _buildSubjectsContent(padding, isWide),
          );
        },
      ),
    );
  }

  Widget _buildTagsContent(EdgeInsets padding, bool isWide) {
    if (_loading) return _buildLoadingList(padding);
    if (_error != null) return _buildError(padding);
    if (_tags.isEmpty) return _buildEmpty(padding, '暂无标签');

    return ListView(
      controller: _scrollController,
      padding: padding,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _tags.map((tag) {
            return ActionChip(
              label: Text('${tag.name} ${_formatCount(tag.count)}'),
              onPressed: () => _openTag(tag.name),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSubjectsContent(EdgeInsets padding, bool isWide) {
    if (_loading) return _buildLoadingList(padding);
    if (_error != null) return _buildError(padding);
    if (_subjects.isEmpty) return _buildEmpty(padding, '暂无条目');

    final itemCount = _subjects.length + (_loadingMore ? 1 : 0);
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            padding.left,
            padding.top,
            padding.right,
            8,
          ),
          sliver: SliverToBoxAdapter(child: _buildSortBar()),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            padding.left,
            0,
            padding.right,
            padding.bottom,
          ),
          sliver: isWide
              ? SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: 112,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 4,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildSubjectItem(index),
                    childCount: itemCount,
                  ),
                )
              : SliverList.builder(
                  itemCount: itemCount,
                  itemBuilder: (context, index) => _buildSubjectItem(index),
                ),
        ),
      ],
    );
  }

  Widget _buildSortBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _AnimeTagSort.values.map((sort) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: _sort == sort,
              label: Text(sort.label),
              onSelected: (_) => _changeSort(sort),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSubjectItem(int index) {
    if (index >= _subjects.length) {
      return const Center(child: CircularProgressIndicator());
    }
    return _AnimeTagSubjectCard(item: _subjects[index]);
  }

  Widget _buildLoadingList(EdgeInsets padding) {
    return ListView.builder(
      padding: padding,
      itemCount: 8,
      itemBuilder: (context, index) {
        return Container(
          height: 88,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
          ),
        );
      },
    );
  }

  Widget _buildError(EdgeInsets padding) {
    return ListView(
      padding: padding,
      children: [
        const SizedBox(height: 96),
        Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
        const SizedBox(height: 12),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildEmpty(EdgeInsets padding, String text) {
    return ListView(
      padding: padding,
      children: [
        const SizedBox(height: 96),
        Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[400]),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600]),
        ),
      ],
    );
  }

  String _formatCount(int count) {
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
    return '$count';
  }
}

class _AnimeTagSubjectCard extends StatelessWidget {
  final BangumiTagSubject item;

  const _AnimeTagSubjectCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final subject = item.subject;
    final colorScheme = Theme.of(context).colorScheme;
    final appState = context.watch<AppStateProvider>();
    final densityScale = switch (appState.listDensityMode) {
      0 => 0.88,
      2 => 1.12,
      _ => 1.0,
    };
    final cardPadding = 10.0 * densityScale;
    final coverWidth = 56.0 * densityScale;
    final coverHeight = 80.0 * densityScale;
    final coverRadius = appState.coverCornerRadius;
    final showSecondary = _hasSecondaryInfo;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SubjectPage(subjectId: subject.id),
            ),
          );
        },
        child: Padding(
          padding: EdgeInsets.all(cardPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(coverRadius),
                child: SizedBox(
                  width: coverWidth,
                  height: coverHeight,
                  child: subject.images?.common.isNotEmpty == true
                      ? CachedNetworkImage(
                          imageUrl: subject.images!.common,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: colorScheme.surfaceContainerHighest,
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.image, size: 24),
                          ),
                        )
                      : Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.image, size: 24),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: coverHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject.displayName,
                        style: TextStyle(
                          fontSize: 14 * densityScale,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4 * densityScale),
                      if (subject.name.isNotEmpty &&
                          subject.name != subject.nameCn)
                        Text(
                          subject.name,
                          style: TextStyle(
                            fontSize: 11 * densityScale,
                            color: Colors.grey[500],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (subject.shortSummary.isNotEmpty) ...[
                        SizedBox(height: 4 * densityScale),
                        Text(
                          subject.shortSummary,
                          style: TextStyle(
                            fontSize: 11 * densityScale,
                            color: Colors.grey[500],
                            height: 1.2,
                          ),
                          maxLines:
                              subject.name.isNotEmpty &&
                                  subject.name != subject.nameCn
                              ? 1
                              : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (showSecondary) ...[
                        const Spacer(),
                        _buildBottomRow(context, colorScheme, densityScale),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomRow(
    BuildContext context,
    ColorScheme colorScheme,
    double densityScale,
  ) {
    final subject = item.subject;
    return Row(
      children: [
        if (subject.score > 0) ...[
          Icon(Icons.star_rounded, size: 14, color: Colors.amber[700]),
          const SizedBox(width: 2),
          Text(
            subject.score.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 12 * densityScale,
              fontWeight: FontWeight.w600,
              color: Colors.amber[800],
            ),
          ),
          const SizedBox(width: 10),
        ],
        if (subject.rank > 0) ...[
          Text(
            '#${subject.rank}',
            style: TextStyle(
              fontSize: 11 * densityScale,
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
        ],
        const Spacer(),
        if (subject.collectionTotal > 0) ...[
          Icon(Icons.people_outline, size: 13, color: Colors.grey[500]),
          const SizedBox(width: 2),
          Text(
            '${subject.collectionTotal}',
            style: TextStyle(
              fontSize: 11 * densityScale,
              color: Colors.grey[500],
            ),
          ),
        ],
      ],
    );
  }

  bool get _hasSecondaryInfo {
    final subject = item.subject;
    return subject.score > 0 || subject.rank > 0 || subject.collectionTotal > 0;
  }
}
