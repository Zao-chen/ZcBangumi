import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models/subject.dart';
import '../models/subject_browse.dart';
import '../providers/discovery_provider.dart';
import '../widgets/subject_cover_card.dart';
import 'subject_page.dart';

class SubjectBrowsePage extends StatefulWidget {
  final int initialType;
  final SubjectBrowseSort initialSort;
  final SubjectBrowseFilter? initialFilter;

  const SubjectBrowsePage({
    super.key,
    this.initialType = BgmConst.subjectAnime,
    this.initialSort = SubjectBrowseSort.rank,
    this.initialFilter,
  });

  @override
  State<SubjectBrowsePage> createState() => _SubjectBrowsePageState();
}

class _SubjectBrowsePageState extends State<SubjectBrowsePage> {
  static const _pageSize = 30;

  final ScrollController _scrollController = ScrollController();
  late SubjectBrowseFilter _filter;
  List<SlimSubject> _subjects = const [];
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  String? _loadMoreError;
  String? _cacheWarning;
  int _generation = 0;

  bool get _hasMore => _subjects.length < _total;

  @override
  void initState() {
    super.initState();
    final requestedFilter =
        widget.initialFilter ??
        SubjectBrowseFilter(type: widget.initialType, sort: widget.initialSort);
    _filter = subjectBrowseTypes.contains(requestedFilter.type)
        ? requestedFilter
        : SubjectBrowseFilter(sort: requestedFilter.sort);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(refresh: true));
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > 520 ||
        !_hasMore ||
        _loading ||
        _loadingMore) {
      return;
    }
    _load(refresh: false);
  }

  Future<void> _load({required bool refresh, bool forceNetwork = false}) async {
    if (!refresh && (_loadingMore || !_hasMore)) {
      return;
    }

    final generation = refresh ? ++_generation : _generation;
    final offset = refresh ? 0 : _subjects.length;
    final filter = _filter;
    setState(() {
      if (refresh) {
        _loading = _subjects.isEmpty;
        _error = null;
        _loadMoreError = null;
        _cacheWarning = null;
      } else {
        _loadingMore = true;
        _loadMoreError = null;
      }
    });

    try {
      final result = await context.read<DiscoveryProvider>().browseSubjects(
        filter: filter,
        limit: _pageSize,
        offset: offset,
        forceNetwork: forceNetwork,
      );
      if (!mounted || generation != _generation) return;

      final nextItems = refresh
          ? result.page.data
          : _mergeUnique(_subjects, result.page.data);
      setState(() {
        _subjects = nextItems;
        _total = result.page.total;
        _error = null;
        _cacheWarning = result.refreshError == null ? null : '网络刷新失败，正在显示本地缓存';
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        if (refresh) {
          _error = '条目加载失败，请稍后重试';
        } else {
          _loadMoreError = '加载更多失败，点击重试';
        }
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  List<SlimSubject> _mergeUnique(
    List<SlimSubject> current,
    List<SlimSubject> incoming,
  ) {
    final ids = current.map((subject) => subject.id).toSet();
    return [...current, ...incoming.where((subject) => ids.add(subject.id))];
  }

  void _setType(int type) {
    if (_filter.type == type) return;
    setState(() {
      _filter = SubjectBrowseFilter(type: type, sort: _filter.sort);
      _subjects = const [];
      _total = 0;
    });
    _load(refresh: true);
  }

  void _setSort(SubjectBrowseSort sort) {
    if (_filter.sort == sort) return;
    setState(() {
      _filter = _filter.copyWith(sort: sort);
      _subjects = const [];
      _total = 0;
    });
    _load(refresh: true);
  }

  void _applyFilter(SubjectBrowseFilter filter) {
    setState(() {
      _filter = filter;
      _subjects = const [];
      _total = 0;
    });
    _load(refresh: true);
  }

  Future<void> _showMobileFilters() async {
    final filter = await showModalBottomSheet<SubjectBrowseFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _SubjectBrowseFilterPanel(
          initialFilter: _filter,
          onApply: (value) => Navigator.of(context).pop(value),
          onCancel: () => Navigator.of(context).pop(),
        ),
      ),
    );
    if (filter != null && mounted) {
      _applyFilter(filter);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: const Text('浏览条目'),
        centerTitle: false,
        actions: [
          if (!isWide)
            IconButton(
              key: const Key('subject_browse_filter_button'),
              tooltip: '筛选',
              onPressed: _showMobileFilters,
              icon: const Icon(Icons.tune_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildTypeSelector(),
          _buildSortSelector(),
          const Divider(height: 1),
          Expanded(
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 280,
                        child: _SubjectBrowseFilterPanel(
                          key: ValueKey('filter_${_filter.type}'),
                          initialFilter: _filter,
                          onApply: _applyFilter,
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: _buildResults()),
                    ],
                  )
                : _buildResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: subjectBrowseTypes.map((type) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: Key('subject_browse_type_$type'),
              selected: _filter.type == type,
              label: Text(subjectTypeLabel(type)),
              onSelected: (_) => _setType(type),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSortSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<SubjectBrowseSort>(
          segments: const [
            ButtonSegment(
              value: SubjectBrowseSort.rank,
              icon: Icon(Icons.leaderboard_outlined),
              label: Text('排名'),
            ),
            ButtonSegment(
              value: SubjectBrowseSort.date,
              icon: Icon(Icons.schedule_outlined),
              label: Text('最新'),
            ),
          ],
          selected: {_filter.sort},
          onSelectionChanged: (value) => _setSort(value.first),
          showSelectedIcon: false,
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_loading && _subjects.isEmpty) return _buildSkeletonGrid();
    if (_error != null && _subjects.isEmpty) {
      return _buildMessage(
        icon: Icons.error_outline_rounded,
        message: _error!,
        onRetry: () => _load(refresh: true, forceNetwork: true),
      );
    }
    if (_subjects.isEmpty) {
      return _buildMessage(
        icon: Icons.inbox_outlined,
        message: '没有符合条件的条目',
        onRetry: () => _load(refresh: true, forceNetwork: true),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(refresh: true, forceNetwork: true),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_cacheWarning != null)
            SliverToBoxAdapter(
              child: MaterialBanner(
                content: Text(_cacheWarning!),
                actions: [
                  TextButton(
                    onPressed: () => _load(refresh: true, forceNetwork: true),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 190,
                childAspectRatio: 0.58,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _subjectCard(_subjects[index]),
                childCount: _subjects.length,
              ),
            ),
          ),
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (_loadMoreError != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => _load(refresh: false),
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(_loadMoreError!),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _subjectCard(SlimSubject subject) {
    return SubjectCoverCard(
      title: subject.displayName,
      subtitle: subject.nameCn.isNotEmpty && subject.name != subject.nameCn
          ? subject.name
          : '',
      imageUrl: subject.images?.common ?? '',
      score: subject.score,
      rank: subject.rank,
      date: subject.date,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SubjectPage(subjectId: subject.id)),
      ),
    );
  }

  Widget _buildSkeletonGrid() {
    final color = Theme.of(context).colorScheme.surfaceContainerLow;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        childAspectRatio: 0.58,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: 12,
      itemBuilder: (_, _) => Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String message,
    required VoidCallback onRetry,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ),
      ],
    );
  }
}

class _SubjectBrowseFilterPanel extends StatefulWidget {
  final SubjectBrowseFilter initialFilter;
  final ValueChanged<SubjectBrowseFilter> onApply;
  final VoidCallback? onCancel;

  const _SubjectBrowseFilterPanel({
    super.key,
    required this.initialFilter,
    required this.onApply,
    this.onCancel,
  });

  @override
  State<_SubjectBrowseFilterPanel> createState() =>
      _SubjectBrowseFilterPanelState();
}

class _SubjectBrowseFilterPanelState extends State<_SubjectBrowseFilterPanel> {
  late int? _category;
  late bool _seriesOnly;
  late int? _month;
  late TextEditingController _yearController;
  late TextEditingController _platformController;

  @override
  void initState() {
    super.initState();
    _restore(widget.initialFilter, disposeExisting: false);
  }

  @override
  void didUpdateWidget(covariant _SubjectBrowseFilterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFilter.cacheKey != widget.initialFilter.cacheKey) {
      _restore(widget.initialFilter);
    }
  }

  void _restore(SubjectBrowseFilter filter, {bool disposeExisting = true}) {
    if (disposeExisting) {
      _yearController.dispose();
      _platformController.dispose();
    }
    _category = filter.category;
    _seriesOnly = filter.series == true;
    _month = filter.month;
    _yearController = TextEditingController(
      text: filter.year?.toString() ?? '',
    );
    _platformController = TextEditingController(text: filter.platform ?? '');
  }

  @override
  void dispose() {
    _yearController.dispose();
    _platformController.dispose();
    super.dispose();
  }

  void _clear() {
    setState(() {
      _category = null;
      _seriesOnly = false;
      _month = null;
      _yearController.clear();
      _platformController.clear();
    });
  }

  void _apply() {
    final year = int.tryParse(_yearController.text.trim());
    widget.onApply(
      SubjectBrowseFilter(
        type: widget.initialFilter.type,
        category: _category,
        series: _seriesOnly ? true : null,
        platform: _platformController.text.trim().isEmpty
            ? null
            : _platformController.text.trim(),
        year: year,
        month: year == null ? null : _month,
        sort: widget.initialFilter.sort,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = subjectBrowseCategories(widget.initialFilter.type);
    final isBook = widget.initialFilter.type == BgmConst.subjectBook;
    final isGame = widget.initialFilter.type == BgmConst.subjectGame;
    final hasYear = _yearController.text.trim().isNotEmpty;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        shrinkWrap: widget.onCancel != null,
        children: [
          Row(
            children: [
              Text(
                '筛选',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              TextButton(onPressed: _clear, child: const Text('重置')),
              if (widget.onCancel != null)
                IconButton(
                  tooltip: '关闭',
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('分类'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: categories.map((category) {
                return ChoiceChip(
                  selected: _category == category.value,
                  label: Text(category.label),
                  onSelected: (selected) {
                    setState(() {
                      _category = selected ? category.value : null;
                    });
                  },
                );
              }).toList(),
            ),
          ],
          if (isBook) ...[
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('仅系列主条目'),
              value: _seriesOnly,
              onChanged: (value) => setState(() => _seriesOnly = value),
            ),
          ],
          if (isGame) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _platformController,
              decoration: const InputDecoration(
                labelText: '平台',
                hintText: '例如 PC、PS5、Switch',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _yearController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '年份',
                    hintText: '例如 2026',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    if (!mounted) return;
                    setState(() {
                      if (_yearController.text.trim().isEmpty) {
                        _month = null;
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int?>(
                  initialValue: hasYear ? _month : null,
                  decoration: const InputDecoration(
                    labelText: '月份',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('全部')),
                    ...List.generate(
                      12,
                      (index) => DropdownMenuItem(
                        value: index + 1,
                        child: Text('${index + 1} 月'),
                      ),
                    ),
                  ],
                  onChanged: hasYear
                      ? (value) => setState(() => _month = value)
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('subject_browse_apply_filter'),
            onPressed: _apply,
            icon: const Icon(Icons.check_rounded),
            label: const Text('应用筛选'),
          ),
        ],
      ),
    );
  }
}
