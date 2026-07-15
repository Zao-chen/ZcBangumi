import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/character.dart';
import '../models/collection.dart';
import '../models/comment.dart';
import '../pages/profile_page.dart';
import '../models/episode.dart';
import '../models/person.dart';
import '../models/subject.dart';
import '../models/subject_tab_config.dart';
import '../providers/app_state_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/connectivity_provider.dart';
import '../services/api_client.dart';
import '../services/link_navigator.dart';
import '../services/storage_service.dart';
import '../widgets/progress_grid.dart';
import '../widgets/subject_action_buttons.dart';
import '../widgets/bangumi_content_view.dart';
import '../widgets/copyable_text.dart';
import '../widgets/copyable_chip.dart';
import '../widgets/mono_detail_scaffold.dart';
import '../widgets/mono_entity_widgets.dart';
import '../widgets/mono_relation_graph.dart';
import 'anime_tag_page.dart';
import 'character_page.dart';
import 'person_page.dart';
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
  Subject? _subject;
  UserCollection? _userCollection;
  List<Character> _characters = [];
  List<RelatedPerson> _persons = [];
  List<RelatedSubject> _relatedSubjects = [];
  List<UserEpisodeCollection> _episodes = [];
  List<Comment> _comments = [];
  bool _loading = true;
  bool _charactersLoading = false;
  bool _personsLoading = false;
  bool _relatedLoading = false;
  bool _commentsLoading = false;
  bool _episodesLoading = false;
  bool _subjectDetailLoading = false;
  bool _showCollapsedTitle = false;
  int _selectedTabIndex = 0;
  List<String> _visibleTabIds = List<String>.from(
    SubjectTabConfig.defaultOrder,
  );
  MonoRelationViewMode _charactersViewMode = MonoRelationViewMode.list;
  MonoRelationViewMode _personsViewMode = MonoRelationViewMode.list;
  MonoRelationViewMode _relatedViewMode = MonoRelationViewMode.list;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _visibleTabIds.length, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _nestedScrollController.addListener(_handleHeaderCollapse);
    _restoreRelationViewModes();
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

  void _restoreRelationViewModes() {
    final storage = context.read<StorageService>();
    _charactersViewMode = _readRelationViewMode(
      storage,
      _charactersViewModeCacheName,
    );
    _personsViewMode = _readRelationViewMode(
      storage,
      _personsViewModeCacheName,
    );
    _relatedViewMode = _readRelationViewMode(
      storage,
      _relatedViewModeCacheName,
    );
  }

  MonoRelationViewMode _readRelationViewMode(
    StorageService storage,
    String cacheName,
  ) {
    final cached = storage.getCache(cacheName);
    return cached == 'graph' || cached == 'mind_map'
        ? MonoRelationViewMode.graph
        : MonoRelationViewMode.list;
  }

  void _setRelationViewMode(
    MonoRelationViewMode mode, {
    required String cacheName,
    required ValueSetter<MonoRelationViewMode> update,
  }) {
    setState(() => update(mode));
    context.read<StorageService>().setCache(
      cacheName,
      mode == MonoRelationViewMode.graph ? 'graph' : 'list',
    );
  }

  String get _cacheName => 'subject_${widget.subjectId}';
  String get _charsCacheName => 'subject_chars_${widget.subjectId}';
  String get _personsCacheName => 'subject_persons_${widget.subjectId}';
  String get _relatedCacheName => 'subject_related_${widget.subjectId}';
  String get _episodesCacheName => 'subject_episodes_${widget.subjectId}';
  String get _commentsCacheName => 'subject_comments_${widget.subjectId}';
  String get _userCollectionCacheName =>
      'subject_user_collection_${widget.subjectId}';
  String get _charactersViewModeCacheName => 'subject_characters_view_mode';
  String get _personsViewModeCacheName => 'subject_persons_view_mode';
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
    final connectivity = context.read<ConnectivityProvider>();

    _subject ??= _readSubjectFromCache(storage);

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

    if (_persons.isEmpty) {
      final personsCached = storage.getCache(_personsCacheName);
      if (personsCached is List) {
        try {
          _persons = personsCached
              .whereType<Map<String, dynamic>>()
              .map(RelatedPerson.fromJson)
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
      storage.touchCache(_cacheName);
    }

    setState(() {
      _loading = _subject == null;
      _charactersLoading = _characters.isEmpty;
      _personsLoading = _persons.isEmpty;
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
        connectivity.reportNetworkSuccess();
      }

      final charsFuture = api.getSubjectCharacters(widget.subjectId);
      final personsFuture = api.getSubjectPersons(widget.subjectId);
      final relatedFuture = api.getSubjectRelations(widget.subjectId);
      final commentsFuture = api.getSubjectComments(
        subjectId: widget.subjectId,
      );

      Future<Object?> tolerateFailure(Future<Object?> request) async {
        try {
          return await request;
        } catch (_) {
          return null;
        }
      }

      final results = await Future.wait<Object?>([
        tolerateFailure(charsFuture),
        tolerateFailure(personsFuture),
        tolerateFailure(relatedFuture),
        tolerateFailure(commentsFuture),
      ]);
      if (!mounted) return;

      setState(() {
        _characters = results[0] is List<Character>
            ? results[0] as List<Character>
            : _characters;
        _persons = results[1] is List<RelatedPerson>
            ? results[1] as List<RelatedPerson>
            : _persons;
        _relatedSubjects = results[2] is List<RelatedSubject>
            ? results[2] as List<RelatedSubject>
            : _relatedSubjects;
        if (results[3] is PagedResult<Comment>) {
          final commentsResult = results[3] as PagedResult<Comment>;
          _comments = commentsResult.data;
        }
        _charactersLoading = false;
        _personsLoading = false;
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
        _personsCacheName,
        _persons.map((person) => person.toJson()).toList(),
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
      connectivity.reportNetworkFailure(e);
      if (_subject == null) {
        setState(() => _error = '加载失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _subjectDetailLoading = false;
          _charactersLoading = false;
          _personsLoading = false;
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
    final connectivity = context.read<ConnectivityProvider>();

    if (!authProvider.canUseAuthenticatedCache) {
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
      if (!mounted) return;

      setState(() {
        _episodes = result.data;
      });
      connectivity.reportNetworkSuccess();

      storage.setCache(
        _episodesCacheName,
        _episodes.map((e) => e.toJson()).toList(),
      );
    } catch (e) {
      connectivity.reportNetworkFailure(e);
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
    final connectivity = context.read<ConnectivityProvider>();
    final username = authProvider.username;

    if (!authProvider.canUseAuthenticatedCache || username == null) {
      return;
    }

    try {
      final collection = await api.getUserCollection(
        username: username,
        subjectId: widget.subjectId,
      );
      if (!mounted) return;
      if (mounted) {
        setState(() {
          _userCollection = collection;
        });
      }
      storage.setCache(_userCollectionCacheName, collection.toJson());
      connectivity.reportNetworkSuccess();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        if (mounted) {
          setState(() {
            _userCollection = null;
          });
        }
        storage.removeCache(_userCollectionCacheName);
      } else {
        connectivity.reportNetworkFailure(e);
      }
    } catch (e) {
      connectivity.reportNetworkFailure(e);
    }
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
      separatorBuilder: (_, _) => const SizedBox(height: 10),
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
            expandedHeight: MonoDetailScaffold.defaultExpandedHeight,
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

    final colorScheme = Theme.of(context).colorScheme;
    return MonoDetailScaffold(
      scrollController: _nestedScrollController,
      tabController: _tabController,
      tabs: _visibleTabItems
          .map((tab) => MonoDetailTab(label: tab.label, icon: tab.icon))
          .toList(),
      tabChildren: _visibleTabIds.map(_buildTabById).toList(),
      selectedTabIndex: _selectedTabIndex,
      showCollapsedTitle: _showCollapsedTitle,
      title: _subject!.displayName,
      onTitleTap: _showFullTitleDialog,
      header: _buildHeaderCard(colorScheme, isLandscape: isLandscape),
      actions: [
        IconButton(
          tooltip: '打开网页',
          onPressed: _openSubjectWebPage,
          icon: const Icon(Icons.open_in_new),
        ),
      ],
      nestedScrollPhysics: _shouldLockTabSwipeForMindMap
          ? const NeverScrollableScrollPhysics()
          : null,
      tabViewPhysics: _shouldLockTabSwipeForMindMap
          ? const NeverScrollableScrollPhysics()
          : null,
    );
  }

  Widget _buildTabById(String tabId) {
    switch (tabId) {
      case SubjectTabConfig.overviewId:
        return _buildOverviewTab();
      case SubjectTabConfig.charactersId:
        return _buildCharactersTab();
      case SubjectTabConfig.personsId:
        return _buildPersonsTab();
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
        child: Text('暂无可用于搜索的条目名', style: TextStyle(color: Colors.grey[600])),
      );
    }

    if (kIsWeb) {
      return _buildMoegirlWebOpenTab(uri);
    }

    return EmbeddedWebPageView(initialUri: uri);
  }

  Widget _buildMoegirlWebOpenTab(Uri uri) {
    final colorScheme = Theme.of(context).colorScheme;
    final subjectName = _subject?.displayName ?? '';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.travel_explore_rounded,
                    size: 40,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '萌娘百科',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subjectName.isEmpty ? '在新标签页中查看相关页面' : subjectName,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => _openMoegirlInBrowser(uri),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('在萌娘百科打开'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openMoegirlInBrowser(Uri uri) async {
    final ok = await LinkNavigator.openBrowser(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('打开萌娘百科失败')));
    }
  }

  bool get _shouldLockTabSwipeForMindMap => switch (_selectedTabId) {
    SubjectTabConfig.charactersId =>
      _charactersViewMode == MonoRelationViewMode.graph,
    SubjectTabConfig.personsId =>
      _personsViewMode == MonoRelationViewMode.graph,
    SubjectTabConfig.relatedId =>
      _relatedViewMode == MonoRelationViewMode.graph,
    _ => false,
  };

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
                              child: MonoEntityOverviewSection(
                                title: '简介',
                                padding: EdgeInsets.zero,
                                child: CopyableText(
                                  summaryText,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                  enableLongPressCopy: false,
                                ),
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
              MonoEntityOverviewSection(
                title: '简介',
                child: CopyableText(
                  summaryText,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  enableLongPressCopy: false,
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
              _buildOverviewTagsSection(
                colorScheme,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              _buildOverviewInfoboxSection(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
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
    return MonoEntityOverviewSection(
      title: '标签',
      padding: padding,
      child: _subject!.tags.isEmpty
          ? Text('暂无标签', style: TextStyle(color: Colors.grey[600]))
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _subject!.tags.map((tag) {
                return CopyableChip(
                  label: tag,
                  labelStyle: const TextStyle(fontSize: 12),
                  backgroundColor: colorScheme.surfaceContainerHigh,
                  onTap: () => _openAnimeTagPage(tag),
                );
              }).toList(),
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
    return MonoEntityOverviewSection(
      title: '详情',
      padding: padding,
      child: _subject!.infobox.isEmpty
          ? Text('暂无详情', style: TextStyle(color: Colors.grey[600]))
          : MonoEntityInfoTable(info: _subject!.infobox),
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
      return const MonoEntitySkeletonList();
    }

    if (_characters.isEmpty) {
      return MonoEntityEmptyState(
        message: '暂无角色信息',
        icon: Icons.person_outline_rounded,
        onRefresh: _loadAllData,
      );
    }

    return MonoRelationViewSwitcher(
      mode: _charactersViewMode,
      onModeChanged: (mode) => _setRelationViewMode(
        mode,
        cacheName: _charactersViewModeCacheName,
        update: (value) => _charactersViewMode = value,
      ),
      itemCount: _characters.length,
      listView: RefreshIndicator(
        onRefresh: _loadAllData,
        child: _buildCharactersList(),
      ),
      graphView: MonoRelationGraph(
        graphId: 'subject:${widget.subjectId}:characters',
        centerTitle: _subject!.displayName,
        centerSubtitle: '角色 ${_characters.length}',
        centerImageUrl: _subject!.images?.medium ?? '',
        centerPlaceholderIcon: Icons.movie_outlined,
        nodes: _characters.map(_buildCharacterGraphNode).toList(),
      ),
    );
  }

  Widget _buildCharactersList() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _characters.length,
      itemBuilder: (context, index) {
        final character = _characters[index];
        final imageUrl = character.images.isNotEmpty
            ? character.images.first.medium
            : '';

        return MonoEntityListCard(
          key: ValueKey('subject_character_${character.id}'),
          imageUrl: imageUrl,
          placeholderIcon: Icons.person_outline_rounded,
          title: character.name,
          description: character.comment,
          chips: [
            if (character.relation.isNotEmpty)
              MonoEntityChip(
                character.relation,
                tone: MonoEntityChipTone.accent,
              ),
            if (character.type.isNotEmpty) MonoEntityChip(character.type),
          ],
          onTap: () => _openCharacterPage(character),
        );
      },
    );
  }

  MonoRelationGraphNode _buildCharacterGraphNode(Character character) {
    final imageUrl = character.images.isNotEmpty
        ? character.images.first.medium
        : '';
    return MonoRelationGraphNode(
      key: 'character:${character.id}',
      relation: character.relation.isEmpty ? '其他角色' : character.relation,
      title: character.name,
      subtitle: character.type,
      imageUrl: imageUrl,
      placeholderIcon: Icons.person_outline_rounded,
      onTap: () => _openCharacterPage(character),
      loadChildren: () => _loadCharacterGraphChildren(character),
    );
  }

  Future<List<MonoRelationGraphNode>> _loadCharacterGraphChildren(
    Character character,
  ) async {
    const graphLimit = 48;
    final subjects = await context.read<ApiClient>().getCharacterSubjects(
      character.id,
    );
    final visible = subjects.take(graphLimit).map((subject) {
      final relation = subject.staff.trim();
      return MonoRelationGraphNode(
        key: 'subject:${subject.id}',
        relation: relation.isEmpty ? '出演作品' : '出演 · $relation',
        title: subject.displayName,
        subtitle: subject.eps,
        imageUrl: subject.image,
        placeholderIcon: Icons.movie_outlined,
        onTap: () => _openSubjectPage(subject.id),
      );
    }).toList();
    if (subjects.length > graphLimit) {
      visible.add(
        MonoRelationGraphNode(
          key: 'character:${character.id}:more',
          relation: '更多',
          title: '另有 ${subjects.length - graphLimit} 项出演作品',
          subtitle: '进入角色详情查看完整列表',
          placeholderIcon: Icons.more_horiz_rounded,
          onTap: () => _openCharacterPage(character),
        ),
      );
    }
    return visible;
  }

  void _openCharacterPage(Character character) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CharacterPage(character: character)),
    );
  }

  Widget _buildPersonsTab() {
    if (_personsLoading && _persons.isEmpty) {
      return const MonoEntitySkeletonList();
    }

    if (_persons.isEmpty) {
      return MonoEntityEmptyState(
        message: '暂无制作人员信息',
        icon: Icons.badge_outlined,
        onRefresh: _loadAllData,
      );
    }

    return MonoRelationViewSwitcher(
      mode: _personsViewMode,
      onModeChanged: (mode) => _setRelationViewMode(
        mode,
        cacheName: _personsViewModeCacheName,
        update: (value) => _personsViewMode = value,
      ),
      itemCount: _persons.length,
      listView: RefreshIndicator(
        onRefresh: _loadAllData,
        child: _buildPersonsList(),
      ),
      graphView: MonoRelationGraph(
        graphId: 'subject:${widget.subjectId}:persons',
        centerTitle: _subject!.displayName,
        centerSubtitle: '制作 ${_persons.length}',
        centerImageUrl: _subject!.images?.medium ?? '',
        centerPlaceholderIcon: Icons.movie_outlined,
        nodes: _persons.map(_buildPersonGraphNode).toList(),
      ),
    );
  }

  Widget _buildPersonsList() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _persons.length,
      itemBuilder: (context, index) {
        final person = _persons[index];
        final imageUrl = person.images?.bestSmall ?? '';
        return MonoEntityListCard(
          key: ValueKey('subject_person_${person.id}'),
          imageUrl: imageUrl,
          placeholderIcon: Icons.badge_outlined,
          title: person.name,
          description: person.eps.isEmpty ? '' : '参与章节：${person.eps}',
          chips: [
            if (person.relation.isNotEmpty)
              MonoEntityChip(person.relation, tone: MonoEntityChipTone.accent),
            ...person.careerLabels.take(3).map(MonoEntityChip.new),
          ],
          onTap: () => _openPersonPage(person),
        );
      },
    );
  }

  MonoRelationGraphNode _buildPersonGraphNode(RelatedPerson person) {
    return MonoRelationGraphNode(
      key: 'person:${person.id}',
      relation: person.relation.isEmpty ? '其他制作' : person.relation,
      title: person.name,
      subtitle: person.careerLabels.take(3).join('、'),
      imageUrl: person.images?.bestSmall ?? '',
      placeholderIcon: Icons.badge_outlined,
      onTap: () => _openPersonPage(person),
      loadChildren: () => _loadPersonGraphChildren(person),
    );
  }

  Future<List<MonoRelationGraphNode>> _loadPersonGraphChildren(
    RelatedPerson person,
  ) async {
    const branchLimit = 32;
    final api = context.read<ApiClient>();
    var subjects = <PersonSubject>[];
    var characters = <PersonCharacter>[];
    await Future.wait([
      () async {
        try {
          subjects = await api.getPersonSubjects(person.id);
        } catch (_) {}
      }(),
      () async {
        try {
          characters = await api.getPersonCharacters(person.id);
        } catch (_) {}
      }(),
    ]);

    final nodes = <MonoRelationGraphNode>[
      ...subjects.take(branchLimit).map((subject) {
        final staff = subject.staff.trim();
        return MonoRelationGraphNode(
          key: 'person:${person.id}:subject:${subject.id}',
          relation: staff.isEmpty ? '参与作品' : '作品 · $staff',
          title: subject.displayName,
          subtitle: subject.eps,
          imageUrl: subject.image,
          placeholderIcon: Icons.movie_outlined,
          onTap: () => _openSubjectPage(subject.id),
        );
      }),
      ...characters.take(branchLimit).map((character) {
        final staff = character.staff.trim();
        return MonoRelationGraphNode(
          key:
              'person:${person.id}:character:${character.id}:${character.subjectId}',
          relation: staff.isEmpty ? '关联角色' : '角色 · $staff',
          title: character.name,
          subtitle: character.displaySubjectName,
          imageUrl: character.images?.bestSmall ?? '',
          placeholderIcon: Icons.person_outline_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CharacterPage(characterId: character.id),
            ),
          ),
        );
      }),
    ];
    if (subjects.length > branchLimit) {
      nodes.add(
        MonoRelationGraphNode(
          key: 'person:${person.id}:more-subjects',
          relation: '更多作品',
          title: '另有 ${subjects.length - branchLimit} 项参与作品',
          subtitle: '进入人物详情查看完整列表',
          placeholderIcon: Icons.more_horiz_rounded,
          onTap: () => _openPersonPage(person),
        ),
      );
    }
    if (characters.length > branchLimit) {
      nodes.add(
        MonoRelationGraphNode(
          key: 'person:${person.id}:more-characters',
          relation: '更多角色',
          title: '另有 ${characters.length - branchLimit} 个关联角色',
          subtitle: '进入人物详情查看完整列表',
          placeholderIcon: Icons.more_horiz_rounded,
          onTap: () => _openPersonPage(person),
        ),
      );
    }
    if (nodes.isEmpty) {
      throw StateError('暂无可展开的作品或角色数据');
    }
    return nodes;
  }

  void _openPersonPage(RelatedPerson person) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PersonPage(person: person)));
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

    return MonoRelationViewSwitcher(
      mode: _relatedViewMode,
      onModeChanged: (mode) => _setRelationViewMode(
        mode,
        cacheName: _relatedViewModeCacheName,
        update: (value) => _relatedViewMode = value,
      ),
      itemCount: _relatedSubjects.length,
      listView: RefreshIndicator(
        onRefresh: _loadAllData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          children: _buildRelatedListItems(),
        ),
      ),
      graphView: MonoRelationGraph(
        graphId: 'subject:${widget.subjectId}:related',
        centerTitle: _subject!.displayName,
        centerSubtitle: '关联 ${_relatedSubjects.length}',
        centerImageUrl: _subject!.images?.medium ?? '',
        centerPlaceholderIcon: Icons.movie_outlined,
        nodes: _relatedSubjects.map(_buildRelatedGraphNode).toList(),
      ),
    );
  }

  MonoRelationGraphNode _buildRelatedGraphNode(RelatedSubject related) {
    return MonoRelationGraphNode(
      key: 'subject:${related.id}',
      relation: related.relation.isEmpty ? '其他' : related.relation,
      title: related.displayName,
      subtitle: _getSubjectTypeLabel(related.type),
      imageUrl: related.images['medium'] ?? '',
      placeholderIcon: Icons.movie_outlined,
      onTap: () => _openSubjectPage(related.id),
      loadChildren: () => _loadRelatedGraphChildren(related),
    );
  }

  Future<List<MonoRelationGraphNode>> _loadRelatedGraphChildren(
    RelatedSubject parent,
  ) async {
    final children = await context.read<ApiClient>().getSubjectRelations(
      parent.id,
    );
    return children
        .where((child) => child.id != widget.subjectId)
        .map(
          (child) => MonoRelationGraphNode(
            key: 'subject:${child.id}',
            relation: child.relation.isEmpty ? '其他' : child.relation,
            title: child.displayName,
            subtitle: _getSubjectTypeLabel(child.type),
            imageUrl: child.images['medium'] ?? '',
            placeholderIcon: Icons.movie_outlined,
            onTap: () => _openSubjectPage(child.id),
          ),
        )
        .toList();
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

  void _openSubjectPage(int subjectId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SubjectPage(subjectId: subjectId)),
    );
  }

  void _openAnimeTagPage(String tag) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => AnimeTagPage(initialTag: tag)));
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
                      MikanSubscriptionButton(subject: _subject!),
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
