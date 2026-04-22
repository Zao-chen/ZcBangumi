import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/character.dart';
import '../models/collection.dart';
import '../models/comment.dart';
import '../pages/profile_page.dart';
import '../models/episode.dart';
import '../models/subject.dart';
import '../models/subject_tab_config.dart';
import '../providers/app_state_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/link_navigator.dart';
import '../services/storage_service.dart';
import '../widgets/progress_grid.dart';
import '../widgets/subject_action_buttons.dart';
import '../widgets/bangumi_content_view.dart';
import '../widgets/copyable_text.dart';
import '../widgets/copyable_chip.dart';
import 'character_page.dart';
import 'web_page_viewer.dart';

class SubjectPage extends StatefulWidget {
  final int subjectId;
  final Subject? subject;

  const SubjectPage({super.key, required this.subjectId, this.subject});

  @override
  State<SubjectPage> createState() => _SubjectPageState();
}

class _SubjectPageState extends State<SubjectPage>
    with TickerProviderStateMixin {
  static final Map<String, _SubjectTabItem> _tabItemsById = {
    for (final tab in SubjectTabConfig.allTabs)
      tab.id: _SubjectTabItem(label: tab.label, icon: tab.icon),
  };

  late TabController _tabController;
  final ScrollController _nestedScrollController = ScrollController();
  final TransformationController _mindMapTransformController =
      TransformationController();
  static const double _mindMapMinScale = 0.2;
  static const double _mindMapMaxScale = 2.2;
  static const double _mindMapFitPadding = 16;
  final Set<int> _expandedRelatedNodes = <int>{};
  final Set<int> _expandingRelatedNodes = <int>{};
  final Map<int, List<RelatedSubject>> _expandedRelatedChildren =
      <int, List<RelatedSubject>>{};
  final Set<String> _collapsedRelationGroups = <String>{};
  Subject? _subject;
  UserCollection? _userCollection;
  List<Character> _characters = [];
  List<RelatedSubject> _relatedSubjects = [];
  List<UserEpisodeCollection> _episodes = [];
  List<Comment> _comments = [];
  bool _loading = true;
  bool _charactersLoading = false;
  bool _relatedLoading = false;
  bool _commentsLoading = false;
  bool _episodesLoading = false;
  bool _subjectDetailLoading = false;
  bool _showCollapsedTitle = false;
  int _selectedTabIndex = 0;
  List<String> _visibleTabIds = List<String>.from(
    SubjectTabConfig.defaultOrder,
  );
  _RelatedViewMode _relatedViewMode = _RelatedViewMode.list;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _visibleTabIds.length, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _nestedScrollController.addListener(_handleHeaderCollapse);
    _restoreRelatedViewMode();
    if (widget.subject != null) {
      _subject = widget.subject;
      _loading = false;
    }
    _loadAllData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSubjectTabs(Provider.of<AppStateProvider>(context));
  }

  @override
  void dispose() {
    _nestedScrollController
      ..removeListener(_handleHeaderCollapse)
      ..dispose();
    _mindMapTransformController.dispose();
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  List<_SubjectTabItem> get _visibleTabItems => _visibleTabIds
      .map((id) => _tabItemsById[id])
      .whereType<_SubjectTabItem>()
      .toList(growable: false);

  String? get _selectedTabId {
    if (_visibleTabIds.isEmpty ||
        _selectedTabIndex < 0 ||
        _selectedTabIndex >= _visibleTabIds.length) {
      return null;
    }
    return _visibleTabIds[_selectedTabIndex];
  }

  void _syncSubjectTabs(AppStateProvider appState) {
    final nextVisibleIds = appState.enabledSubjectTabIds;
    if (listEquals(_visibleTabIds, nextVisibleIds) || nextVisibleIds.isEmpty) {
      return;
    }

    final currentTabId = _selectedTabId;
    final nextIndex = currentTabId == null
        ? 0
        : nextVisibleIds.indexOf(currentTabId);
    final normalizedIndex = nextIndex >= 0 ? nextIndex : 0;

    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _visibleTabIds = List<String>.from(nextVisibleIds);
    _selectedTabIndex = normalizedIndex;
    _tabController = TabController(
      length: _visibleTabIds.length,
      vsync: this,
      initialIndex: normalizedIndex,
    );
    _tabController.addListener(_handleTabChanged);
  }

  void _handleTabChanged() {
    if (!mounted) {
      return;
    }
    if (_selectedTabIndex != _tabController.index) {
      setState(() => _selectedTabIndex = _tabController.index);
    }
  }

  void _handleHeaderCollapse() {
    if (!_nestedScrollController.hasClients) {
      return;
    }

    final shouldShowTitle = _nestedScrollController.offset > 110;
    if (shouldShowTitle != _showCollapsedTitle && mounted) {
      setState(() => _showCollapsedTitle = shouldShowTitle);
    }
  }

  void _restoreRelatedViewMode() {
    final storage = context.read<StorageService>();
    final cached = storage.getCache(_relatedViewModeCacheName);
    if (cached is String) {
      if (cached == 'mind_map') {
        _relatedViewMode = _RelatedViewMode.mindMap;
      } else if (cached == 'list') {
        _relatedViewMode = _RelatedViewMode.list;
      }
    }
  }

  void _setRelatedViewMode(_RelatedViewMode mode) {
    if (_relatedViewMode == mode) {
      return;
    }
    _mindMapTransformController.value = Matrix4.identity();
    setState(() => _relatedViewMode = mode);
    final storage = context.read<StorageService>();
    storage.setCache(
      _relatedViewModeCacheName,
      mode == _RelatedViewMode.mindMap ? 'mind_map' : 'list',
    );
  }

  String get _cacheName => 'subject_${widget.subjectId}';
  String get _charsCacheName => 'subject_chars_${widget.subjectId}';
  String get _relatedCacheName => 'subject_related_${widget.subjectId}';
  String get _episodesCacheName => 'subject_episodes_${widget.subjectId}';
  String get _commentsCacheName => 'subject_comments_${widget.subjectId}';
  String get _userCollectionCacheName =>
      'subject_user_collection_${widget.subjectId}';
  String get _relatedViewModeCacheName => 'subject_related_view_mode';

  Subject? _readSubjectFromCache(StorageService storage) {
    final cached = storage.getCache(_cacheName);
    if (cached is Map<String, dynamic>) {
      try {
        return Subject.fromJson(cached);
      } catch (_) {}
    }

    final recent = storage.getRecentSubjectDetails(limit: 50);
    for (final item in recent) {
      if (item.id == widget.subjectId) {
        return item;
      }
    }
    return null;
  }

  Future<void> _loadAllData() async {
    final storage = context.read<StorageService>();
    final api = context.read<ApiClient>();

    if (_subject == null) {
      _subject = _readSubjectFromCache(storage);
    }

    if (_characters.isEmpty) {
      final charsCached = storage.getCache(_charsCacheName);
      if (charsCached is List) {
        try {
          _characters = charsCached
              .whereType<Map<String, dynamic>>()
              .map((e) => Character.fromJson(e))
              .toList();
        } catch (_) {}
      }
    }

    if (_relatedSubjects.isEmpty) {
      final relatedCached = storage.getCache(_relatedCacheName);
      if (relatedCached is List) {
        try {
          _relatedSubjects = relatedCached
              .whereType<Map<String, dynamic>>()
              .map((e) => RelatedSubject.fromJson(e))
              .toList();
        } catch (_) {}
      }
    }

    if (_episodes.isEmpty) {
      final episodesCached = storage.getCache(_episodesCacheName);
      if (episodesCached is List) {
        try {
          _episodes = episodesCached
              .whereType<Map<String, dynamic>>()
              .map((e) => UserEpisodeCollection.fromJson(e))
              .toList();
        } catch (_) {}
      }
    }

    if (_comments.isEmpty) {
      final commentsCached = storage.getCache(_commentsCacheName);
      if (commentsCached is List) {
        try {
          _comments = commentsCached
              .whereType<Map<String, dynamic>>()
              .map((e) => Comment.fromJson(e))
              .toList();
        } catch (_) {}
      }
    }

    if (_userCollection == null) {
      final userCollectionCached = storage.getCache(_userCollectionCacheName);
      if (userCollectionCached is Map<String, dynamic>) {
        try {
          _userCollection = UserCollection.fromJson(userCollectionCached);
        } catch (_) {}
      }
    }

    if (_subject != null) {
      storage.setCache(_cacheName, _subject!.toJson());
      storage.saveRecentSubjectDetail(_subject!);
    }

    setState(() {
      _loading = _subject == null;
      _charactersLoading = _characters.isEmpty;
      _relatedLoading = _relatedSubjects.isEmpty;
      _commentsLoading = _comments.isEmpty;
      _error = null;
    });

    if (mounted) {
      setState(() => _subjectDetailLoading = true);
    }

    try {
      Subject? subject;
      try {
        subject = await api.getSubject(widget.subjectId);
      } catch (e) {
        if (_subject == null) {
          throw Exception('Failed to fetch subject: $e');
        }
      }

      if (subject == null && _subject == null) {
        setState(() => _error = '无法获取条目信息');
        return;
      }

      if (subject != null) {
        _subject = subject;
      }

      final charsFuture = api.getSubjectCharacters(widget.subjectId);
      final relatedFuture = api.getSubjectRelations(widget.subjectId);
      final commentsFuture = api.getSubjectComments(
        subjectId: widget.subjectId,
      );

      final results = await Future.wait([
        charsFuture,
        relatedFuture,
        commentsFuture,
      ], eagerError: false);

      setState(() {
        _characters = results[0] is List<Character>
            ? results[0] as List<Character>
            : _characters;
        _relatedSubjects = results[1] is List<RelatedSubject>
            ? results[1] as List<RelatedSubject>
            : _relatedSubjects;
        if (results[2] is PagedResult<Comment>) {
          final commentsResult = results[2] as PagedResult<Comment>;
          _comments = commentsResult.data;
        }
        _charactersLoading = false;
        _relatedLoading = false;
        _commentsLoading = false;
        _error = null;
      });

      if (_subject != null) {
        storage.setCache(_cacheName, _subject!.toJson());
        storage.saveRecentSubjectDetail(_subject!);
      }
      storage.setCache(
        _charsCacheName,
        _characters.map((c) => c.toJson()).toList(),
      );
      storage.setCache(
        _relatedCacheName,
        _relatedSubjects.map((r) => r.toJson()).toList(),
      );
      storage.setCache(
        _commentsCacheName,
        _comments.map((c) => c.toJson()).toList(),
      );

      _loadEpisodeProgress();
      _loadUserCollection();
    } catch (e) {
      if (_subject == null) {
        setState(() => _error = '加载失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _subjectDetailLoading = false;
          _charactersLoading = false;
          _relatedLoading = false;
          _commentsLoading = false;
        });
      }
    }
  }

  Future<void> _loadEpisodeProgress() async {
    final storage = context.read<StorageService>();
    final api = context.read<ApiClient>();
    final authProvider = context.read<AuthProvider>();

    if (!authProvider.isLoggedIn) {
      return;
    }

    final shouldShowLoading = _episodes.isEmpty;
    if (_episodesLoading != shouldShowLoading) {
      setState(() => _episodesLoading = shouldShowLoading);
    }

    try {
      final result = await api.getUserEpisodeCollections(
        subjectId: widget.subjectId,
      );

      setState(() {
        _episodes = result.data;
      });

      storage.setCache(
        _episodesCacheName,
        _episodes.map((e) => e.toJson()).toList(),
      );
    } catch (e) {
    } finally {
      if (mounted && _episodesLoading) {
        setState(() => _episodesLoading = false);
      }
    }
  }

  Future<void> _loadUserCollection() async {
    final api = context.read<ApiClient>();
    final authProvider = context.read<AuthProvider>();
    final storage = context.read<StorageService>();

    if (!authProvider.isLoggedIn) {
      return;
    }

    try {
      final collection = await api.getUserCollection(
        username: authProvider.user!.username,
        subjectId: widget.subjectId,
      );
      if (mounted) {
        setState(() {
          _userCollection = collection;
        });
      }
      storage.setCache(_userCollectionCacheName, collection.toJson());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        if (mounted) {
          setState(() {
            _userCollection = null;
          });
        }
        storage.removeCache(_userCollectionCacheName);
      }
    } catch (e) {}
  }

  Future<void> _setEpisodeStatus(int episodeId, int newType) async {
    final api = context.read<ApiClient>();
    try {
      await api.putEpisodeCollection(episodeId: episodeId, type: newType);

      final index = _episodes.indexWhere((e) => e.episode.id == episodeId);
      if (index != -1) {
        setState(() {
          _episodes[index] = UserEpisodeCollection(
            episode: _episodes[index].episode,
            type: newType,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('设置状态失败: $e')));
      }
    }
  }

  Future<void> _watchUpTo(int episodeSort) async {
    final api = context.read<ApiClient>();
    final storage = context.read<StorageService>();
    final toWatch = _episodes
        .where(
          (e) =>
              e.episode.type == 0 &&
              e.episode.sort <= episodeSort &&
              e.type != BgmConst.episodeDone,
        )
        .map((e) => e.episode.id)
        .toList();
    if (toWatch.isEmpty) {
      if (_subject?.type == BgmConst.subjectBook) {
        try {
          await api.patchCollection(
            subjectId: widget.subjectId,
            epStatus: episodeSort,
          );
          if (_userCollection != null) {
            setState(() {
              _userCollection = UserCollection(
                subjectId: _userCollection!.subjectId,
                subjectType: _userCollection!.subjectType,
                rate: _userCollection!.rate,
                type: _userCollection!.type,
                comment: _userCollection!.comment,
                tags: _userCollection!.tags,
                epStatus: episodeSort,
                volStatus: _userCollection!.volStatus,
                updatedAt: _userCollection!.updatedAt,
                private_: _userCollection!.private_,
                subject: _userCollection!.subject,
              );
            });
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('更新阅读进度失败: $e')));
          }
        }
      }
      return;
    }

    final toWatchSet = toWatch.toSet();
    setState(() {
      for (var i = 0; i < _episodes.length; i++) {
        if (toWatchSet.contains(_episodes[i].episode.id)) {
          _episodes[i] = UserEpisodeCollection(
            episode: _episodes[i].episode,
            type: BgmConst.episodeDone,
          );
        }
      }
    });

    try {
      await api.patchEpisodeCollections(
        subjectId: widget.subjectId,
        episodeIds: toWatch,
        type: BgmConst.episodeDone,
      );
      storage.setCache(
        _episodesCacheName,
        _episodes.map((e) => e.toJson()).toList(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('批量更新章节失败: $e')));
      }
      await _loadEpisodeProgress();
    }
  }

  Future<void> _openSubjectWebPage() async {
    final uri = Uri.parse('${BgmConst.webBaseUrl}/subject/${widget.subjectId}');
    final ok = await LinkNavigator.openBrowser(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('打开网页失败')));
    }
  }

  Uri? _buildMoegirlUri() {
    final subject = _subject;
    if (subject == null) {
      return null;
    }

    final keyword = subject.nameCn.trim().isNotEmpty
        ? subject.nameCn.trim()
        : subject.name.trim();
    if (keyword.isEmpty) {
      return null;
    }

    return Uri.https('zh.moegirl.org.cn', '/index.php', {'search': keyword});
  }

  Widget _buildSubjectSkeleton({required bool isLandscape}) {
    final colorScheme = Theme.of(context).colorScheme;
    final content = ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return Container(
          height: index == 0 ? 120 : 88,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
        );
      },
    );

    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          SliverAppBar(
            pinned: true,
            expandedHeight: 200,
            flexibleSpace: FlexibleSpaceBar(
              background: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    12,
                    kToolbarHeight + 2,
                    12,
                    0,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!isLandscape)
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarHeaderDelegate(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    border: Border(
                      bottom: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: TabBar(
                    tabs: _visibleTabItems
                        .map((tab) => Tab(text: tab.label))
                        .toList(),
                  ),
                ),
              ),
            ),
        ];
      },
      body: isLandscape
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedTabIndex,
                  onDestinationSelected: (_) {},
                  backgroundColor: colorScheme.surface,
                  indicatorColor: colorScheme.primaryContainer,
                  labelType: NavigationRailLabelType.all,
                  destinations: _visibleTabItems
                      .map(
                        (tab) => NavigationRailDestination(
                          icon: Icon(tab.icon),
                          label: Text(tab.label),
                        ),
                      )
                      .toList(),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    if (_loading && _subject == null) {
      return Scaffold(
        body: DefaultTabController(
          length: _visibleTabIds.length,
          child: _buildSubjectSkeleton(isLandscape: isLandscape),
        ),
      );
    }

    if (_error != null && _subject == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadAllData, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    if (_subject == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('暂无数据')),
      );
    }

    return Scaffold(
      body: NestedScrollView(
        controller: _nestedScrollController,
        physics: _shouldLockTabSwipeForMindMap
            ? const NeverScrollableScrollPhysics()
            : null,
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          final colorScheme = Theme.of(context).colorScheme;
          return [
            SliverAppBar(
              pinned: true,
              elevation: 0,
              scrolledUnderElevation: 0,
              expandedHeight: 200,
              actions: [
                IconButton(
                  tooltip: '打开网页',
                  onPressed: _openSubjectWebPage,
                  icon: const Icon(Icons.open_in_new),
                ),
              ],
              title: _showCollapsedTitle
                  ? GestureDetector(
                      onTap: _showFullTitleDialog,
                      child: Text(
                        _subject!.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  : null,
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      12,
                      kToolbarHeight + 2,
                      12,
                      0,
                    ),
                    child: OrientationBuilder(
                      builder: (context, orientation) {
                        return Align(
                          alignment: Alignment.bottomCenter,
                          child: _buildHeaderCard(
                            colorScheme,
                            isLandscape: orientation == Orientation.landscape,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (!isLandscape)
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarHeaderDelegate(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      tabs: _visibleTabItems
                          .map((tab) => Tab(text: tab.label))
                          .toList(),
                    ),
                  ),
                ),
              ),
          ];
        },
        body: isLandscape ? _buildLandscapeTabs() : _buildTabView(),
      ),
    );
  }

  Widget _buildLandscapeTabs() {
    final colorScheme = Theme.of(context).colorScheme;
    final topInset = _showCollapsedTitle ? (kToolbarHeight + 8) : 0.0;

    return Row(
      children: [
        AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(top: topInset),
          child: NavigationRail(
            selectedIndex: _selectedTabIndex,
            onDestinationSelected: _tabController.animateTo,
            backgroundColor: colorScheme.surface,
            indicatorColor: colorScheme.primaryContainer,
            labelType: NavigationRailLabelType.all,
            destinations: _visibleTabItems
                .map(
                  (tab) => NavigationRailDestination(
                    icon: Icon(tab.icon),
                    label: Text(tab.label),
                  ),
                )
                .toList(),
          ),
        ),
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(child: _buildTabView()),
      ],
    );
  }

  Widget _buildTabView() {
    return TabBarView(
      controller: _tabController,
      physics: _shouldLockTabSwipeForMindMap
          ? const NeverScrollableScrollPhysics()
          : null,
      children: _visibleTabIds.map(_buildTabById).toList(),
    );
  }

  Widget _buildTabById(String tabId) {
    switch (tabId) {
      case SubjectTabConfig.overviewId:
        return _buildOverviewTab();
      case SubjectTabConfig.charactersId:
        return _buildCharactersTab();
      case SubjectTabConfig.relatedId:
        return _buildRelatedTab();
      case SubjectTabConfig.commentsId:
        return _buildCommentsTab();
      case SubjectTabConfig.moegirlId:
        return _buildMoegirlTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildMoegirlTab() {
    final uri = _buildMoegirlUri();
    if (uri == null) {
      return Center(
        child: Text(
          'No subject name',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    return EmbeddedWebPageView(initialUri: uri);
  }

  bool get _shouldLockTabSwipeForMindMap =>
      _selectedTabId == SubjectTabConfig.relatedId &&
      _relatedViewMode == _RelatedViewMode.mindMap;

  String _normalizeSummary(String text) {
    final withoutZeroWidth = text.replaceAll(
      RegExp(r'[\u200B-\u200D\uFEFF]'),
      '',
    );
    final normalizedLineBreaks = withoutZeroWidth
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final collapsedBlankLines = normalizedLineBreaks.replaceAll(
      RegExp(r'\n\s*\n\s*\n+'),
      '\n\n',
    );
    return collapsedBlankLines.trim();
  }

  Widget _buildOverviewTab() {
    final colorScheme = Theme.of(context).colorScheme;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final summaryText = _normalizeSummary(_subject!.summary);
    final shouldShowMetaSkeleton =
        _subjectDetailLoading &&
        _subject!.tags.isEmpty &&
        _subject!.infobox.isEmpty;

    if (isLandscape) {
      return RefreshIndicator(
        onRefresh: _loadAllData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_episodes.isNotEmpty ||
                  _episodesLoading ||
                  _subject!.type == BgmConst.subjectBook ||
                  _subject!.type == BgmConst.subjectGame)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: ProgressGrid(
                    episodes: _episodes,
                    loading: _episodesLoading && _episodes.isEmpty,
                    onSetStatus: _setEpisodeStatus,
                    onWatchUpTo: _watchUpTo,
                    useNumberPicker: _subject!.type == BgmConst.subjectBook,
                    useCollectionTypePicker:
                        _subject!.type == BgmConst.subjectGame,
                    bookCurrentProgress: _userCollection?.epStatus ?? 0,
                    bookMaxProgress: _subject!.eps > 0 ? _subject!.eps : null,
                    collectionSubjectType: _subject!.type,
                    collectionType: _userCollection?.type,
                    onSetCollectionType: (newType) async {
                      final api = context.read<ApiClient>();
                      try {
                        await api.patchCollection(
                          subjectId: widget.subjectId,
                          type: newType,
                        );
                        await _loadUserCollection();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('更新收藏状态失败: $e')),
                          );
                        }
                      }
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (summaryText.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '简介',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  CopyableText(
                                    summaryText,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                    enableLongPressCopy: false,
                                  ),
                                ],
                              ),
                            ),
                          shouldShowMetaSkeleton
                              ? _buildOverviewTagsSkeletonSection(
                                  colorScheme,
                                  padding: EdgeInsets.zero,
                                )
                              : _buildOverviewTagsSection(
                                  colorScheme,
                                  padding: EdgeInsets.zero,
                                ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 2,
                      child: shouldShowMetaSkeleton
                          ? _buildOverviewInfoboxSkeletonSection(
                              colorScheme,
                              padding: EdgeInsets.zero,
                            )
                          : _buildOverviewInfoboxSection(
                              padding: EdgeInsets.zero,
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_episodes.isNotEmpty ||
                _episodesLoading ||
                _subject!.type == BgmConst.subjectBook ||
                _subject!.type == BgmConst.subjectGame)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: ProgressGrid(
                  episodes: _episodes,
                  loading: _episodesLoading && _episodes.isEmpty,
                  onSetStatus: _setEpisodeStatus,
                  onWatchUpTo: _watchUpTo,
                  useNumberPicker: _subject!.type == BgmConst.subjectBook,
                  useCollectionTypePicker:
                      _subject!.type == BgmConst.subjectGame,
                  bookCurrentProgress: _userCollection?.epStatus ?? 0,
                  bookMaxProgress: _subject!.eps > 0 ? _subject!.eps : null,
                  collectionSubjectType: _subject!.type,
                  collectionType: _userCollection?.type,
                  onSetCollectionType: (newType) async {
                    final api = context.read<ApiClient>();
                    try {
                      await api.patchCollection(
                        subjectId: widget.subjectId,
                        type: newType,
                      );
                      await _loadUserCollection();
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('更新收藏状态失败: $e')));
                      }
                    }
                  },
                ),
              ),
            if (summaryText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '简介',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    CopyableText(
                      summaryText,
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      enableLongPressCopy: false,
                    ),
                  ],
                ),
              ),
            if (shouldShowMetaSkeleton)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '标签',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(6, (index) {
                        return Container(
                          width: 48 + (index % 3) * 16,
                          height: 26,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(16),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '详情',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(4, (index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 80,
                              height: 16,
                              margin: const EdgeInsets.only(top: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: index.isEven ? 16 : 34,
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '标签',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_subject!.tags.isEmpty)
                      Text('暂无标签', style: TextStyle(color: Colors.grey[600]))
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _subject!.tags.map((tag) {
                          return CopyableChip(
                            label: tag,
                            labelStyle: const TextStyle(fontSize: 12),
                            backgroundColor: colorScheme.surfaceContainerHigh,
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '详情',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_subject!.infobox.isEmpty)
                      Text('暂无详情', style: TextStyle(color: Colors.grey[600]))
                    else
                      ...List.generate(_subject!.infobox.length, (index) {
                        final entries = _subject!.infobox.entries.toList();
                        final key = entries[index].key;
                        final value = entries[index].value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 80,
                                child: CopyableText(
                                  key,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                ),
                              ),
                              Expanded(
                                child: CopyableText(
                                  value,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTagsSection(
    ColorScheme colorScheme, {
    required EdgeInsets padding,
  }) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '标签',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_subject!.tags.isEmpty)
            Text('暂无标签', style: TextStyle(color: Colors.grey[600]))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _subject!.tags.map((tag) {
                return CopyableChip(
                  label: tag,
                  labelStyle: const TextStyle(fontSize: 12),
                  backgroundColor: colorScheme.surfaceContainerHigh,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildOverviewTagsSkeletonSection(
    ColorScheme colorScheme, {
    required EdgeInsets padding,
  }) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '标签',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(6, (index) {
              return Container(
                width: 48 + (index % 3) * 16,
                height: 26,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewInfoboxSection({required EdgeInsets padding}) {
    final entries = _subject!.infobox.entries.toList();

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '详情',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            Text('暂无详情', style: TextStyle(color: Colors.grey[600]))
          else
            ...List.generate(entries.length, (index) {
              final key = entries[index].key;
              final value = entries[index].value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 80,
                      child: CopyableText(
                        key,
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                        maxLines: 1,
                      ),
                    ),
                    Expanded(
                      child: CopyableText(
                        value,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildOverviewInfoboxSkeletonSection(
    ColorScheme colorScheme, {
    required EdgeInsets padding,
  }) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '详情',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...List.generate(4, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 80,
                    height: 16,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: index.isEven ? 16 : 34,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCharactersTab() {
    if (_charactersLoading && _characters.isEmpty) {
      return _buildCharactersSkeletonList();
    }

    if (_characters.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadAllData,
        child: const Center(child: Text('暂无角色信息')),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: _characters.length,
        itemBuilder: (context, index) {
          final character = _characters[index];
          final imageUrl = character.images.isNotEmpty
              ? character.images.first.medium
              : '';

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CharacterPage(character: character),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: imageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              width: 80,
                              height: 104,
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              placeholder: (context, url) => Container(
                                width: 80,
                                height: 104,
                                color: Colors.grey[300],
                              ),
                              errorWidget: (context, url, error) => Container(
                                width: 80,
                                height: 104,
                                color: Colors.grey[300],
                                child: const Icon(Icons.person),
                              ),
                            )
                          : Container(
                              width: 80,
                              height: 104,
                              color: Colors.grey[300],
                              child: const Icon(Icons.person),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            character.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          if (character.type.isNotEmpty)
                            Text(
                              character.type,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          const SizedBox(height: 2),
                          if (character.comment.isNotEmpty)
                            Text(
                              character.comment,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCharactersSkeletonList() {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: 4,
      itemBuilder: (context, index) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 80,
                  height: 104,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 140,
                        height: 14,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 90,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 180,
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
      },
    );
  }

  Widget _buildRelatedSkeletonList() {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: 4,
      itemBuilder: (context, index) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 80,
                  height: 104,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 140,
                        height: 14,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 90,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 70,
                        height: 22,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: colorScheme.surfaceContainerHighest,
                          ),
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
      },
    );
  }

  Widget _buildCommentsSkeletonList() {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: 3,
      itemBuilder: (context, index) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 100,
                            height: 12,
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: 80,
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
                const SizedBox(height: 12),
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
                  width: 200,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRelatedTab() {
    if (_relatedLoading && _relatedSubjects.isEmpty) {
      return _buildRelatedSkeletonList();
    }

    if (_relatedSubjects.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadAllData,
        child: const Center(child: Text('暂无关联')),
      );
    }

    if (_relatedViewMode == _RelatedViewMode.list) {
      return RefreshIndicator(
        onRefresh: _loadAllData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          children: [
            _buildRelatedViewModeSwitch(),
            const SizedBox(height: 8),
            ..._buildRelatedListItems(),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRelatedViewModeSwitch(),
          const SizedBox(height: 8),
          Expanded(child: _buildRelatedMindMapView()),
        ],
      ),
    );
  }

  Widget _buildRelatedViewModeSwitch() {
    return Row(
      children: [
        Text(
          '展示方式',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('列表'),
          selected: _relatedViewMode == _RelatedViewMode.list,
          onSelected: (_) => _setRelatedViewMode(_RelatedViewMode.list),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('脑图'),
          selected: _relatedViewMode == _RelatedViewMode.mindMap,
          onSelected: (_) => _setRelatedViewMode(_RelatedViewMode.mindMap),
        ),
      ],
    );
  }

  List<Widget> _buildRelatedListItems() {
    return _relatedSubjects.map((related) {
      final imageUrl = related.images['medium'] ?? '';
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: InkWell(
          onTap: () => _openSubjectPage(related.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          width: 80,
                          height: 104,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            width: 80,
                            height: 104,
                            color: Colors.grey[300],
                          ),
                          errorWidget: (context, url, error) => Container(
                            width: 80,
                            height: 104,
                            color: Colors.grey[300],
                            child: const Icon(Icons.image),
                          ),
                        )
                      : Container(
                          width: 80,
                          height: 104,
                          color: Colors.grey[300],
                          child: const Icon(Icons.image),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        related.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '关系: ${related.relation}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[400]!),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _getSubjectTypeLabel(related.type),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  void _handleMindMapPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (
      PointerSignalEvent signal,
    ) {
      final scrollEvent = signal as PointerScrollEvent;
      final clampedDeltaDy = scrollEvent.scrollDelta.dy.clamp(-64.0, 64.0);
      final currentScale = _mindMapTransformController.value
          .getMaxScaleOnAxis();
      final targetScale = (currentScale * math.exp(-clampedDeltaDy / 420))
          .clamp(_mindMapMinScale, _mindMapMaxScale)
          .toDouble();
      final scaleChange = targetScale / currentScale;
      if ((scaleChange - 1).abs() < 0.0001) {
        return;
      }

      final focalScenePoint = _mindMapTransformController.toScene(
        scrollEvent.localPosition,
      );
      final nextMatrix = Matrix4.copy(_mindMapTransformController.value)
        ..translate(focalScenePoint.dx, focalScenePoint.dy)
        ..scale(scaleChange)
        ..translate(-focalScenePoint.dx, -focalScenePoint.dy);
      _mindMapTransformController.value = nextMatrix;
    });
  }

  bool _isIdentityMatrix(Matrix4 matrix) {
    return matrix.storage[0] == 1.0 &&
        matrix.storage[5] == 1.0 &&
        matrix.storage[10] == 1.0 &&
        matrix.storage[15] == 1.0 &&
        matrix.storage[1] == 0.0 &&
        matrix.storage[2] == 0.0 &&
        matrix.storage[3] == 0.0 &&
        matrix.storage[4] == 0.0 &&
        matrix.storage[6] == 0.0 &&
        matrix.storage[7] == 0.0 &&
        matrix.storage[8] == 0.0 &&
        matrix.storage[9] == 0.0 &&
        matrix.storage[11] == 0.0 &&
        matrix.storage[12] == 0.0 &&
        matrix.storage[13] == 0.0 &&
        matrix.storage[14] == 0.0;
  }

  void _fitMindMapToViewport(Size viewportSize, _MindMapLayout layout) {
    if (!_isIdentityMatrix(_mindMapTransformController.value)) {
      return;
    }
    if (viewportSize.width <= 0 || viewportSize.height <= 0) {
      return;
    }

    final availableWidth = math.max(
      1.0,
      viewportSize.width - _mindMapFitPadding * 2,
    );
    final availableHeight = math.max(
      1.0,
      viewportSize.height - _mindMapFitPadding * 2,
    );
    final scaleX = availableWidth / layout.width;
    final scaleY = availableHeight / layout.height;
    final fitScale = math
        .min(scaleX, scaleY)
        .clamp(0.1, _mindMapMaxScale)
        .toDouble();
    final tx = (viewportSize.width - layout.width * fitScale) / 2;
    final ty = (viewportSize.height - layout.height * fitScale) / 2;

    final matrix = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(fitScale);
    _mindMapTransformController.value = matrix;
  }

  Widget _buildRelatedMindMapView() {
    final layout = _buildMindMapLayout();
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportSize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _fitMindMapToViewport(viewportSize, layout);
            });

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (_) {},
              onScaleUpdate: (_) {},
              onScaleEnd: (_) {},
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerSignal: _handleMindMapPointerSignal,
                child: InteractiveViewer(
                  transformationController: _mindMapTransformController,
                  minScale: _mindMapMinScale,
                  maxScale: _mindMapMaxScale,
                  constrained: false,
                  boundaryMargin: EdgeInsets.all(viewportSize.longestSide * 2),
                  clipBehavior: Clip.none,
                  child: SizedBox(
                    width: layout.width,
                    height: layout.height,
                    child: Stack(
                      children: [
                        CustomPaint(
                          size: Size(layout.width, layout.height),
                          painter: _MindMapLinePainter(
                            edges: layout.edges,
                            lineColor: colorScheme.outlineVariant,
                            highlightColor: colorScheme.primary.withOpacity(
                              0.8,
                            ),
                          ),
                        ),
                        ...layout.nodes.map((node) {
                          return Positioned(
                            left: node.rect.left,
                            top: node.rect.top,
                            width: node.rect.width,
                            height: node.rect.height,
                            child: _buildMindMapNode(node),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _toggleRelatedNodeExpansion(RelatedSubject related) async {
    if (_expandedRelatedNodes.contains(related.id)) {
      setState(() => _expandedRelatedNodes.remove(related.id));
      return;
    }

    final cachedChildren = _expandedRelatedChildren[related.id];
    if (cachedChildren != null) {
      setState(() => _expandedRelatedNodes.add(related.id));
      return;
    }

    if (_expandingRelatedNodes.contains(related.id)) {
      return;
    }

    setState(() => _expandingRelatedNodes.add(related.id));
    try {
      final api = context.read<ApiClient>();
      final children = await api.getSubjectRelations(related.id);
      final seen = <int>{};
      final filtered = children.where((item) {
        if (item.id == widget.subjectId || item.id == related.id) {
          return false;
        }
        if (seen.contains(item.id)) {
          return false;
        }
        seen.add(item.id);
        return true;
      }).toList();

      if (!mounted) return;
      setState(() {
        _expandedRelatedChildren[related.id] = filtered;
        if (filtered.isNotEmpty) {
          _expandedRelatedNodes.add(related.id);
        } else {
          _expandedRelatedNodes.remove(related.id);
        }
        final relationSet = <String>{};
        for (final child in filtered) {
          final relation = child.relation.isNotEmpty ? child.relation : '其他';
          relationSet.add(relation);
        }
        for (final relation in relationSet) {
          _collapsedRelationGroups.add(_relationGroupKey(related.id, relation));
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('加载下一级关联失败')));
    } finally {
      if (mounted) {
        setState(() => _expandingRelatedNodes.remove(related.id));
      }
    }
  }

  String _relationGroupKey(int parentId, String relation) {
    return '$parentId::$relation';
  }

  void _toggleRelationGroup(String groupKey) {
    setState(() {
      if (_collapsedRelationGroups.contains(groupKey)) {
        _collapsedRelationGroups.remove(groupKey);
      } else {
        _collapsedRelationGroups.add(groupKey);
      }
    });
  }

  Widget _buildMindMapNode(_MindMapNode node) {
    final colorScheme = Theme.of(context).colorScheme;
    if (node.kind == _MindMapNodeKind.center) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.primary.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _subject?.displayName ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '关联 ${_relatedSubjects.length}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onPrimaryContainer.withOpacity(0.85),
              ),
            ),
          ],
        ),
      );
    }

    if (node.kind == _MindMapNodeKind.relation) {
      final hasToggle = node.relationGroupKey != null;
      final isOuterLeft = node.side == _MindMapSide.left;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.secondary.withOpacity(0.28)),
        ),
        child: Row(
          children: [
            if (hasToggle && isOuterLeft) ...[
              _buildMindMapExpandControl(
                isExpanding: false,
                isExpanded: node.relationGroupExpanded,
                canExpand: true,
                onTap: () => _toggleRelationGroup(node.relationGroupKey!),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                node.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            if (hasToggle && !isOuterLeft) ...[
              const SizedBox(width: 4),
              _buildMindMapExpandControl(
                isExpanding: false,
                isExpanded: node.relationGroupExpanded,
                canExpand: true,
                onTap: () => _toggleRelationGroup(node.relationGroupKey!),
              ),
            ],
          ],
        ),
      );
    }

    final related = node.subject!;
    final isExpandableNode =
        node.kind == _MindMapNodeKind.subject ||
        node.kind == _MindMapNodeKind.childSubject;
    final isChildNode = node.kind == _MindMapNodeKind.childSubject;
    final isOuterLeft = node.side == _MindMapSide.left;
    final isExpanded = _expandedRelatedNodes.contains(related.id);
    final isExpanding = _expandingRelatedNodes.contains(related.id);
    final cachedChildren = _expandedRelatedChildren[related.id];
    final hasKnownChildren = cachedChildren?.isNotEmpty == true;
    final knownNoChildren = cachedChildren != null && cachedChildren.isEmpty;
    final showExpandControl = !knownNoChildren || isExpanded;
    final canExpandOrCollapse =
        isExpanded || cachedChildren == null || hasKnownChildren;
    final thumbWidth = isChildNode ? 26.0 : 34.0;
    final thumbHeight = isChildNode ? 36.0 : 46.0;
    final titleStyle = isChildNode
        ? Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)
        : Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600);
    final imageUrl = related.images['small'] ?? related.images['grid'] ?? '';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openSubjectPage(related.id),
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: isChildNode ? 4 : 6,
          ),
          child: Row(
            children: [
              if (isExpandableNode && isOuterLeft && showExpandControl) ...[
                _buildMindMapExpandControl(
                  isExpanding: isExpanding,
                  isExpanded: isExpanded,
                  canExpand: canExpandOrCollapse,
                  onTap: () => _toggleRelatedNodeExpansion(related),
                ),
                const SizedBox(width: 4),
              ],
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: thumbWidth,
                        height: thumbHeight,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: thumbWidth,
                          height: thumbHeight,
                          color: colorScheme.surfaceContainerHighest,
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: thumbWidth,
                          height: thumbHeight,
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(
                            Icons.image_not_supported,
                            size: 16,
                          ),
                        ),
                      )
                    : Container(
                        width: thumbWidth,
                        height: thumbHeight,
                        color: colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.image, size: 16),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      related.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getSubjectTypeLabel(related.type),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isExpandableNode && !isOuterLeft && showExpandControl) ...[
                const SizedBox(width: 4),
                _buildMindMapExpandControl(
                  isExpanding: isExpanding,
                  isExpanded: isExpanded,
                  canExpand: canExpandOrCollapse,
                  onTap: () => _toggleRelatedNodeExpansion(related),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMindMapExpandControl({
    required bool isExpanding,
    required bool isExpanded,
    required bool canExpand,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canExpand ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: isExpanding
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                )
              : Text(
                  isExpanded ? '-' : '+',
                  style: TextStyle(
                    color: canExpand
                        ? colorScheme.primary
                        : colorScheme.outline,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
        ),
      ),
    );
  }

  _MindMapLayout _buildMindMapLayout() {
    final grouped = <String, List<RelatedSubject>>{};
    for (final related in _relatedSubjects) {
      final relation = related.relation.isNotEmpty ? related.relation : '其他';
      grouped.putIfAbsent(relation, () => []).add(related);
    }

    final entries = grouped.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final left = <MapEntry<String, List<RelatedSubject>>>[];
    final right = <MapEntry<String, List<RelatedSubject>>>[];
    var leftWeight = 0;
    var rightWeight = 0;
    for (final entry in entries) {
      final weight = math.max(1, entry.value.length);
      if (leftWeight <= rightWeight) {
        left.add(entry);
        leftWeight += weight;
      } else {
        right.add(entry);
        rightWeight += weight;
      }
    }

    const padding = 32.0;
    const centerW = 220.0;
    const centerH = 72.0;
    const relationW = 120.0;
    const relationH = 40.0;
    const subjectW = 220.0;
    const subjectH = 66.0;
    const outerSubjectW = 204.0;
    const outerSubjectH = 52.0;
    const subjectToRelationGap = 54.0;
    const relationToSubjectGap = 56.0;
    const subtreeRowGap = 8.0;
    const subtreeGroupGap = 16.0;
    const rowGap = 12.0;
    const groupGap = 24.0;
    const relationToCenterGap = 90.0;
    const topRelationToSubjectGap = 84.0;

    Size nodeSizeForDepth(int depth) {
      if (depth <= 1) {
        return const Size(subjectW, subjectH);
      }
      return const Size(outerSubjectW, outerSubjectH);
    }

    List<MapEntry<String, List<RelatedSubject>>> groupedChildrenFor(
      RelatedSubject subject,
    ) {
      if (!_expandedRelatedNodes.contains(subject.id)) {
        return const [];
      }
      final children =
          _expandedRelatedChildren[subject.id] ?? const <RelatedSubject>[];
      if (children.isEmpty) {
        return const [];
      }
      final map = <String, List<RelatedSubject>>{};
      for (final child in children) {
        final relation = child.relation.isNotEmpty ? child.relation : '其他';
        map.putIfAbsent(relation, () => []).add(child);
      }
      final groups = map.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return groups;
    }

    double subtreeHeightFor(
      RelatedSubject subject, {
      required int depth,
      required Set<int> visited,
    }) {
      final nodeH = nodeSizeForDepth(depth).height;
      if (visited.contains(subject.id)) {
        return nodeH;
      }
      final nextVisited = {...visited, subject.id};
      final groups = groupedChildrenFor(subject);
      if (groups.isEmpty) {
        return nodeH;
      }

      double groupsTotalH = 0;
      for (var g = 0; g < groups.length; g++) {
        final relation = groups[g].key;
        final groupKey = _relationGroupKey(subject.id, relation);
        final collapsed = _collapsedRelationGroups.contains(groupKey);
        if (collapsed) {
          groupsTotalH += relationH;
          if (g != groups.length - 1) {
            groupsTotalH += subtreeGroupGap;
          }
          continue;
        }
        final children = groups[g].value;
        double childStackH = 0;
        for (var i = 0; i < children.length; i++) {
          childStackH += subtreeHeightFor(
            children[i],
            depth: depth + 1,
            visited: nextVisited,
          );
          if (i != children.length - 1) {
            childStackH += subtreeRowGap;
          }
        }
        groupsTotalH += math.max(relationH, childStackH);
        if (g != groups.length - 1) {
          groupsTotalH += subtreeGroupGap;
        }
      }
      return math.max(nodeH, groupsTotalH);
    }

    double outwardWidthFor(
      RelatedSubject subject, {
      required int depth,
      required Set<int> visited,
    }) {
      if (visited.contains(subject.id)) {
        return 0;
      }
      final nextVisited = {...visited, subject.id};
      final groups = groupedChildrenFor(subject);
      if (groups.isEmpty) {
        return 0;
      }

      double maxGroupWidth = 0;
      for (final group in groups) {
        final groupKey = _relationGroupKey(subject.id, group.key);
        final collapsed = _collapsedRelationGroups.contains(groupKey);
        if (collapsed) {
          final groupWidth = subjectToRelationGap + relationW;
          if (groupWidth > maxGroupWidth) {
            maxGroupWidth = groupWidth;
          }
          continue;
        }
        double maxChildWidth = 0;
        for (final child in group.value) {
          final childNodeW = nodeSizeForDepth(depth + 1).width;
          final childWidth =
              childNodeW +
              outwardWidthFor(child, depth: depth + 1, visited: nextVisited);
          if (childWidth > maxChildWidth) {
            maxChildWidth = childWidth;
          }
        }
        final groupWidth =
            subjectToRelationGap +
            relationW +
            relationToSubjectGap +
            maxChildWidth;
        if (groupWidth > maxGroupWidth) {
          maxGroupWidth = groupWidth;
        }
      }
      return maxGroupWidth;
    }

    double groupHeight(List<RelatedSubject> subjects) {
      if (subjects.isEmpty) {
        return 0;
      }
      var total = 0.0;
      for (var i = 0; i < subjects.length; i++) {
        total += subtreeHeightFor(subjects[i], depth: 1, visited: <int>{});
        if (i != subjects.length - 1) {
          total += rowGap;
        }
      }
      return total;
    }

    double sideContentHeight(
      List<MapEntry<String, List<RelatedSubject>>> side,
    ) {
      if (side.isEmpty) {
        return centerH;
      }
      var total = 0.0;
      for (var i = 0; i < side.length; i++) {
        final groupKey = _relationGroupKey(widget.subjectId, side[i].key);
        final collapsed = _collapsedRelationGroups.contains(groupKey);
        total += collapsed ? relationH : groupHeight(side[i].value);
        if (i != side.length - 1) {
          total += groupGap;
        }
      }
      return total;
    }

    final contentH = math.max(
      centerH,
      math.max(sideContentHeight(left), sideContentHeight(right)),
    );
    final canvasHeight = contentH + padding * 2;

    double maxLeftOutwardW = 0;
    for (final entry in left) {
      for (final subject in entry.value) {
        final w = outwardWidthFor(subject, depth: 1, visited: <int>{});
        if (w > maxLeftOutwardW) {
          maxLeftOutwardW = w;
        }
      }
    }
    double maxRightOutwardW = 0;
    for (final entry in right) {
      for (final subject in entry.value) {
        final w = outwardWidthFor(subject, depth: 1, visited: <int>{});
        if (w > maxRightOutwardW) {
          maxRightOutwardW = w;
        }
      }
    }

    final leftOutwardSpace = math.max(outerSubjectW / 2, maxLeftOutwardW);
    final rightOutwardSpace = math.max(outerSubjectW / 2, maxRightOutwardW);

    final leftMostX = padding + leftOutwardSpace;
    final leftSubjectX = leftMostX + subjectW / 2;
    final leftRelationX =
        leftSubjectX + subjectW / 2 + topRelationToSubjectGap + relationW / 2;
    final centerX =
        leftRelationX + relationW / 2 + relationToCenterGap + centerW / 2;
    final rightRelationX =
        centerX + centerW / 2 + relationToCenterGap + relationW / 2;
    final rightSubjectX =
        rightRelationX + relationW / 2 + topRelationToSubjectGap + subjectW / 2;
    final rightMostX = rightSubjectX + subjectW / 2 + rightOutwardSpace;
    final canvasWidth = rightMostX + padding;
    final centerY = canvasHeight / 2;

    final nodes = <_MindMapNode>[];
    final edges = <_MindMapEdge>[];

    final centerNode = _MindMapNode(
      kind: _MindMapNodeKind.center,
      label: _subject?.displayName ?? '',
      rect: Rect.fromCenter(
        center: Offset(centerX, centerY),
        width: centerW,
        height: centerH,
      ),
    );
    nodes.add(centerNode);

    void placeExpandedSubtree(
      RelatedSubject parentSubject,
      Rect parentRect, {
      required int depth,
      required bool sideLeft,
      required double top,
      required Set<int> visited,
    }) {
      if (visited.contains(parentSubject.id)) {
        return;
      }
      final nextVisited = {...visited, parentSubject.id};
      final groups = groupedChildrenFor(parentSubject);
      if (groups.isEmpty) {
        return;
      }

      final parentNodeSize = nodeSizeForDepth(depth);
      final childNodeSize = nodeSizeForDepth(depth + 1);
      final parentTreeH = subtreeHeightFor(
        parentSubject,
        depth: depth,
        visited: visited,
      );

      final groupHeights = <double>[];
      var groupsContentH = 0.0;
      for (var g = 0; g < groups.length; g++) {
        final relation = groups[g].key;
        final groupKey = _relationGroupKey(parentSubject.id, relation);
        final collapsed = _collapsedRelationGroups.contains(groupKey);
        if (collapsed) {
          groupHeights.add(relationH);
          groupsContentH += relationH;
          if (g != groups.length - 1) {
            groupsContentH += subtreeGroupGap;
          }
          continue;
        }
        final children = groups[g].value;
        double childStackH = 0;
        for (var i = 0; i < children.length; i++) {
          childStackH += subtreeHeightFor(
            children[i],
            depth: depth + 1,
            visited: nextVisited,
          );
          if (i != children.length - 1) {
            childStackH += subtreeRowGap;
          }
        }
        final h = math.max(relationH, childStackH);
        groupHeights.add(h);
        groupsContentH += h;
        if (g != groups.length - 1) {
          groupsContentH += subtreeGroupGap;
        }
      }

      var y = top + (parentTreeH - groupsContentH) / 2;

      for (var g = 0; g < groups.length; g++) {
        final relation = groups[g].key;
        final children = groups[g].value;
        final groupKey = _relationGroupKey(parentSubject.id, relation);
        final collapsed = _collapsedRelationGroups.contains(groupKey);
        final groupH = groupHeights[g];
        final relationY = y + groupH / 2;
        final direction = sideLeft ? -1.0 : 1.0;
        final relationX =
            parentRect.center.dx +
            direction *
                (parentNodeSize.width / 2 +
                    subjectToRelationGap +
                    relationW / 2);
        final relationRect = Rect.fromCenter(
          center: Offset(relationX, relationY),
          width: relationW,
          height: relationH,
        );
        final relationNode = _MindMapNode(
          kind: _MindMapNodeKind.relation,
          label: relation,
          rect: relationRect,
          side: sideLeft ? _MindMapSide.left : _MindMapSide.right,
          relationGroupKey: groupKey,
          relationGroupExpanded: !collapsed,
        );
        nodes.add(relationNode);
        edges.add(
          _MindMapEdge(
            fromRect: parentRect,
            toRect: relationRect,
            highlight: false,
          ),
        );

        if (collapsed) {
          y += groupH;
          if (g != groups.length - 1) {
            y += subtreeGroupGap;
          }
          continue;
        }

        double childStackH = 0;
        final childHeights = <double>[];
        for (var i = 0; i < children.length; i++) {
          final h = subtreeHeightFor(
            children[i],
            depth: depth + 1,
            visited: nextVisited,
          );
          childHeights.add(h);
          childStackH += h;
          if (i != children.length - 1) {
            childStackH += subtreeRowGap;
          }
        }
        var childTop = y + (groupH - childStackH) / 2;

        for (var i = 0; i < children.length; i++) {
          final child = children[i];
          final childBlockH = childHeights[i];
          final childNodeY =
              childTop + (childBlockH - childNodeSize.height) / 2;
          final childX =
              relationRect.center.dx +
              direction *
                  (relationW / 2 +
                      relationToSubjectGap +
                      childNodeSize.width / 2);
          final childRect = Rect.fromLTWH(
            childX - childNodeSize.width / 2,
            childNodeY,
            childNodeSize.width,
            childNodeSize.height,
          );
          final childNode = _MindMapNode(
            kind: _MindMapNodeKind.childSubject,
            label: child.displayName,
            subject: child,
            rect: childRect,
            side: sideLeft ? _MindMapSide.left : _MindMapSide.right,
            depth: depth + 1,
          );
          nodes.add(childNode);
          edges.add(
            _MindMapEdge(
              fromRect: relationRect,
              toRect: childRect,
              highlight: false,
            ),
          );

          placeExpandedSubtree(
            child,
            childRect,
            depth: depth + 1,
            sideLeft: sideLeft,
            top: childTop,
            visited: nextVisited,
          );
          childTop += childBlockH;
          if (i != children.length - 1) {
            childTop += subtreeRowGap;
          }
        }

        y += groupH;
        if (g != groups.length - 1) {
          y += subtreeGroupGap;
        }
      }
    }

    void placeSide(
      List<MapEntry<String, List<RelatedSubject>>> sideEntries,
      bool isLeft,
    ) {
      if (sideEntries.isEmpty) return;
      final totalH = sideContentHeight(sideEntries);
      var cursorY = (canvasHeight - totalH) / 2;
      final relationX = isLeft ? leftRelationX : rightRelationX;
      final subjectX = isLeft ? leftSubjectX : rightSubjectX;

      for (final entry in sideEntries) {
        final subjects = entry.value;
        final groupKey = _relationGroupKey(widget.subjectId, entry.key);
        final collapsed = _collapsedRelationGroups.contains(groupKey);
        final blockH = collapsed ? relationH : groupHeight(subjects);
        final relationY = cursorY + blockH / 2;

        final relationNode = _MindMapNode(
          kind: _MindMapNodeKind.relation,
          label: entry.key,
          rect: Rect.fromCenter(
            center: Offset(relationX, relationY),
            width: relationW,
            height: relationH,
          ),
          side: isLeft ? _MindMapSide.left : _MindMapSide.right,
          relationGroupKey: groupKey,
          relationGroupExpanded: !collapsed,
        );
        nodes.add(relationNode);
        edges.add(
          _MindMapEdge(
            fromRect: centerNode.rect,
            toRect: relationNode.rect,
            highlight: true,
          ),
        );

        if (!collapsed) {
          for (var i = 0; i < subjects.length; i++) {
            final subject = subjects[i];
            final blockTop = cursorY;
            final subjectTreeH = subtreeHeightFor(
              subject,
              depth: 1,
              visited: <int>{},
            );
            final subjectTop = blockTop + (subjectTreeH - subjectH) / 2;
            final subjectNode = _MindMapNode(
              kind: _MindMapNodeKind.subject,
              label: subject.displayName,
              subject: subject,
              rect: Rect.fromLTWH(
                subjectX - subjectW / 2,
                subjectTop,
                subjectW,
                subjectH,
              ),
              side: isLeft ? _MindMapSide.left : _MindMapSide.right,
              depth: 1,
            );
            nodes.add(subjectNode);
            edges.add(
              _MindMapEdge(
                fromRect: relationNode.rect,
                toRect: subjectNode.rect,
                highlight: false,
              ),
            );

            placeExpandedSubtree(
              subject,
              subjectNode.rect,
              depth: 1,
              sideLeft: isLeft,
              top: blockTop,
              visited: <int>{},
            );

            cursorY += subjectTreeH;
            if (i != subjects.length - 1) {
              cursorY += rowGap;
            }
          }
        } else {
          cursorY += blockH;
        }

        cursorY += groupGap;
      }
    }

    placeSide(left, true);
    placeSide(right, false);

    return _MindMapLayout(
      width: canvasWidth,
      height: canvasHeight,
      nodes: nodes,
      edges: edges,
    );
  }

  void _openSubjectPage(int subjectId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SubjectPage(subjectId: subjectId)),
    );
  }

  void _showFullTitleDialog() {
    if (_subject == null) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('完整标题'),
          content: SelectableText(_subject!.displayName),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeaderCard(ColorScheme colorScheme, {bool isLandscape = false}) {
    final coverWidth = isLandscape ? 84 : 84;
    final coverHeight = isLandscape ? 122 : 122;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_subject!.images?.medium.isNotEmpty ?? false)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: _subject!.images!.medium,
                  width: coverWidth.toDouble(),
                  height: coverHeight.toDouble(),
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    width: coverWidth.toDouble(),
                    height: coverHeight.toDouble(),
                    color: Colors.grey[300],
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: coverWidth.toDouble(),
                    height: coverHeight.toDouble(),
                    color: Colors.grey[300],
                    child: const Icon(Icons.image_not_supported),
                  ),
                ),
              )
            else
              Container(
                width: coverWidth.toDouble(),
                height: coverHeight.toDouble(),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.image),
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _showFullTitleDialog,
                    behavior: HitTestBehavior.opaque,
                    //标题固定单行，避免头部卡片在窄宽度时被撑高。
                    child: ShortCopyableText(
                      _subject!.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_subject!.name != _subject!.nameCn &&
                      _subject!.name.isNotEmpty)
                    ShortCopyableText(
                      _subject!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[600], fontSize: 11),
                    ),
                  if (isLandscape)
                    const SizedBox(height: 4)
                  else
                    const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.yellow, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        _subject!.score > 0
                            ? _subject!.score.toStringAsFixed(1)
                            : 'N/A',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      if (_subject!.rank > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '#${_subject!.rank}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (isLandscape)
                    const SizedBox(height: 4)
                  else
                    const SizedBox(height: 8),
                  Text(
                    '标记数${_subject!.collectionTotal}',
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  ),
                  if (isLandscape)
                    const SizedBox(height: 4)
                  else
                    const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[400]!),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          _getSubjectTypeLabel(_subject!.type),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const Spacer(),
                      SubjectActionButtons(
                        subject: _subject!,
                        existingCollection: _userCollection,
                        onCollectionChanged: _loadUserCollection,
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

  Widget _buildCommentsTab() {
    if (_commentsLoading && _comments.isEmpty) {
      return _buildCommentsSkeletonList();
    }

    if (_comments.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadAllData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 100, horizontal: 16),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.message_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '暂无吐槽',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '这部作品还没有吐槽',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: _comments.length,
        itemBuilder: (context, index) {
          final comment = _comments[index];
          return _buildCommentItem(comment, colorScheme);
        },
      ),
    );
  }

  Widget _buildCommentItem(Comment comment, ColorScheme colorScheme) {
    final userId = comment.user['id'] as int? ?? 0;
    final isValidUser = userId > 0;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: !isValidUser
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => OtherUserProfilePage(
                              userId: userId,
                              displayName: comment.userName,
                            ),
                          ),
                        ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: comment.userAvatar.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: comment.userAvatar,
                              fit: BoxFit.cover,
                              placeholder: (context, url) =>
                                  Container(color: Colors.grey[300]),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey[300],
                                child: const Icon(Icons.person, size: 20),
                              ),
                            )
                          : Container(
                              color: Colors.grey[300],
                              child: const Icon(Icons.person, size: 20),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: !isValidUser
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => OtherUserProfilePage(
                                    userId: userId,
                                    displayName: comment.userName,
                                  ),
                                ),
                              ),
                        child: Text(
                          comment.userName,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (comment.rating > 0)
                            Row(
                              children: [
                                ...List.generate(5, (i) {
                                  return Icon(
                                    i < comment.rating ~/ 2
                                        ? Icons.star
                                        : Icons.star_border,
                                    color: Colors.amber,
                                    size: 12,
                                  );
                                }),
                                const SizedBox(width: 4),
                              ],
                            ),
                          if (comment.spoiler == 1)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red[100],
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                '剧透',
                                style: TextStyle(
                                  color: Colors.red[700],
                                  fontSize: 10,
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
            const SizedBox(height: 12),
            BangumiContentView(
              text: comment.content,
              html: comment.contentHtml,
              style: TextStyle(color: Colors.grey[700], fontSize: 14),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatTime(comment.updatedAt),
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
                if (comment.replies > 0)
                  Text(
                    '${comment.replies} 条回复',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}小时前';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      return '${dateTime.month}月${dateTime.day}日';
    }
  }

  String _getSubjectTypeLabel(int type) {
    switch (type) {
      case BgmConst.subjectBook:
        return '书籍';
      case BgmConst.subjectAnime:
        return '动画';
      case BgmConst.subjectMusic:
        return '音乐';
      case BgmConst.subjectGame:
        return '游戏';
      case BgmConst.subjectReal:
        return '三次元';
      default:
        return '未知';
    }
  }
}

enum _RelatedViewMode { list, mindMap }

enum _MindMapSide { none, left, right }

enum _MindMapNodeKind { center, relation, subject, childSubject }

class _MindMapNode {
  final _MindMapNodeKind kind;
  final String label;
  final Rect rect;
  final RelatedSubject? subject;
  final _MindMapSide side;
  final int depth;
  final String? relationGroupKey;
  final bool relationGroupExpanded;

  const _MindMapNode({
    required this.kind,
    required this.label,
    required this.rect,
    this.subject,
    this.side = _MindMapSide.none,
    this.depth = 0,
    this.relationGroupKey,
    this.relationGroupExpanded = true,
  });
}

class _MindMapEdge {
  final Rect fromRect;
  final Rect toRect;
  final bool highlight;

  const _MindMapEdge({
    required this.fromRect,
    required this.toRect,
    required this.highlight,
  });
}

class _MindMapLayout {
  final double width;
  final double height;
  final List<_MindMapNode> nodes;
  final List<_MindMapEdge> edges;

  const _MindMapLayout({
    required this.width,
    required this.height,
    required this.nodes,
    required this.edges,
  });
}

class _MindMapLinePainter extends CustomPainter {
  final List<_MindMapEdge> edges;
  final Color lineColor;
  final Color highlightColor;

  const _MindMapLinePainter({
    required this.edges,
    required this.lineColor,
    required this.highlightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final normalPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final highlightPaint = Paint()
      ..color = highlightColor
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    for (final edge in edges) {
      late final Offset start;
      late final Offset end;
      late final Path path;
      final startOnRight = edge.fromRect.center.dx <= edge.toRect.center.dx;
      start = Offset(
        startOnRight ? edge.fromRect.right : edge.fromRect.left,
        edge.fromRect.center.dy,
      );
      end = Offset(
        startOnRight ? edge.toRect.left : edge.toRect.right,
        edge.toRect.center.dy,
      );
      final midX = (start.dx + end.dx) / 2;
      path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(midX, start.dy, midX, end.dy, end.dx, end.dy);
      canvas.drawPath(path, edge.highlight ? highlightPaint : normalPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MindMapLinePainter oldDelegate) {
    return oldDelegate.edges != edges ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.highlightColor != highlightColor;
  }
}

class _SubjectTabItem {
  final String label;
  final IconData icon;

  const _SubjectTabItem({required this.label, required this.icon});
}

class _TabBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  const _TabBarHeaderDelegate({required this.child});

  @override
  double get minExtent => kTextTabBarHeight;

  @override
  double get maxExtent => kTextTabBarHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _TabBarHeaderDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
}
