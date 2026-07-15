import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/subject.dart';
import '../models/subject_search.dart';
import '../pages/subject_page.dart';
import '../providers/app_state_provider.dart';
import '../providers/auth_provider.dart';

enum _NsfwMode { any, safeOnly, adultOnly }

class _SearchAdvancedOptions {
  final List<String> metaTags;
  final List<String> tags;
  final DateTime? airDateFrom;
  final DateTime? airDateTo;
  final double? ratingMin;
  final double? ratingMax;
  final int? ratingCountMin;
  final int? ratingCountMax;
  final int? rankMin;
  final int? rankMax;
  final _NsfwMode nsfwMode;

  const _SearchAdvancedOptions({
    this.metaTags = const [],
    this.tags = const [],
    this.airDateFrom,
    this.airDateTo,
    this.ratingMin,
    this.ratingMax,
    this.ratingCountMin,
    this.ratingCountMax,
    this.rankMin,
    this.rankMax,
    this.nsfwMode = _NsfwMode.any,
  });

  bool get isEmpty => activeLabels.isEmpty;

  List<String> get activeLabels => [
    if (metaTags.isNotEmpty) '公共标签',
    if (tags.isNotEmpty) '用户标签',
    if (airDateFrom != null || airDateTo != null) '日期',
    if (ratingMin != null || ratingMax != null) '评分',
    if (ratingCountMin != null || ratingCountMax != null) '评分人数',
    if (rankMin != null || rankMax != null) '排名',
    if (nsfwMode != _NsfwMode.any) 'NSFW',
  ];

  SubjectSearchFilter toApiFilter({required int? subjectType}) {
    return SubjectSearchFilter(
      types: subjectType == null ? const [] : [subjectType],
      metaTags: metaTags,
      tags: tags,
      airDates: [
        if (airDateFrom != null) '>=${_formatApiDate(airDateFrom!)}',
        if (airDateTo != null) '<=${_formatApiDate(airDateTo!)}',
      ],
      ratings: [
        if (ratingMin != null) '>=${_formatNumber(ratingMin!)}',
        if (ratingMax != null) '<=${_formatNumber(ratingMax!)}',
      ],
      ratingCounts: [
        if (ratingCountMin != null) '>=$ratingCountMin',
        if (ratingCountMax != null) '<=$ratingCountMax',
      ],
      ranks: [
        if (rankMin != null) '>=$rankMin',
        if (rankMax != null) '<=$rankMax',
      ],
      nsfw: switch (nsfwMode) {
        _NsfwMode.any => null,
        _NsfwMode.safeOnly => false,
        _NsfwMode.adultOnly => true,
      },
    );
  }
}

class _SearchFilterSelection {
  final SubjectSearchSort sort;
  final _SearchAdvancedOptions options;

  const _SearchFilterSelection({required this.sort, required this.options});
}

String _formatApiDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _formatNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

String _subjectSearchSortLabel(SubjectSearchSort sort) => switch (sort) {
  SubjectSearchSort.match => '匹配程度',
  SubjectSearchSort.heat => '收藏热度',
  SubjectSearchSort.rank => '排名',
  SubjectSearchSort.score => '评分',
};

/// 条目搜索页面
class SearchPage extends StatefulWidget {
  final int? initialSubjectType;
  const SearchPage({super.key, this.initialSubjectType});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late TextEditingController _searchController;
  final ScrollController _resultsController = ScrollController();
  List<SlimSubject> _searchResults = [];
  bool _isSearching = false;
  bool _isLoadingMore = false;
  String? _searchError;
  String? _loadMoreError;
  late int _selectedSubjectType;
  String _submittedQuery = '';
  int _searchGeneration = 0;
  int _resultTotal = 0;
  int _nextOffset = 0;
  SubjectSearchSort _searchSort = SubjectSearchSort.match;
  _SearchAdvancedOptions _advancedOptions = const _SearchAdvancedOptions();

  // 0 表示全部类型
  static const int _allTypes = 0;
  static const int _pageSize = 30;

