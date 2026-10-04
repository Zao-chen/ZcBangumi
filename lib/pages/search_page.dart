import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/scroll_aware_scaffold.dart';
import '../constants.dart';
import '../models/character.dart';
import '../models/person.dart';
import '../models/subject.dart';
import '../models/subject_search.dart';
import '../models/subject_tag_query.dart';
import '../models/unified_search.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../widgets/search_filter_drawer.dart';
import '../widgets/search_result_cards.dart';

/// 同时支持条目、角色和人物的统一搜索页面。
class SearchPage extends StatefulWidget {
  final int? initialSubjectType;
  final String? initialTag;

  const SearchPage({super.key, this.initialSubjectType, this.initialTag});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const int _allSubjectTypes = 0;
  static const int _pageSize = 30;
  static const int _previewSize = 6;

  static const _subjectTypes = [
    (type: _allSubjectTypes, label: '全部', icon: Icons.apps_outlined),
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

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  final FocusNode _tagFocusNode = FocusNode();
  final ScrollController _resultsController = ScrollController();

  late SearchScope _scope;
  late int _selectedSubjectType;
  SubjectSearchSort _subjectSort = SubjectSearchSort.match;
  UnifiedSearchOptions _options = const UnifiedSearchOptions();
  bool _tagEditorOpen = false;

  List<SlimSubject> _subjects = const [];
  List<Character> _characters = const [];
  List<PersonSummary> _persons = const [];
  int _subjectTotal = 0;
  int _characterTotal = 0;
  int _personTotal = 0;
  int _subjectOffset = 0;
  int _characterOffset = 0;
  int _personOffset = 0;

  bool _isSearching = false;
  bool _isLoadingMore = false;
  String _submittedQuery = '';
  String? _searchError;
  String? _loadMoreError;
  String? _subjectError;
  String? _characterError;
  String? _personError;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scope = widget.initialSubjectType == null
        ? SearchScope.all
        : SearchScope.subjects;
    _selectedSubjectType = widget.initialSubjectType ?? _allSubjectTypes;
    final initialTag = widget.initialTag?.trim() ?? '';
    if (initialTag.isNotEmpty) {
      _options = UnifiedSearchOptions(tags: [initialTag]);
    }
    _resultsController.addListener(_handleResultsScroll);
    if (initialTag.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search('');
      });
    }
  }

  @override
  void dispose() {
    _resultsController.dispose();
    _searchController.dispose();
    _tagController.dispose();
    _tagFocusNode.dispose();
    super.dispose();
  }

  StorageService? get _storage =>
      context.read<AuthProvider?>()?.storage ?? context.read<StorageService?>();

  ApiClient? get _api =>
      context.read<AuthProvider?>()?.api ?? context.read<ApiClient?>();

  bool get _hasSubjectCriteria =>
      _submittedQuery.isNotEmpty ||
      _options.activeLabelsFor(SearchScope.subjects).isNotEmpty;

  bool get _hasCurrentCriteria => switch (_scope) {
    SearchScope.subjects => _hasSubjectCriteria,
    SearchScope.characters || SearchScope.persons => _submittedQuery.isNotEmpty,
    SearchScope.all => _submittedQuery.isNotEmpty,
  };

  SubjectTagQuery get _savedSubjectQuery => SubjectTagQuery(
    subjectType: _subjectTypeFilter,
    keyword: _submittedQuery,
    sort: _subjectSort,
    options: _options,
  );

  bool get _isFavoriteSubjectQuery =>
      (_storage?.favoriteTagSearches ?? const []).any(
        (query) => query.identity == _savedSubjectQuery.identity,
      );

  int? get _subjectTypeFilter =>
      _scope != SearchScope.subjects || _selectedSubjectType == _allSubjectTypes
      ? null
      : _selectedSubjectType;

  bool get _hasMoreResults => switch (_scope) {
    SearchScope.subjects => _subjectOffset < _subjectTotal,
    SearchScope.characters => _characterOffset < _characterTotal,
    SearchScope.persons => _personOffset < _personTotal,
    SearchScope.all => false,
  };

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
    final canSearch = switch (_scope) {
      SearchScope.subjects =>
        query.isNotEmpty ||
            _options.activeLabelsFor(SearchScope.subjects).isNotEmpty,
      SearchScope.characters || SearchScope.persons =>
        query.isNotEmpty || _options.activeLabelsFor(_scope).isNotEmpty,
      SearchScope.all => query.isNotEmpty,
    };
    if (!canSearch) {
      _clearSearchState(clearInput: false);
      return;
    }

    setState(() {
      _submittedQuery = query;
      _isSearching = true;
      _isLoadingMore = false;
      _searchError = null;
      _loadMoreError = null;
      _subjectError = null;
      _characterError = null;
      _personError = null;
      _subjects = const [];
      _characters = const [];
      _persons = const [];
      _subjectTotal = 0;
      _characterTotal = 0;
      _personTotal = 0;
      _subjectOffset = 0;
      _characterOffset = 0;
      _personOffset = 0;
    });

    if (_scope == SearchScope.all) {
      await _searchAll(query, generation);
    } else {
      await _searchSingleScope(query, generation);
    }
  }

  Future<void> _searchAll(String query, int generation) async {
    final api = _api;
    if (api == null) {
      if (mounted && generation == _searchGeneration) {
        setState(() => _isSearching = false);
      }
      return;
    }
    const unfilteredOptions = UnifiedSearchOptions();
    PagedResult<SlimSubject>? subjectPage;
    PagedResult<Character>? characterPage;
    PagedResult<PersonSummary>? personPage;
    String? subjectError;
    String? characterError;
    String? personError;

    Future<void> loadSubjects() async {
      try {
        subjectPage = await api.searchSubjects(
          keyword: query,
          sort: SubjectSearchSort.match,
          filter: unfilteredOptions.toSubjectFilter(subjectType: null),
          limit: _previewSize,
        );
      } catch (_) {
        subjectError = '条目搜索暂时不可用';
      }
    }

    Future<void> loadCharacters() async {
      try {
        characterPage = await api.searchCharacters(
          keyword: query,
          filter: unfilteredOptions.toCharacterFilter(),
          limit: _previewSize,
        );
      } catch (_) {
        characterError = '角色搜索暂时不可用';
      }
    }

    Future<void> loadPersons() async {
      try {
        personPage = await api.searchPersons(
          keyword: query,
          filter: unfilteredOptions.toPersonFilter(),
          limit: _previewSize,
        );
      } catch (_) {
        personError = '人物搜索暂时不可用';
      }
    }

    await Future.wait([loadSubjects(), loadCharacters(), loadPersons()]);
    if (!mounted || generation != _searchGeneration) return;

    final allFailed =
        subjectPage == null && characterPage == null && personPage == null;
    setState(() {
      _subjects = subjectPage?.data ?? const [];
      _characters = characterPage?.data ?? const [];
      _persons = personPage?.data ?? const [];
      _subjectTotal = subjectPage?.total ?? 0;
      _characterTotal = characterPage?.total ?? 0;
      _personTotal = personPage?.total ?? 0;
      _subjectOffset = _nextOffset(subjectPage);
      _characterOffset = _nextOffset(characterPage);
      _personOffset = _nextOffset(personPage);
      _subjectError = subjectError;
      _characterError = characterError;
      _personError = personError;
      _searchError = allFailed ? '搜索服务暂时不可用，请稍后重试' : null;
      _isSearching = false;
    });
    _scrollToTop(generation);
  }

  Future<void> _searchSingleScope(String query, int generation) async {
    final api = _api;
    if (api == null) {
      if (mounted && generation == _searchGeneration) {
        setState(() => _isSearching = false);
      }
      return;
    }
    try {
      switch (_scope) {
        case SearchScope.subjects:
          final page = await api.searchSubjects(
            keyword: query,
            sort: _subjectSort,
            filter: _options.toSubjectFilter(subjectType: _subjectTypeFilter),
            limit: _pageSize,
          );
          if (!mounted || generation != _searchGeneration) return;
          setState(() {
            _subjects = page.data;
            _subjectTotal = page.total;
            _subjectOffset = _nextOffset(page);
          });
          await _storage?.recordTagSearch(_savedSubjectQuery);
        case SearchScope.characters:
          final page = await api.searchCharacters(
            keyword: query,
            filter: _options.toCharacterFilter(),
            limit: _pageSize,
          );
          if (!mounted || generation != _searchGeneration) return;
          setState(() {
            _characters = page.data;
            _characterTotal = page.total;
            _characterOffset = _nextOffset(page);
          });
        case SearchScope.persons:
          final page = await api.searchPersons(
            keyword: query,
            filter: _options.toPersonFilter(),
            limit: _pageSize,
          );
          if (!mounted || generation != _searchGeneration) return;
          setState(() {
            _persons = page.data;
            _personTotal = page.total;
            _personOffset = _nextOffset(page);
          });
        case SearchScope.all:
          return;
      }
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _isSearching = false);
      _scrollToTop(generation);
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _isSearching = false;
        _searchError = '网络错误，请稍后重试';
      });
    }
  }

  Future<void> _loadMore() async {
    final hasSearchCriteria = _scope == SearchScope.subjects
        ? _hasSubjectCriteria
        : _submittedQuery.isNotEmpty;
    if (_isSearching ||
        _isLoadingMore ||
        !_hasMoreResults ||
        !hasSearchCriteria ||
        _scope == SearchScope.all) {
      return;
    }

    final generation = _searchGeneration;
    final api = _api;
    if (api == null) return;
    setState(() {
      _isLoadingMore = true;
      _loadMoreError = null;
    });

    try {
      switch (_scope) {
        case SearchScope.subjects:
          final page = await api.searchSubjects(
            keyword: _submittedQuery,
            sort: _subjectSort,
            filter: _options.toSubjectFilter(subjectType: _subjectTypeFilter),
            limit: _pageSize,
            offset: _subjectOffset,
          );
          if (!mounted || generation != _searchGeneration) return;
          setState(() {
            _subjects = _mergeUnique(_subjects, page.data, (item) => item.id);
            _subjectTotal = page.total;
            _subjectOffset = _nextOffset(page);
          });
        case SearchScope.characters:
          final page = await api.searchCharacters(
            keyword: _submittedQuery,
            filter: _options.toCharacterFilter(),
            limit: _pageSize,
            offset: _characterOffset,
          );
          if (!mounted || generation != _searchGeneration) return;
          setState(() {
            _characters = _mergeUnique(
              _characters,
              page.data,
              (item) => item.id,
            );
            _characterTotal = page.total;
            _characterOffset = _nextOffset(page);
          });
        case SearchScope.persons:
          final page = await api.searchPersons(
            keyword: _submittedQuery,
            filter: _options.toPersonFilter(),
            limit: _pageSize,
            offset: _personOffset,
          );
          if (!mounted || generation != _searchGeneration) return;
          setState(() {
            _persons = _mergeUnique(_persons, page.data, (item) => item.id);
            _personTotal = page.total;
            _personOffset = _nextOffset(page);
          });
        case SearchScope.all:
          return;
      }
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _isLoadingMore = false);
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _isLoadingMore = false;
        _loadMoreError = '加载更多失败，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScrollAwareScaffold(
      appBar: AppBar(
        title: const Text('搜索'),
        centerTitle: false,
        actions: [
          if (_scope == SearchScope.subjects && _hasSubjectCriteria)
            IconButton(
              key: const Key('search_save_search'),
              tooltip: _isFavoriteSubjectQuery ? '取消收藏此筛选' : '收藏此筛选',
              icon: Icon(
                _isFavoriteSubjectQuery ? Icons.star : Icons.star_border,
              ),
              onPressed: _toggleFavoriteSubjectQuery,
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildScopeRail(),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      ScrollChromeCollapse(
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                16,
                                24,
                                12,
                              ),
                              child: _buildSearchField(),
                            ),
                            if (_scope == SearchScope.subjects)
                              _buildSubjectTagControls(),
                            if (_scope == SearchScope.subjects)
                              const SizedBox(height: 8),
                          ],
                        ),
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
              ScrollChromeCollapse(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: _buildSearchField(),
                    ),
                    _buildScopeChips(),
                    if (_scope == SearchScope.subjects) ...[
                      const SizedBox(height: 6),
                      _buildSubjectTagControls(),
                    ],
                    const SizedBox(height: 10),
                  ],
                ),
              ),
              Expanded(child: _buildResultContent(12, false)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchField() {
    final supportsFilters = _scope != SearchScope.all;
    final activeFilterCount = supportsFilters
        ? _options.activeLabelsFor(_scope).length
        : 0;
    final sortIsCustom =
        _scope == SearchScope.subjects &&
        _subjectSort != SubjectSearchSort.match;
    final hasCustomSearch = activeFilterCount > 0 || sortIsCustom;
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('search_query_field'),
            controller: _searchController,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: switch (_scope) {
                SearchScope.all => '搜索条目、角色或人物...',
                SearchScope.subjects => '搜索条目...',
                SearchScope.characters => '搜索角色...',
                SearchScope.persons => '搜索人物...',
              },
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
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: _search,
          ),
        ),
        if (supportsFilters) ...[
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
      ],
    );
  }

  void _openTagEditor() {
    setState(() => _tagEditorOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tagFocusNode.requestFocus();
    });
  }

  void _submitTag() {
    final tag = _tagController.text.trim();
    if (tag.isEmpty || _options.tags.contains(tag)) return;
    _tagController.clear();
    setState(() {
      _options = _options.copyWith(tags: [..._options.tags, tag]);
    });
    _search(_submittedQuery);
    _tagFocusNode.requestFocus();
  }

  void _removeSubjectTag(String tag) {
    final tags = _options.tags.where((entry) => entry != tag).toList();
    setState(() => _options = _options.copyWith(tags: tags));
    if (_hasSubjectCriteria) {
      _search(_submittedQuery);
    } else {
      _clearSearchState(clearInput: false);
    }
  }

  Future<void> _toggleFavoriteSubjectQuery() async {
    final storage = _storage;
    if (storage == null) return;
    await storage.toggleFavoriteTagSearch(_savedSubjectQuery);
    if (mounted) setState(() {});
  }

  Widget _buildScopeChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<SearchScope>(
          key: const Key('search_scope_selector'),
          expandedInsets: EdgeInsets.zero,
          showSelectedIcon: false,
          segments: SearchScope.values
              .map(
                (scope) => ButtonSegment(
                  value: scope,
                  icon: Icon(scope.icon, size: 18),
                  label: Text(scope.label),
                ),
              )
              .toList(),
          selected: {_scope},
          onSelectionChanged: (selection) => _selectScope(selection.single),
        ),
      ),
    );
  }

  Widget _buildScopeRail() {
    return NavigationRail(
      minWidth: 104,
      labelType: NavigationRailLabelType.all,
      selectedIndex: SearchScope.values.indexOf(_scope),
      onDestinationSelected: (index) => _selectScope(SearchScope.values[index]),
      destinations: SearchScope.values
          .map(
            (scope) => NavigationRailDestination(
              icon: Icon(scope.icon),
              label: Text(scope.label),
            ),
          )
          .toList(),
    );
  }

  Widget _buildSubjectTypeChips() {
    final selected = _subjectTypes.firstWhere(
      (config) => config.type == _selectedSubjectType,
    );
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<int>(
      key: const Key('search_subject_type_menu'),
      tooltip: '选择条目类型',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      onSelected: _selectSubjectType,
      itemBuilder: (context) => [
        for (final config in _subjectTypes)
          PopupMenuItem<int>(
            key: Key('search_subject_type_${config.type}'),
            value: config.type,
            child: Row(
              children: [
                Icon(config.icon, size: 18),
                const SizedBox(width: 10),
                Text(config.label),
                if (config.type == _selectedSubjectType) ...[
                  const Spacer(),
                  Icon(Icons.check, size: 18, color: colorScheme.primary),
                ],
              ],
            ),
          ),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected.icon, size: 18),
              const SizedBox(width: 7),
              Text(selected.label),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubjectTagControls() {
    final tags = _options.tags;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final tag in tags)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InputChip(
                          key: ValueKey('search_tag_$tag'),
                          label: Text(tag),
                          selected: true,
                          showCheckmark: false,
                          onDeleted: () => _removeSubjectTag(tag),
                          deleteButtonTooltipMessage: '移除标签：$tag',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final addButton = _tagEditorOpen
                  ? _buildTagInput()
                  : OutlinedButton.icon(
                      key: const Key('search_add_tag_button'),
                      onPressed: _openTagEditor,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('添加标签'),
                    );
              final typeButton = _buildSubjectTypeChips();
              if (_tagEditorOpen) {
                return Row(
                  key: const Key('search_tag_shortcuts_row'),
                  children: [
                    typeButton,
                    const SizedBox(width: 8),
                    Expanded(child: addButton),
                  ],
                );
              }
              if (constraints.maxWidth < 330) {
                return Wrap(
                  key: const Key('search_tag_shortcuts_row'),
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [typeButton, addButton],
                );
              }
              return Row(
                key: const Key('search_tag_shortcuts_row'),
                children: [
                  typeButton,
                  const SizedBox(width: 8),
                  addButton,
                  const Spacer(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTagInput() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _tagController,
      builder: (context, value, child) => TextField(
        key: const Key('search_tag_input'),
        controller: _tagController,
        focusNode: _tagFocusNode,
        textInputAction: TextInputAction.search,
        onEditingComplete: () {},
        onSubmitted: (_) => _submitTag(),
        decoration: InputDecoration(
          hintText: '输入标签后回车',
          isDense: true,
          prefixIcon: const Icon(Icons.local_offer_outlined, size: 20),
          suffixIcon: IconButton(
            key: const Key('search_tag_submit'),
            tooltip: '添加标签',
            onPressed: value.text.trim().isEmpty ? null : _submitTag,
            icon: const Icon(Icons.add),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Future<void> _showFilterDrawer() async {
    final result = await showGeneralDialog<SearchFilterSelection>(
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
                child: SearchFilterDrawer(
                  scope: _scope,
                  initialSort: _subjectSort,
                  initialOptions: _options,
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
      _subjectSort = result.sort;
      _options = result.options;
    });
    if (_scope == SearchScope.subjects
        ? _hasSubjectCriteria
        : _submittedQuery.isNotEmpty) {
      _search(_submittedQuery);
    }
  }

  void _selectScope(SearchScope scope) {
    if (_scope == scope) return;
    _searchGeneration++;
    setState(() {
      _scope = scope;
      _searchError = null;
      _loadMoreError = null;
    });
    if (_scope == SearchScope.subjects
        ? _hasSubjectCriteria
        : _submittedQuery.isNotEmpty) {
      _search(_submittedQuery);
    }
  }

  void _selectSubjectType(int type) {
    if (_selectedSubjectType == type) return;
    setState(() => _selectedSubjectType = type);
    if (_scope == SearchScope.subjects
        ? _hasSubjectCriteria
        : _submittedQuery.isNotEmpty) {
      _search(_submittedQuery);
    }
  }

  void _clearSearch() {
    _searchController.clear();
    if (_scope == SearchScope.subjects &&
        _options.activeLabelsFor(SearchScope.subjects).isNotEmpty) {
      _search('');
    } else {
      _clearSearchState(clearInput: false);
    }
  }

  void _clearSearchState({required bool clearInput}) {
    _searchGeneration++;
    if (clearInput) _searchController.clear();
    setState(() {
      _submittedQuery = '';
      _subjects = const [];
      _characters = const [];
      _persons = const [];
      _subjectTotal = 0;
      _characterTotal = 0;
      _personTotal = 0;
      _subjectOffset = 0;
      _characterOffset = 0;
      _personOffset = 0;
      _isSearching = false;
      _isLoadingMore = false;
      _searchError = null;
      _loadMoreError = null;
      _subjectError = null;
      _characterError = null;
      _personError = null;
    });
  }

  Widget _buildResultContent(double horizontalPadding, bool isWide) {
    if (_isSearching) {
      return _buildSearchSkeletonList(horizontalPadding, isWide);
    }
    if (_searchError != null) return _buildErrorState(_searchError!);
    if (!_hasCurrentCriteria) {
      if (_scope == SearchScope.subjects) {
        return _buildSubjectHome(horizontalPadding);
      }
      return _buildMessageState(
        icon: Icons.manage_search_outlined,
        message: '输入关键词搜索条目、角色或人物',
      );
    }
    if (_scope == SearchScope.all) {
      return _buildAllResults(horizontalPadding);
    }

    final (count, emptyMessage, builder) = switch (_scope) {
      SearchScope.subjects => (
        _subjects.length,
        '没有找到相关条目',
        (int index) => SubjectSearchResultCard(
          key: ValueKey('subject_${_subjects[index].id}'),
          subject: _subjects[index],
        ),
      ),
      SearchScope.characters => (
        _characters.length,
        '没有找到相关角色',
        (int index) => CharacterSearchResultCard(
          key: ValueKey('character_${_characters[index].id}'),
          character: _characters[index],
        ),
      ),
      SearchScope.persons => (
        _persons.length,
        '没有找到相关人物',
        (int index) => PersonSearchResultCard(
          key: ValueKey('person_${_persons[index].id}'),
          person: _persons[index],
        ),
      ),
      SearchScope.all => throw StateError('全部搜索使用分组结果'),
    };
    if (count == 0) {
      return _buildMessageState(
        icon: Icons.inbox_outlined,
        message: emptyMessage,
      );
    }
    return _buildPagedResultList(
      horizontalPadding: horizontalPadding,
      isWide: isWide,
      count: count,
      itemBuilder: builder,
    );
  }

  Widget _buildSubjectHome(double horizontalPadding) {
    final recent = _storage?.recentTagSearches ?? const <SubjectTagQuery>[];
    final favorites =
        _storage?.favoriteTagSearches ?? const <SubjectTagQuery>[];
    return ListView(
      controller: _resultsController,
      padding: EdgeInsets.fromLTRB(horizontalPadding, 4, horizontalPadding, 24),
      children: [
        if (favorites.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('收藏', style: Theme.of(context).textTheme.titleSmall),
          for (final query in favorites) _buildSavedSubjectQuery(query, true),
        ],
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Text('最近搜索', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton(
                key: const Key('search_clear_history'),
                onPressed: () async {
                  await _storage?.clearRecentTagSearches();
                  if (mounted) setState(() {});
                },
                child: const Text('清空'),
              ),
            ],
          ),
          for (final query in recent) _buildSavedSubjectQuery(query, false),
        ],
      ],
    );
  }

  Widget _buildSavedSubjectQuery(SubjectTagQuery query, bool favorite) {
    return ListTile(
      key: ValueKey('search_saved_${query.identity}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(favorite ? Icons.star_outline : Icons.history),
      title: Text(query.label, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        query.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        setState(() {
          _scope = SearchScope.subjects;
          _selectedSubjectType = query.subjectType ?? _allSubjectTypes;
          _subjectSort = query.sort;
          _options = query.options;
          _searchController.text = query.keyword;
        });
        _search(query.keyword);
      },
    );
  }

  Widget _buildAllResults(double horizontalPadding) {
    return ListView(
      controller: _resultsController,
      padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 24),
      children: [
        SearchPreviewSection(
          key: const Key('search_section_subjects'),
          title: '条目',
          icon: SearchScope.subjects.icon,
          total: _subjectTotal,
          error: _subjectError,
          onShowAll: () => _selectScope(SearchScope.subjects),
          children: _subjects
              .map((subject) => SubjectSearchResultCard(subject: subject))
              .toList(),
        ),
        SearchPreviewSection(
          key: const Key('search_section_characters'),
          title: '角色',
          icon: SearchScope.characters.icon,
          total: _characterTotal,
          error: _characterError,
          onShowAll: () => _selectScope(SearchScope.characters),
          children: _characters
              .map(
                (character) => CharacterSearchResultCard(character: character),
              )
              .toList(),
        ),
        SearchPreviewSection(
          key: const Key('search_section_persons'),
          title: '人物',
          icon: SearchScope.persons.icon,
          total: _personTotal,
          error: _personError,
          onShowAll: () => _selectScope(SearchScope.persons),
          children: _persons
              .map((person) => PersonSearchResultCard(person: person))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildPagedResultList({
    required double horizontalPadding,
    required bool isWide,
    required int count,
    required Widget Function(int index) itemBuilder,
  }) {
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
                    (context, index) => itemBuilder(index),
                    childCount: count,
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => itemBuilder(index),
                    childCount: count,
                  ),
                ),
        ),
        if (_hasMoreResults || _isLoadingMore || _loadMoreError != null)
          SliverToBoxAdapter(child: _buildPaginationFooter()),
      ],
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => _search(_submittedQuery),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageState({required IconData icon, required String message}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
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
    Widget skeletonCard(int index) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 80,
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
                    _skeletonLine(colorScheme, 160, 14),
                    const SizedBox(height: 10),
                    _skeletonLine(colorScheme, double.infinity, 10),
                    const SizedBox(height: 7),
                    _skeletonLine(colorScheme, 190, 10),
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
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
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
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      itemCount: 6,
      itemBuilder: (context, index) => skeletonCard(index),
    );
  }

  Widget _skeletonLine(ColorScheme scheme, double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  void _scrollToTop(int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _searchGeneration ||
          !_resultsController.hasClients) {
        return;
      }
      _resultsController.jumpTo(0);
    });
  }
}

extension on SearchScope {
  String get label => switch (this) {
    SearchScope.all => '综合',
    SearchScope.subjects => '条目',
    SearchScope.characters => '角色',
    SearchScope.persons => '人物',
  };

  IconData get icon => switch (this) {
    SearchScope.all => Icons.manage_search_rounded,
    SearchScope.subjects => Icons.movie_filter_outlined,
    SearchScope.characters => Icons.face_outlined,
    SearchScope.persons => Icons.badge_outlined,
  };
}

int _nextOffset<T>(PagedResult<T>? page) {
  if (page == null) return 0;
  return page.data.isEmpty ? page.total : page.offset + page.data.length;
}

List<T> _mergeUnique<T>(
  List<T> current,
  List<T> incoming,
  int Function(T item) idOf,
) {
  final ids = current.map(idOf).toSet();
  return [...current, ...incoming.where((item) => ids.add(idOf(item)))];
}

class SearchPreviewSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final int total;
  final String? error;
  final VoidCallback onShowAll;
  final List<Widget> children;

  const SearchPreviewSection({
    super.key,
    required this.title,
    required this.icon,
    required this.total,
    required this.error,
    required this.onShowAll,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (total > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '$total',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
              const Spacer(),
              if (total > 0)
                TextButton.icon(
                  onPressed: onShowAll,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.chevron_right, size: 18),
                  label: const Text('查看全部'),
                ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(error!, style: TextStyle(color: colorScheme.error)),
            )
          else if (children.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '没有匹配结果',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            )
          else
            ...children,
        ],
      ),
    );
  }
}
