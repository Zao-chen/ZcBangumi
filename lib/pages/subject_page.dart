import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/character.dart';
import '../models/collection.dart';
import '../models/comment.dart';
import '../models/episode.dart';
import '../models/subject.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../widgets/progress_grid.dart';
import '../widgets/subject_action_buttons.dart';
import 'character_page.dart';

class SubjectPage extends StatefulWidget {
  final int subjectId;
  final Subject? subject;

  const SubjectPage({super.key, required this.subjectId, this.subject});

  @override
  State<SubjectPage> createState() => _SubjectPageState();
}

class _SubjectPageState extends State<SubjectPage>
    with TickerProviderStateMixin {
  static const _tabItems = [
    _SubjectTabItem(label: '概述', icon: Icons.article_outlined),
    _SubjectTabItem(label: '角色', icon: Icons.groups_outlined),
    _SubjectTabItem(label: '关联条目', icon: Icons.link_outlined),
    _SubjectTabItem(label: '吐槽', icon: Icons.chat_bubble_outline),
  ];

  late TabController _tabController;
  final ScrollController _nestedScrollController = ScrollController();
  Subject? _subject;
  UserCollection? _userCollection;
  List<Character> _characters = [];
  List<RelatedSubject> _relatedSubjects = [];
  List<UserEpisodeCollection> _episodes = [];
  List<Comment> _comments = [];
  bool _loading = true;
  bool _episodesLoading = false;
  bool _showCollapsedTitle = false;
  int _selectedTabIndex = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabItems.length, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _nestedScrollController.addListener(_handleHeaderCollapse);
    if (widget.subject != null) {
      _subject = widget.subject;
      _loading = false;
    }
    _loadAllData();
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

  String get _cacheName => 'subject_${widget.subjectId}';
  String get _charsCacheName => 'subject_chars_${widget.subjectId}';
  String get _relatedCacheName => 'subject_related_${widget.subjectId}';
  String get _episodesCacheName => 'subject_episodes_${widget.subjectId}';
  String get _commentsCacheName => 'subject_comments_${widget.subjectId}';

  Future<void> _loadAllData() async {
    final storage = context.read<StorageService>();
    final api = context.read<ApiClient>();

    if (_subject == null) {
      final cached = storage.getCache(_cacheName);
      if (cached is Map<String, dynamic>) {
        try {
          _subject = Subject.fromJson(cached);
        } catch (_) {}
      }
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

    setState(() {
      _loading = _subject == null;
      _error = null;
    });

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
        _error = null;
      });

      if (_subject != null) {
        storage.setCache(_cacheName, _subject!.toJson());
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
        setState(() => _loading = false);
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

    setState(() => _episodesLoading = true);

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
      if (mounted) {
        setState(() => _episodesLoading = false);
      }
    }
  }

  Future<void> _loadUserCollection() async {
    final api = context.read<ApiClient>();
    final authProvider = context.read<AuthProvider>();

    if (!authProvider.isLoggedIn) {
      return;
    }

    try {
      final collections = await api.getUserCollections(
        username: authProvider.user!.username,
      );

      final index = collections.data.indexWhere(
        (c) => c.subjectId == widget.subjectId,
      );

      if (index != -1) {
        setState(() {
          _userCollection = collections.data[index];
        });
      }
    } catch (e) {
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

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    if (_loading && _subject == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
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
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          final colorScheme = Theme.of(context).colorScheme;
          return [
            SliverAppBar(
              pinned: true,
              elevation: 0,
              scrolledUnderElevation: 0,
              expandedHeight: 200,
              title: _showCollapsedTitle
                  ? Text(
                      _subject!.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                        bottom:
                            BorderSide(color: Theme.of(context).dividerColor),
                      ),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      tabs: _tabItems.map((tab) => Tab(text: tab.label)).toList(),
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
            destinations: _tabItems
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
      children: [
        _buildOverviewTab(),
        _buildCharactersTab(),
        _buildRelatedTab(),
        _buildCommentsTab(),
      ],
    );
  }

  Widget _buildOverviewTab() {
    final colorScheme = Theme.of(context).colorScheme;

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
                  loading: _episodesLoading,
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
            if (_subject!.summary.isNotEmpty)
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
                    Text(
                      _subject!.summary,
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              ),
            if (_subject!.tags.isNotEmpty)
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
                      children: _subject!.tags.map((tag) {
                        return Chip(
                          label: Text(
                            tag,
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: colorScheme.surfaceContainerHigh,
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            if (_subject!.infobox.isNotEmpty)
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
                              child: Text(
                                key,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
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
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCharactersTab() {
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

  Widget _buildRelatedTab() {
    if (_relatedSubjects.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadAllData,
        child: const Center(child: Text('暂无关联条目')),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: _relatedSubjects.length,
        itemBuilder: (context, index) {
          final related = _relatedSubjects[index];
          final imageUrl = related.images['medium'] ?? '';

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SubjectPage(subjectId: related.id),
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
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '关系: ${related.relation}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
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
        },
      ),
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
                  Text(
                    _subject!.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_subject!.name != _subject!.nameCn &&
                      _subject!.name.isNotEmpty)
                    Text(
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
                  if (_subject!.collectionTotal > 0)
                    Text(
                      '${_subject!.collectionTotal} 人',
                      style: TextStyle(color: Colors.grey[700], fontSize: 12),
                    )
                  else
                    Text(
                      '暂无收藏',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
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
                if (comment.userAvatar.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: CachedNetworkImage(
                      imageUrl: comment.userAvatar,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 40,
                        height: 40,
                        color: Colors.grey[300],
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 40,
                        height: 40,
                        color: Colors.grey[300],
                        child: const Icon(Icons.person, size: 20),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey[300],
                    ),
                    child: const Icon(Icons.person, size: 20),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comment.userName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
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
            Text(
              comment.content,
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
