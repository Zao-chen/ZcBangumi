import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants.dart';
import '../models/character.dart';
import '../models/comment.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import 'subject_page.dart';

/// 角色详情页
class CharacterPage extends StatefulWidget {
  final Character? character;
  final int? characterId;

  const CharacterPage({super.key, this.character, this.characterId});

  @override
  State<CharacterPage> createState() => _CharacterPageState();
}

class _CharacterPageState extends State<CharacterPage>
    with TickerProviderStateMixin {
  static const double _headerExpandedHeight = 188;

  static const _tabItems = [
    _CharacterTabItem(label: '概述', icon: Icons.article_outlined),
    _CharacterTabItem(label: '出演', icon: Icons.movie_outlined),
    _CharacterTabItem(label: '吐槽', icon: Icons.chat_bubble_outline),
  ];

  late TabController _tabController;
  final ScrollController _nestedScrollController = ScrollController();
  Character? _character;
  List<CharacterSubject> _characterSubjects = [];
  List<Comment> _comments = [];
  bool _loading = true;
  bool _showCollapsedTitle = false;
  int _selectedTabIndex = 0;
  String? _error;

  int? get _activeCharacterId => widget.characterId ?? _character?.id;
  String get _cacheKey => 'character_${_activeCharacterId ?? 0}';
  String get _subjectCacheKey =>
      'character_subjects_${_activeCharacterId ?? 0}';
  String get _commentCacheKey =>
      'character_comments_${_activeCharacterId ?? 0}';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabItems.length, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _nestedScrollController.addListener(_handleHeaderCollapse);

    if (widget.character != null) {
      _character = widget.character;
      _loading = false;
    }

    final characterId = widget.characterId ?? widget.character?.id;
    if (characterId != null) {
      _loadAllData(characterId);
    }
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

    final shouldShowTitle = _nestedScrollController.offset > 100;
    if (shouldShowTitle != _showCollapsedTitle && mounted) {
      setState(() => _showCollapsedTitle = shouldShowTitle);
    }
  }

  Future<void> _loadAllData(int characterId) async {
    final storage = context.read<StorageService>();
    final api = context.read<ApiClient>();

    if (_character == null) {
      final cached = storage.getCache(_cacheKey);
      if (cached is Map<String, dynamic>) {
        try {
          _character = Character.fromJson(cached);
        } catch (_) {}
      }
    }

    if (_characterSubjects.isEmpty) {
      final subjectCached = storage.getCache(_subjectCacheKey);
      if (subjectCached is List) {
        try {
          _characterSubjects = subjectCached
              .whereType<Map<String, dynamic>>()
              .map((e) => CharacterSubject.fromJson(e))
              .toList();
        } catch (_) {}
      }
    }

    if (_comments.isEmpty) {
      final commentsCached = storage.getCache(_commentCacheKey);
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
      _loading = _character == null;
      _error = null;
    });

    try {
      Character? latestCharacter;
      List<CharacterSubject>? latestSubjects;
      List<Comment>? latestComments;

      try {
        latestCharacter = await api.getCharacter(characterId);
      } catch (_) {}

      try {
        latestSubjects = await api.getCharacterSubjects(characterId);
      } catch (_) {}

      try {
        final commentsResult = await api.getCharacterComments(
          characterId: characterId,
        );
        latestComments = commentsResult.data;
      } catch (_) {}

      if (latestCharacter == null && _character == null) {
        setState(() => _error = '无法获取角色信息');
        return;
      }

      setState(() {
        if (latestCharacter != null) {
          _character = latestCharacter;
        }
        if (latestSubjects != null) {
          _characterSubjects = latestSubjects;
        }
        if (latestComments != null) {
          _comments = latestComments;
        }
        _error = null;
      });

      if (_character != null) {
        storage.setCache(_cacheKey, _character!.toJson());
      }
      storage.setCache(
        _subjectCacheKey,
        _characterSubjects.map((e) => e.toJson()).toList(),
      );
      storage.setCache(
        _commentCacheKey,
        _comments.map((e) => e.toJson()).toList(),
      );
    } catch (e) {
      if (_character == null) {
        setState(() => _error = '加载失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openCharacterWebPage() async {
    final characterId = _activeCharacterId;
    if (characterId == null) {
      return;
    }
    final uri = Uri.parse('${BgmConst.webBaseUrl}/character/$characterId');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('打开网页失败')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    if (_loading && _character == null) {
      return Scaffold(appBar: AppBar(), body: _buildSkeleton(isLandscape));
    }

    if (_error != null && _character == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('角色')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () {
                  final id = _activeCharacterId;
                  if (id != null) {
                    _loadAllData(id);
                  }
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_character == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('角色不存在')),
      );
    }

    return Scaffold(
      body: NestedScrollView(
        controller: _nestedScrollController,
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              pinned: true,
              expandedHeight: _headerExpandedHeight,
              actions: [
                IconButton(
                  tooltip: '打开网页',
                  onPressed: _openCharacterWebPage,
                  icon: const Icon(Icons.open_in_new),
                ),
              ],
              title: _showCollapsedTitle
                  ? Text(
                      _character!.name,
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
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: _buildHeaderCard(),
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
                      tabs: _tabItems
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
        _buildAppearancesTab(),
        _buildCommentsTab(),
      ],
    );
  }

  Widget _buildHeaderCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final character = _character!;
    final imageUrl = character.images.isNotEmpty
        ? (character.images.first.large.isNotEmpty
              ? character.images.first.large
              : character.images.first.medium)
        : '';

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: 86,
                      height: 112,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      placeholder: (context, url) => Container(
                        width: 86,
                        height: 112,
                        color: colorScheme.surfaceContainerHighest,
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 86,
                        height: 112,
                        color: colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.person),
                      ),
                    )
                  : Container(
                      width: 86,
                      height: 112,
                      color: colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.person),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    character.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (character.type.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            character.type,
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (character.relation.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            character.relation,
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${character.collects} 次收藏',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    final character = _character!;

    return RefreshIndicator(
      onRefresh: () async {
        final id = _activeCharacterId;
        if (id != null) {
          await _loadAllData(id);
        }
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (character.comment.isNotEmpty)
              _buildSection(
                title: '简介',
                child: Text(
                  character.comment,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ),
            if (character.summary.isNotEmpty)
              _buildSection(
                title: '详细描述',
                child: Text(
                  character.summary,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ),
            if (character.infobox.isNotEmpty)
              _buildSection(
                title: '详情',
                child: Column(
                  children: character.infobox.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 80,
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              entry.value,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            if (character.collects > 0)
              _buildSection(
                title: '人气',
                child: Row(
                  children: [
                    Icon(
                      Icons.favorite_outline,
                      size: 18,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${character.collects} 次收藏',
                      style: TextStyle(color: Colors.grey[700], fontSize: 14),
                    ),
                  ],
                ),
              ),
            if (character.comment.isEmpty &&
                character.summary.isEmpty &&
                character.infobox.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 120,
                  horizontal: 16,
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 56,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '暂无概述信息',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearancesTab() {
    if (_characterSubjects.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          final id = _activeCharacterId;
          if (id != null) {
            await _loadAllData(id);
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 120, horizontal: 16),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.movie_outlined, size: 60, color: Colors.grey[400]),
                  const SizedBox(height: 18),
                  Text(
                    '暂无出演条目',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        final id = _activeCharacterId;
        if (id != null) {
          await _loadAllData(id);
        }
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: _characterSubjects.length,
        itemBuilder: (context, index) {
          final subject = _characterSubjects[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SubjectPage(subjectId: subject.id),
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
                      child: subject.image.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: subject.image,
                              width: 74,
                              height: 98,
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              placeholder: (context, url) => Container(
                                width: 74,
                                height: 98,
                                color: Colors.grey[300],
                              ),
                              errorWidget: (context, url, error) => Container(
                                width: 74,
                                height: 98,
                                color: Colors.grey[300],
                                child: const Icon(Icons.movie_outlined),
                              ),
                            )
                          : Container(
                              width: 74,
                              height: 98,
                              color: Colors.grey[300],
                              child: const Icon(Icons.movie_outlined),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subject.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (subject.nameCn.isNotEmpty &&
                              subject.nameCn != subject.name) ...[
                            const SizedBox(height: 2),
                            Text(
                              subject.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (subject.staff.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    subject.staff,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              if (subject.eps.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    '章节: ${subject.eps}',
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontSize: 11,
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
            ),
          );
        },
      ),
    );
  }

  Widget _buildCommentsTab() {
    if (_comments.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          final id = _activeCharacterId;
          if (id != null) {
            await _loadAllData(id);
          }
        },
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
                    '这个角色还没有吐槽',
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
      onRefresh: () async {
        final id = _activeCharacterId;
        if (id != null) {
          await _loadAllData(id);
        }
      },
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

  Widget _buildSection({required String title, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          child,
        ],
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

  Widget _buildSkeleton(bool isLandscape) {
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
            expandedHeight: _headerExpandedHeight,
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
                  child: Align(
                    alignment: Alignment.bottomCenter,
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
                  child: const TabBar(
                    tabs: [
                      Tab(text: '概述'),
                      Tab(text: '出演'),
                      Tab(text: '吐槽'),
                    ],
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
                  destinations: _tabItems
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
}

class _CharacterTabItem {
  final String label;
  final IconData icon;

  const _CharacterTabItem({required this.label, required this.icon});
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
