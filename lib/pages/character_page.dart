import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models/character.dart';
import '../models/comment.dart';
import '../models/person.dart';
import '../pages/profile_page.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/link_navigator.dart';
import '../services/storage_service.dart';
import '../widgets/bangumi_post_widgets.dart';
import '../widgets/copyable_text.dart';
import '../widgets/mono_detail_scaffold.dart';
import '../widgets/mono_entity_widgets.dart';
import 'person_page.dart';
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
  static const _tabItems = [
    _CharacterTabItem(label: '概述', icon: Icons.article_outlined),
    _CharacterTabItem(label: '出演', icon: Icons.movie_outlined),
    _CharacterTabItem(label: '吐槽', icon: Icons.chat_bubble_outline),
  ];

  late TabController _tabController;
  final ScrollController _nestedScrollController = ScrollController();
  Character? _character;
  List<CharacterSubject> _characterSubjects = [];
  List<CharacterPerson> _characterPersons = [];
  List<Comment> _comments = [];
  bool _loading = true;
  bool _overviewLoading = false;
  bool _subjectsLoading = false;
  bool _personsLoading = false;
  bool _commentsLoading = false;
  bool _collectionLoading = false;
  bool _collectionUpdating = false;
  bool _isCollected = false;
  bool _showCollapsedTitle = false;
  int _selectedTabIndex = 0;
  String? _error;
  String? _personsError;

  int? get _activeCharacterId => widget.characterId ?? _character?.id;
  String get _cacheKey => 'character_${_activeCharacterId ?? 0}';
  String get _subjectCacheKey =>
      'character_subjects_${_activeCharacterId ?? 0}';
  String get _personCacheKey => 'character_persons_${_activeCharacterId ?? 0}';
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadCollectionState(characterId);
      });
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

    if (_characterPersons.isEmpty) {
      final personCached = storage.getCache(_personCacheKey);
      if (personCached is List) {
        try {
          _characterPersons = personCached
              .whereType<Map<String, dynamic>>()
              .map(CharacterPerson.fromJson)
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
      _overviewLoading = _character == null || _character!.infobox.isEmpty;
      _subjectsLoading = _characterSubjects.isEmpty;
      _personsLoading = _characterPersons.isEmpty;
      _commentsLoading = _comments.isEmpty;
      _error = null;
      _personsError = null;
    });

    try {
      Character? latestCharacter;
      List<CharacterSubject>? latestSubjects;
      List<CharacterPerson>? latestPersons;
      List<Comment>? latestComments;
      String? personsError;

      try {
        latestCharacter = await api.getCharacter(characterId);
      } catch (_) {}

      try {
        latestSubjects = await api.getCharacterSubjects(characterId);
      } catch (_) {}

      try {
        latestPersons = await api.getCharacterPersons(characterId);
      } catch (_) {
        if (_characterPersons.isEmpty) {
          personsError = '加载关联人物失败';
        }
      }

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
          _overviewLoading = false;
        }
        if (latestSubjects != null) {
          _characterSubjects = latestSubjects;
          _subjectsLoading = false;
        }
        if (latestPersons != null) {
          _characterPersons = latestPersons;
          _personsLoading = false;
        }
        _personsError = personsError;
        if (latestComments != null) {
          _comments = latestComments;
          _commentsLoading = false;
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
      if (latestPersons != null) {
        storage.setCache(
          _personCacheKey,
          _characterPersons.map((e) => e.toJson()).toList(),
        );
      }
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
        setState(() {
          _loading = false;
          _overviewLoading = false;
          _subjectsLoading = false;
          _personsLoading = false;
          _commentsLoading = false;
        });
      }
    }
  }

  Future<void> _loadCollectionState(int characterId) async {
    final auth = context.read<AuthProvider>();
    final username = auth.username;
    if (!auth.isLoggedIn || username == null || username.isEmpty) {
      if (mounted) {
        setState(() {
          _isCollected = false;
          _collectionLoading = false;
        });
      }
      return;
    }

    setState(() => _collectionLoading = true);
    final api = context.read<ApiClient>();
    try {
      final collected = await api.isCharacterCollected(
        username: username,
        characterId: characterId,
      );
      if (mounted) {
        setState(() => _isCollected = collected);
      }
    } catch (_) {
      // 收藏状态查询失败不影响详情页主体展示。
    } finally {
      if (mounted) {
        setState(() => _collectionLoading = false);
      }
    }
  }

  Future<void> _toggleCharacterCollection() async {
    final characterId = _activeCharacterId;
    if (characterId == null || _collectionUpdating) {
      return;
    }

    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先登录后再收藏角色')));
      return;
    }

    final api = context.read<ApiClient>();
    final nextCollected = !_isCollected;

    setState(() {
      _collectionUpdating = true;
      _isCollected = nextCollected;
    });

    try {
      if (nextCollected) {
        await api.collectCharacter(characterId);
      } else {
        await api.uncollectCharacter(characterId);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(nextCollected ? '已收藏角色' : '已取消收藏角色')),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isCollected = !nextCollected);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('更新角色收藏失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _collectionUpdating = false);
      }
    }
  }

  Future<void> _openCharacterWebPage() async {
    final characterId = _activeCharacterId;
    if (characterId == null) {
      return;
    }
    final uri = Uri.parse('${BgmConst.webBaseUrl}/character/$characterId');
    final ok = await LinkNavigator.openBrowser(uri);
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

    return MonoDetailScaffold(
      scrollController: _nestedScrollController,
      tabController: _tabController,
      tabs: _tabItems
          .map((tab) => MonoDetailTab(label: tab.label, icon: tab.icon))
          .toList(),
      tabChildren: [
        _buildOverviewTab(),
        _buildAppearancesTab(),
        _buildCommentsTab(),
      ],
      selectedTabIndex: _selectedTabIndex,
      showCollapsedTitle: _showCollapsedTitle,
      title: _character!.name,
      header: _buildHeaderCard(),
      actions: [
        IconButton(
          tooltip: _isCollected ? '取消收藏角色' : '收藏角色',
          onPressed: _collectionLoading || _collectionUpdating
              ? null
              : _toggleCharacterCollection,
          icon: _collectionUpdating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _isCollected
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
        ),
        IconButton(
          tooltip: '打开网页',
          onPressed: _openCharacterWebPage,
          icon: const Icon(Icons.open_in_new),
        ),
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

    return MonoEntityHeaderCard(
      imageUrl: imageUrl,
      placeholderIcon: Icons.person_outline_rounded,
      title: character.name,
      chips: [
        if (character.type.isNotEmpty) MonoEntityChip(character.type),
        if (character.relation.isNotEmpty)
          MonoEntityChip(character.relation, tone: MonoEntityChipTone.accent),
      ],
      footer: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${character.collects} 次收藏',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
          ),
          if (_isCollected)
            Icon(Icons.favorite_rounded, size: 14, color: colorScheme.primary),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final character = _character!;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final hasCharacterOverview =
        character.comment.isNotEmpty ||
        character.summary.isNotEmpty ||
        character.infobox.isNotEmpty ||
        character.collects > 0;
    final showPersonsSection =
        _personsLoading ||
        _personsError != null ||
        _characterPersons.isNotEmpty;

    if (_overviewLoading && !hasCharacterOverview) {
      return _buildOverviewSkeleton(isLandscape: isLandscape);
    }

    if (isLandscape) {
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
              if (_overviewLoading || hasCharacterOverview)
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
                            if (character.comment.isNotEmpty)
                              _buildSection(
                                title: '\u7b80\u4ecb',
                                padding: EdgeInsets.zero,
                                child: CopyableText(
                                  character.comment,
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 14,
                                    height: 1.6,
                                  ),
                                  enableLongPressCopy: false,
                                ),
                              ),
                            if (character.comment.isNotEmpty &&
                                (character.summary.isNotEmpty ||
                                    character.collects > 0))
                              const SizedBox(height: 24),
                            if (character.summary.isNotEmpty)
                              _buildSection(
                                title: '\u8be6\u7ec6\u63cf\u8ff0',
                                padding: EdgeInsets.zero,
                                child: CopyableText(
                                  character.summary,
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 14,
                                    height: 1.6,
                                  ),
                                  enableLongPressCopy: false,
                                ),
                              ),
                            if (character.summary.isNotEmpty &&
                                character.collects > 0)
                              const SizedBox(height: 24),
                            if (character.collects > 0)
                              _buildSection(
                                title: '\u4eba\u6c14',
                                padding: EdgeInsets.zero,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.favorite_outline,
                                      size: 18,
                                      color: Colors.grey[600],
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${character.collects} \u6b21\u6536\u85cf',
                                      style: TextStyle(
                                        color: Colors.grey[700],
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_overviewLoading || character.infobox.isNotEmpty) ...[
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 2,
                          child: _buildSection(
                            title: '\u8be6\u60c5',
                            padding: EdgeInsets.zero,
                            child: character.infobox.isNotEmpty
                                ? _buildInfoboxContent(character)
                                : _buildInfoboxSkeletonContent(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              if (showPersonsSection)
                _buildSection(
                  title: '声优',
                  child: _buildPersonsOverviewContent(),
                ),
              if (!hasCharacterOverview && !showPersonsSection)
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
                          '\u6682\u65e0\u6982\u89c8\u4fe1\u606f',
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
                child: CopyableText(
                  character.comment,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 14,
                    height: 1.6,
                  ),
                  enableLongPressCopy: false,
                ),
              ),
            if (character.summary.isNotEmpty)
              _buildSection(
                title: '详细描述',
                child: CopyableText(
                  character.summary,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 14,
                    height: 1.6,
                  ),
                  enableLongPressCopy: false,
                ),
              ),
            if (character.infobox.isNotEmpty)
              _buildSection(
                title: '详情',
                child: MonoEntityInfoTable(info: character.infobox),
              ),
            if (showPersonsSection)
              _buildSection(title: '声优', child: _buildPersonsOverviewContent()),
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
            if (!hasCharacterOverview && !showPersonsSection)
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
    if (_subjectsLoading && _characterSubjects.isEmpty) {
      return const MonoEntitySkeletonList(imageWidth: 74, imageHeight: 98);
    }

    if (_characterSubjects.isEmpty) {
      return MonoEntityEmptyState(
        message: '暂无出演条目',
        icon: Icons.movie_outlined,
        onRefresh: () async {
          final id = _activeCharacterId;
          if (id != null) {
            await _loadAllData(id);
          }
        },
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
          return MonoEntityListCard(
            imageUrl: subject.image,
            placeholderIcon: Icons.movie_outlined,
            imageWidth: 74,
            imageHeight: 98,
            title: subject.displayName,
            subtitle:
                subject.nameCn.isNotEmpty && subject.nameCn != subject.name
                ? subject.name
                : '',
            chips: [
              if (subject.staff.isNotEmpty)
                MonoEntityChip(subject.staff, tone: MonoEntityChipTone.accent),
              if (subject.eps.isNotEmpty) MonoEntityChip('章节 ${subject.eps}'),
            ],
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SubjectPage(subjectId: subject.id),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPersonsOverviewContent() {
    if (_personsLoading && _characterPersons.isEmpty) {
      return Column(
        children: List.generate(
          2,
          (index) => Padding(
            padding: EdgeInsets.only(bottom: index == 0 ? 8 : 0),
            child: _buildPersonOverviewSkeleton(),
          ),
        ),
      );
    }

    if (_personsError != null && _characterPersons.isEmpty) {
      final colorScheme = Theme.of(context).colorScheme;
      return Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: colorScheme.errorContainer.withValues(alpha: 0.45),
        child: ListTile(
          leading: Icon(Icons.cloud_off_outlined, color: colorScheme.error),
          title: Text(_personsError!),
          subtitle: const Text('点击重试'),
          trailing: const Icon(Icons.refresh_rounded),
          onTap: () {
            final id = _activeCharacterId;
            if (id != null) _loadAllData(id);
          },
        ),
      );
    }

    final groups = _groupCharacterPersons(_characterPersons);
    if (groups.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final group in groups.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildPersonOverviewCard(group),
          ),
        if (groups.length > 3)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _showAllCharacterPersons(groups),
              icon: const Icon(Icons.people_outline_rounded, size: 18),
              label: Text('查看全部（${groups.length}）'),
            ),
          ),
      ],
    );
  }

  Widget _buildPersonOverviewCard(
    _CharacterPersonGroup group, {
    String keyPrefix = 'character_person',
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final person = group.person;
    return Card(
      key: ValueKey('${keyPrefix}_${group.key}'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap ?? () => _openPersonPage(person),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MonoEntityImage(
                imageUrl: person.images?.bestSmall ?? '',
                placeholderIcon: Icons.badge_outlined,
                width: 52,
                height: 64,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (group.subjectSummary.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        group.subjectSummary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ...group.staffLabels
                            .take(2)
                            .map(
                              (staff) => MonoEntityChipView(
                                MonoEntityChip(
                                  staff,
                                  tone: MonoEntityChipTone.accent,
                                ),
                              ),
                            ),
                        ...group.subjectTypes
                            .take(2)
                            .map(
                              (type) => MonoEntityChipView(
                                MonoEntityChip(BgmConst.subjectTypeName(type)),
                              ),
                            ),
                      ],
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Icon(Icons.chevron_right_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPersonOverviewSkeleton() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 64,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120,
                  height: 12,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
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
        ],
      ),
    );
  }

  Future<void> _showAllCharacterPersons(
    List<_CharacterPersonGroup> groups,
  ) async {
    final selected = await showModalBottomSheet<CharacterPerson>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  '全部声优（${groups.length}）',
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildPersonOverviewCard(
                        group,
                        keyPrefix: 'all_character_person',
                        onTap: () =>
                            Navigator.of(sheetContext).pop(group.person),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) _openPersonPage(selected);
  }

  void _openPersonPage(CharacterPerson person) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PersonPage(person: person)));
  }

  List<_CharacterPersonGroup> _groupCharacterPersons(
    List<CharacterPerson> persons,
  ) {
    final groups = <String, _CharacterPersonGroup>{};
    for (var index = 0; index < persons.length; index++) {
      final person = persons[index];
      final key = person.id > 0 ? '${person.id}' : 'row_$index';
      groups
          .putIfAbsent(key, () => _CharacterPersonGroup(key, person))
          .relations
          .add(person);
    }
    return groups.values.toList(growable: false);
  }

  Widget _buildCommentsTab() {
    if (_commentsLoading && _comments.isEmpty) {
      return _buildCommentsSkeletonList();
    }

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

    return RefreshIndicator(
      onRefresh: () async {
        final id = _activeCharacterId;
        if (id != null) {
          await _loadAllData(id);
        }
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: _comments.length,
        itemBuilder: (context, index) {
          final comment = _comments[index];
          return _buildCommentItem(comment, index);
        },
      ),
    );
  }

  Widget _buildCommentItem(Comment comment, int index) {
    final floorNumber = index + 1;
    final replies = comment.replyItems
        .asMap()
        .entries
        .map(
          (entry) => _commentToPostData(
            entry.value,
            '#$floorNumber-${entry.key + 1}',
            emptyContentLabel: '该回复已删除',
          ),
        )
        .toList(growable: false);

    return BangumiPostCard(
      post: _commentToPostData(
        comment,
        '#$floorNumber',
        emptyContentLabel: comment.state == 6 ? '该评论已删除' : null,
      ),
      replies: replies,
      nestedReplyKeyPrefix: 'comment_reply',
      nestedRepliesKey: ValueKey('comment_replies_${comment.id}'),
      onUserTap: (post) {
        final userId = int.tryParse(post.authorKey) ?? 0;
        if (userId <= 0) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OtherUserProfilePage(
              userId: userId,
              displayName: post.authorName,
            ),
          ),
        );
      },
    );
  }

  BangumiPostData _commentToPostData(
    Comment comment,
    String floorText, {
    String? emptyContentLabel,
  }) {
    final userId = _commentUserId(comment);
    return BangumiPostData(
      id: comment.id.toString(),
      authorKey: userId > 0 ? userId.toString() : '',
      authorName: comment.userName,
      avatarUrl: comment.userAvatar,
      metaText: formatBangumiPostMeta(
        floorText: floorText,
        dateTime: comment.createdAt,
      ),
      content: comment.content,
      contentHtml: comment.contentHtml,
      emptyContentLabel: emptyContentLabel,
    );
  }

  int _commentUserId(Comment comment) {
    final rawId = comment.user['id'];
    if (rawId is int) return rawId;
    if (rawId is num) return rawId.toInt();
    return int.tryParse(rawId?.toString() ?? '') ?? 0;
  }

  Widget _buildInfoboxContent(Character character) {
    return MonoEntityInfoTable(info: character.infobox);
  }

  Widget _buildInfoboxSkeletonContent() {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: List.generate(4, (index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 80,
                height: 14,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: index.isEven ? 14 : 30,
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
    );
  }

  Widget _buildSection({
    required String title,
    required Widget child,
    EdgeInsets padding = const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 12,
    ),
  }) {
    return MonoEntityOverviewSection(
      title: title,
      padding: padding,
      child: child,
    );
  }

  Widget _buildSkeleton(bool isLandscape) {
    final colorScheme = Theme.of(context).colorScheme;
    final content = ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: 5,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
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

  Widget _buildOverviewSkeleton({required bool isLandscape}) {
    final colorScheme = Theme.of(context).colorScheme;

    if (isLandscape) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 72,
                    height: 18,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...List.generate(5, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        width: index == 4 ? 220 : double.infinity,
                        height: 12,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                  Container(
                    width: 88,
                    height: 18,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...List.generate(4, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        width: index == 3 ? 260 : double.infinity,
                        height: 12,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 72,
                    height: 18,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...List.generate(4, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 80,
                            height: 14,
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              height: index.isEven ? 14 : 30,
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
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 18,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(5, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: index == 4 ? 220 : double.infinity,
                height: 12,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            );
          }),
          const SizedBox(height: 18),
          Container(
            width: 72,
            height: 18,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(3, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 80,
                    height: 14,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 14,
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
                            width: 120,
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
}

class _CharacterPersonGroup {
  final String key;
  final CharacterPerson person;
  final List<CharacterPerson> relations = [];

  _CharacterPersonGroup(this.key, this.person);

  List<String> get staffLabels =>
      _distinct(relations.map((relation) => relation.staff.trim()));

  List<int> get subjectTypes => _distinct(
    relations.map((relation) => relation.subjectType).where((type) => type > 0),
  );

  String get subjectSummary {
    final names = _distinct(
      relations.map((relation) => relation.displaySubjectName.trim()),
    );
    if (names.length <= 2) return names.join('、');
    return '${names.take(2).join('、')} 等 ${names.length} 部作品';
  }

  static List<T> _distinct<T>(Iterable<T> values) {
    return values
        .where((value) => value.toString().isNotEmpty)
        .toSet()
        .toList(growable: false);
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