  static const _subjectTypes = [
    (type: _allTypes, label: '全部', icon: Icons.apps_outlined),
    (type: BgmConst.subjectAnime, label: '动画', icon: Icons.movie_outlined),
    (
      type: BgmConst.subjectGame,
      label: '游戏',
      icon: Icons.sports_esports_outlined,
    ),
    (type: BgmConst.subjectBook, label: '书籍', icon: Icons.menu_book_outlined),
    (type: BgmConst.subjectMusic, label: '音乐', icon: Icons.music_note_outlined),
    (type: BgmConst.subjectReal, label: '三次元', icon: Icons.tv_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _selectedSubjectType = widget.initialSubjectType ?? _allTypes;
    _resultsController.addListener(_handleResultsScroll);
  }

  @override
  void dispose() {
    _resultsController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  SubjectSearchFilter get _searchFilter => _advancedOptions.toApiFilter(
    subjectType: _selectedSubjectType == _allTypes
        ? null
        : _selectedSubjectType,
  );

  bool get _hasMoreResults => _nextOffset < _resultTotal;

  void _handleResultsScroll() {
    if (!_resultsController.hasClients ||
        _resultsController.position.extentAfter >= 480) {
      return;
    }
    _loadMore();
  }

  Future<void> _search(String keyword) async {
    final query = keyword.trim();
    final generation = ++_searchGeneration;

    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _searchError = null;
        _loadMoreError = null;
        _submittedQuery = '';
        _isSearching = false;
        _isLoadingMore = false;
        _resultTotal = 0;
        _nextOffset = 0;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _isLoadingMore = false;
      _searchError = null;
      _loadMoreError = null;
      _submittedQuery = query;
      _searchResults = [];
      _resultTotal = 0;
      _nextOffset = 0;
    });

    try {
      final auth = context.read<AuthProvider>();
      final page = await auth.api.searchSubjects(
        keyword: query,
        sort: _searchSort,
        filter: _searchFilter,
        limit: _pageSize,
      );

      if (!mounted || generation != _searchGeneration) return;

      setState(() {
        _searchResults = page.data;
        _resultTotal = page.total;
        _nextOffset = page.data.isEmpty
            ? page.total
            : page.offset + page.data.length;
        _isSearching = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            generation != _searchGeneration ||
            !_resultsController.hasClients) {
          return;
        }
        _resultsController.jumpTo(0);
      });
    } catch (e) {
      if (!mounted || generation != _searchGeneration) return;

      setState(() {
        _isSearching = false;
        _searchError = '网络错误，请稍后重试';
        _searchResults = [];
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isSearching ||
        _isLoadingMore ||
        !_hasMoreResults ||
        _submittedQuery.isEmpty) {
      return;
    }

    final generation = _searchGeneration;
    final query = _submittedQuery;
    final offset = _nextOffset;
    setState(() {
      _isLoadingMore = true;
      _loadMoreError = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      final page = await auth.api.searchSubjects(
        keyword: query,
        sort: _searchSort,
        filter: _searchFilter,
        limit: _pageSize,
        offset: offset,
      );
      if (!mounted || generation != _searchGeneration) return;

      final knownIds = _searchResults.map((item) => item.id).toSet();
      final newItems = page.data
          .where((item) => knownIds.add(item.id))
          .toList(growable: false);
      setState(() {
        _searchResults = [..._searchResults, ...newItems];
        _resultTotal = page.total;
        _nextOffset = page.data.isEmpty
            ? page.total
            : page.offset + page.data.length;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _isLoadingMore = false;
        _loadMoreError = '加载更多失败，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索条目'), centerTitle: false),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTypeRail(),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                        child: _buildSearchField(),
                      ),
                      Expanded(child: _buildResultContent(24, true)),
                    ],
                  ),
                ),
              ],
            );
          }

          return Column(
            children: [
              // 搜索框
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: _buildSearchField(),
              ),

              // 类型筛选
              _buildTypeChips(),

              const SizedBox(height: 16),

              // 搜索结果
              Expanded(child: _buildResultContent(12, false)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchField() {
    final activeFilterCount = _advancedOptions.activeLabels.length;
    final hasCustomSearch =
        activeFilterCount > 0 || _searchSort != SubjectSearchSort.match;
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('search_query_field'),
            controller: _searchController,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜索条目...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: _clearSearch,
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            onChanged: (value) {
              setState(() {});
            },
            onSubmitted: _search,
          ),
        ),
        const SizedBox(width: 10),
        Badge(
          isLabelVisible: activeFilterCount > 0,
          label: Text('$activeFilterCount'),
          child: IconButton(
            key: const Key('search_advanced_filter_button'),
            onPressed: _showFilterDrawer,
            tooltip: hasCustomSearch ? '筛选与排序（已自定义）' : '筛选与排序',
            icon: const Icon(Icons.tune_rounded),
            style: IconButton.styleFrom(
              fixedSize: const Size(48, 48),
              backgroundColor: hasCustomSearch
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              foregroundColor: hasCustomSearch
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showFilterDrawer() async {
    final result = await showGeneralDialog<_SearchFilterSelection>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final screenWidth = MediaQuery.sizeOf(dialogContext).width;
        return Align(
          alignment: Alignment.centerRight,
          child: SafeArea(
            minimum: const EdgeInsets.all(12),
            child: Material(
              color: Theme.of(dialogContext).colorScheme.surface,
              elevation: 12,
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: screenWidth < 404 ? screenWidth - 24 : 380,
                child: _SearchFilterDrawer(
                  initialSort: _searchSort,
                  initialOptions: _advancedOptions,
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
    if (result == null || !mounted) return;

    setState(() {
      _searchSort = result.sort;
      _advancedOptions = result.options;
    });
    if (_submittedQuery.isNotEmpty) {
      _search(_submittedQuery);
    }
  }

  Widget _buildTypeChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _subjectTypes.map((config) {
            final isSelected = _selectedSubjectType == config.type;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilterChip(
                selected: isSelected,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(config.icon, size: 16),
                    const SizedBox(width: 4),
                    Text(config.label),
                  ],
                ),
                onSelected: (_) => _selectSubjectType(config.type),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTypeRail() {
    return NavigationRail(
      minWidth: 112,
      labelType: NavigationRailLabelType.all,
      selectedIndex: _selectedSubjectIndex,
      onDestinationSelected: (index) {
        _selectSubjectType(_subjectTypes[index].type);
      },
      destinations: _subjectTypes
          .map(
            (config) => NavigationRailDestination(
              icon: Icon(config.icon),
              selectedIcon: Icon(config.icon),
              label: Text(config.label),
            ),
          )
          .toList(),
    );
  }

  int get _selectedSubjectIndex {
    final index = _subjectTypes.indexWhere(
      (config) => config.type == _selectedSubjectType,
    );
    return index >= 0 ? index : 0;
  }

  void _selectSubjectType(int type) {
    if (_selectedSubjectType == type) return;
    setState(() {
      _selectedSubjectType = type;
    });
    if (_submittedQuery.isNotEmpty) {
      _search(_submittedQuery);
    }
  }

  void _clearSearch() {
    _searchGeneration++;
    _searchController.clear();
    setState(() {
      _searchResults = [];
      _searchError = null;
      _loadMoreError = null;
      _submittedQuery = '';
      _isSearching = false;
      _isLoadingMore = false;
      _resultTotal = 0;
      _nextOffset = 0;
    });
  }

  Widget _buildResultContent(double horizontalPadding, bool isWide) {
    if (_isSearching) {
      return _buildSearchSkeletonList(horizontalPadding, isWide);
    }

    if (_searchError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              _searchError!,
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => _search(_submittedQuery),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty && _submittedQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('没有找到相关条目', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('输入条目名称进行搜索', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    final listPadding = EdgeInsets.symmetric(
      horizontal: horizontalPadding,
      vertical: isWide ? 4 : 0,
    );

    return CustomScrollView(
      controller: _resultsController,
      slivers: [
        SliverPadding(
          padding: listPadding,
          sliver: isWide
              ? SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: 112,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 4,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _SearchResultCard(subject: _searchResults[index]),
                    childCount: _searchResults.length,
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _SearchResultCard(subject: _searchResults[index]),
                    childCount: _searchResults.length,
                  ),
                ),
        ),
        if (_hasMoreResults || _isLoadingMore || _loadMoreError != null)
          SliverToBoxAdapter(child: _buildPaginationFooter()),
      ],
    );
  }

  Widget _buildPaginationFooter() {
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: TextButton.icon(
          onPressed: _loadMore,
          icon: Icon(
            _loadMoreError == null ? Icons.expand_more : Icons.refresh,
          ),
          label: Text(_loadMoreError ?? '加载更多'),
        ),
      ),
    );
  }

  Widget _buildSearchSkeletonList(double horizontalPadding, bool isWide) {
    final colorScheme = Theme.of(context).colorScheme;
    final listPadding = EdgeInsets.symmetric(
      horizontal: horizontalPadding,
      vertical: isWide ? 4 : 0,
    );

    Widget skeletonCard(int index) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                height: 84,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 160,
                      height: 14,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 190,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
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

    if (isWide) {
      return GridView.builder(
        padding: listPadding,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisExtent: 112,
          crossAxisSpacing: 12,
          mainAxisSpacing: 4,
        ),
        itemCount: 8,
        itemBuilder: (context, index) => skeletonCard(index),
      );
    }

    return ListView.builder(
      padding: listPadding,
      itemCount: 6,
      itemBuilder: (context, index) => skeletonCard(index),
    );
  }
}

class _SearchFilterDrawer extends StatefulWidget {
  final SubjectSearchSort initialSort;
  final _SearchAdvancedOptions initialOptions;

  const _SearchFilterDrawer({
    required this.initialSort,
    required this.initialOptions,
  });

  @override
  State<_SearchFilterDrawer> createState() => _SearchFilterDrawerState();
}

class _SearchFilterDrawerState extends State<_SearchFilterDrawer> {
  late final TextEditingController _metaTagsController;
  late final TextEditingController _tagsController;
  late final TextEditingController _ratingMinController;
  late final TextEditingController _ratingMaxController;
  late final TextEditingController _ratingCountMinController;
  late final TextEditingController _ratingCountMaxController;
  late final TextEditingController _rankMinController;
  late final TextEditingController _rankMaxController;
  DateTime? _airDateFrom;
  DateTime? _airDateTo;
  late SubjectSearchSort _sort;
  late _NsfwMode _nsfwMode;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    final options = widget.initialOptions;
    _metaTagsController = TextEditingController(
      text: options.metaTags.join(', '),
    );
    _tagsController = TextEditingController(text: options.tags.join(', '));
    _ratingMinController = TextEditingController(
      text: options.ratingMin == null ? '' : _formatNumber(options.ratingMin!),
    );
    _ratingMaxController = TextEditingController(
      text: options.ratingMax == null ? '' : _formatNumber(options.ratingMax!),
    );
    _ratingCountMinController = TextEditingController(
      text: options.ratingCountMin?.toString() ?? '',
    );
    _ratingCountMaxController = TextEditingController(
      text: options.ratingCountMax?.toString() ?? '',
    );
    _rankMinController = TextEditingController(
      text: options.rankMin?.toString() ?? '',
    );
    _rankMaxController = TextEditingController(
      text: options.rankMax?.toString() ?? '',
    );
    _airDateFrom = options.airDateFrom;
    _airDateTo = options.airDateTo;
    _sort = widget.initialSort;
    _nsfwMode = options.nsfwMode;
  }

  @override
  void dispose() {
    _metaTagsController.dispose();
    _tagsController.dispose();
    _ratingMinController.dispose();
    _ratingMaxController.dispose();
    _ratingCountMinController.dispose();
    _ratingCountMaxController.dispose();
    _rankMinController.dispose();
    _rankMaxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return AnimatedPadding(
      key: const Key('search_filter_drawer'),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Row(
              children: [
                Text('筛选与排序', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                TextButton(onPressed: _reset, child: const Text('重置')),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: '关闭',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<SubjectSearchSort>(
                    initialValue: _sort,
                    decoration: const InputDecoration(
                      labelText: '排序',
                      border: OutlineInputBorder(),
                    ),
                    items: SubjectSearchSort.values
                        .map(
                          (sort) => DropdownMenuItem(
                            value: sort,
                            child: Text(_subjectSearchSortLabel(sort)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _sort = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_validationError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_validationError!),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    key: const Key('search_meta_tags_field'),
                    controller: _metaTagsController,
                    decoration: const InputDecoration(
                      labelText: '公共标签（维基标签）',
                      hintText: '例如：原创, 童年；使用 -科幻 排除标签',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('search_tags_field'),
                    controller: _tagsController,
                    decoration: const InputDecoration(
                      labelText: '用户标签',
                      hintText: '多个标签用逗号分隔，标签之间为且关系',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '播出／发售日期',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _buildDateButton(
                        label: '起始日期',
                        value: _airDateFrom,
                        onPressed: () => _pickDate(isStart: true),
                        onClear: _airDateFrom == null
                            ? null
                            : () => setState(() => _airDateFrom = null),
                      ),
                      _buildDateButton(
                        label: '结束日期',
                        value: _airDateTo,
                        onPressed: () => _pickDate(isStart: false),
                        onClear: _airDateTo == null
                            ? null
                            : () => setState(() => _airDateTo = null),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildRangeFields(
                    label: '评分范围（0–10）',
                    minController: _ratingMinController,
                    maxController: _ratingMaxController,
                    decimal: true,
                  ),
                  const SizedBox(height: 16),
                  _buildRangeFields(
                    label: '评分人数',
                    minController: _ratingCountMinController,
                    maxController: _ratingCountMaxController,
                  ),
                  const SizedBox(height: 16),
                  _buildRangeFields(
                    label: '排名范围',
                    minController: _rankMinController,
                    maxController: _rankMaxController,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<_NsfwMode>(
                    initialValue: _nsfwMode,
                    decoration: const InputDecoration(
                      labelText: 'NSFW',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: _NsfwMode.any, child: Text('不限')),
                      DropdownMenuItem(
                        value: _NsfwMode.safeOnly,
                        child: Text('仅非成人内容'),
                      ),
                      DropdownMenuItem(
                        value: _NsfwMode.adultOnly,
                        child: Text('仅成人内容'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _nsfwMode = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '不同筛选条件之间为“且”关系；同一类型中的多个条目按 Bangumi 官方规则组合。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  key: const Key('search_apply_filters_button'),
                  onPressed: _apply,
                  child: const Text('应用筛选'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateButton({
    required String label,
    required DateTime? value,
    required VoidCallback onPressed,
    required VoidCallback? onClear,
  }) {
    return InputChip(
      avatar: const Icon(Icons.calendar_today_outlined, size: 18),
      label: Text(value == null ? label : '$label：${_formatApiDate(value)}'),
      onPressed: onPressed,
      onDeleted: onClear,
    );
  }

  Widget _buildRangeFields({
    required String label,
    required TextEditingController minController,
    required TextEditingController maxController,
    bool decimal = false,
  }) {
    final keyboardType = TextInputType.numberWithOptions(decimal: decimal);
    Widget field(TextEditingController controller, String fieldLabel) {
      return TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: fieldLabel,
          border: const OutlineInputBorder(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 420) {
              return Row(
                children: [
                  Expanded(child: field(minController, '最小值')),
                  const SizedBox(width: 12),
                  Expanded(child: field(maxController, '最大值')),
                ],
              );
            }
            return Column(
              children: [
                field(minController, '最小值'),
                const SizedBox(height: 12),
                field(maxController, '最大值'),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initialDate = isStart
        ? (_airDateFrom ?? _airDateTo ?? DateTime.now())
        : (_airDateTo ?? _airDateFrom ?? DateTime.now());
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
    );
    if (date == null || !mounted) return;
    setState(() {
      if (isStart) {
        _airDateFrom = date;
      } else {
        _airDateTo = date;
      }
    });
  }

  void _reset() {
    setState(() {
      _metaTagsController.clear();
      _tagsController.clear();
      _ratingMinController.clear();
      _ratingMaxController.clear();
      _ratingCountMinController.clear();
      _ratingCountMaxController.clear();
      _rankMinController.clear();
      _rankMaxController.clear();
      _airDateFrom = null;
      _airDateTo = null;
      _sort = SubjectSearchSort.match;
      _nsfwMode = _NsfwMode.any;
      _validationError = null;
    });
  }

  void _apply() {
    try {
      final ratingMin = _parseDouble(_ratingMinController, '最低评分');
      final ratingMax = _parseDouble(_ratingMaxController, '最高评分');
      final ratingCountMin = _parseInt(_ratingCountMinController, '最少评分人数');
      final ratingCountMax = _parseInt(_ratingCountMaxController, '最多评分人数');
      final rankMin = _parseInt(_rankMinController, '最小排名');
      final rankMax = _parseInt(_rankMaxController, '最大排名');

      if (ratingMin != null && (ratingMin < 0 || ratingMin > 10) ||
          ratingMax != null && (ratingMax < 0 || ratingMax > 10)) {
        throw const FormatException('评分必须在 0 到 10 之间');
      }
      _validateRange(ratingMin, ratingMax, '评分');
      _validateRange(ratingCountMin, ratingCountMax, '评分人数');
      _validateRange(rankMin, rankMax, '排名');
      if (_airDateFrom != null &&
          _airDateTo != null &&
          _airDateFrom!.isAfter(_airDateTo!)) {
        throw const FormatException('起始日期不能晚于结束日期');
      }

      Navigator.pop(
        context,
        _SearchFilterSelection(
          sort: _sort,
          options: _SearchAdvancedOptions(
            metaTags: _parseTags(_metaTagsController.text),
            tags: _parseTags(_tagsController.text),
            airDateFrom: _airDateFrom,
            airDateTo: _airDateTo,
            ratingMin: ratingMin,
            ratingMax: ratingMax,
            ratingCountMin: ratingCountMin,
            ratingCountMax: ratingCountMax,
            rankMin: rankMin,
            rankMax: rankMax,
            nsfwMode: _nsfwMode,
          ),
        ),
      );
    } on FormatException catch (error) {
      setState(() => _validationError = error.message);
    }
  }

  double? _parseDouble(TextEditingController controller, String label) {
    final value = controller.text.trim();
    if (value.isEmpty) return null;
    final parsed = double.tryParse(value);
    if (parsed == null) throw FormatException('$label 必须是数字');
    return parsed;
  }

  int? _parseInt(TextEditingController controller, String label) {
    final value = controller.text.trim();
    if (value.isEmpty) return null;
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 0) {
      throw FormatException('$label 必须是非负整数');
    }
    return parsed;
  }

  void _validateRange(num? min, num? max, String label) {
    if (min != null && max != null && min > max) {
      throw FormatException('$label 的最小值不能大于最大值');
    }
  }

  List<String> _parseTags(String value) {
    final seen = <String>{};
    return value
        .split(RegExp(r'[,，\n]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && seen.add(item))
        .toList(growable: false);
  }
}

/// 搜索结果卡片
class _SearchResultCard extends StatelessWidget {
  final SlimSubject subject;
  const _SearchResultCard({required this.subject});

  @override
  Widget build(BuildContext context) {
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
              // 封面
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
              // 条目信息
              Expanded(
                child: SizedBox(
                  height: coverHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题
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
                      // 英文名
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

  bool get _hasSecondaryInfo =>
      subject.score > 0 || subject.rank > 0 || subject.collectionTotal > 0;
}
