import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models/person.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/link_navigator.dart';
import '../services/storage_service.dart';
import '../widgets/copyable_text.dart';
import '../widgets/mono_detail_scaffold.dart';
import '../widgets/mono_entity_widgets.dart';
import 'character_page.dart';
import 'subject_page.dart';

class PersonPage extends StatefulWidget {
  final PersonSummary? person;
  final int? personId;

  const PersonPage({super.key, this.person, this.personId});

  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> with TickerProviderStateMixin {
  static const _tabs = [
    _PersonTab(label: '概述', icon: Icons.article_outlined),
    _PersonTab(label: '作品', icon: Icons.movie_outlined),
    _PersonTab(label: '角色', icon: Icons.theater_comedy_outlined),
  ];

  late final TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  PersonSummary? _person;
  PersonDetail? _detail;
  List<PersonSubject> _subjects = [];
  List<PersonCharacter> _characters = [];
  bool _loading = true;
  bool _detailLoading = false;
  bool _subjectsLoading = false;
  bool _charactersLoading = false;
  bool _collectionLoading = false;
  bool _collectionUpdating = false;
  bool _isCollected = false;
  bool _showCollapsedTitle = false;
  int _selectedTabIndex = 0;
  String? _error;

  int? get _activePersonId => widget.personId ?? _person?.id;
  PersonSummary? get _displayPerson => _detail ?? _person;
  String get _detailCacheKey => 'person_${_activePersonId ?? 0}';
  String get _subjectsCacheKey => 'person_subjects_${_activePersonId ?? 0}';
  String get _charactersCacheKey => 'person_characters_${_activePersonId ?? 0}';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this)
      ..addListener(_handleTabChanged);
    _scrollController.addListener(_handleHeaderCollapse);
    _person = widget.person;
    _loading = _person == null;
    final id = widget.personId ?? widget.person?.id;
    if (id != null) {
      _loadAllData(id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadCollectionState(id);
      });
    }
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    _scrollController
      ..removeListener(_handleHeaderCollapse)
      ..dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (mounted && _selectedTabIndex != _tabController.index) {
      setState(() => _selectedTabIndex = _tabController.index);
    }
  }

  void _handleHeaderCollapse() {
    if (!_scrollController.hasClients) return;
    final collapsed = _scrollController.offset > 100;
    if (mounted && collapsed != _showCollapsedTitle) {
      setState(() => _showCollapsedTitle = collapsed);
    }
  }

  Future<void> _loadAllData(int personId) async {
    final storage = context.read<StorageService>();
    final api = context.read<ApiClient>();

    if (_detail == null) {
      final cached = storage.getCache(_detailCacheKey);
      if (cached is Map<String, dynamic>) {
        try {
          _detail = PersonDetail.fromJson(cached);
          _person = _detail;
        } catch (_) {}
      }
    }
    if (_subjects.isEmpty) {
      final cached = storage.getCache(_subjectsCacheKey);
      if (cached is List) {
        try {
          _subjects = cached
              .whereType<Map<String, dynamic>>()
              .map(PersonSubject.fromJson)
              .toList();
        } catch (_) {}
      }
    }
    if (_characters.isEmpty) {
      final cached = storage.getCache(_charactersCacheKey);
      if (cached is List) {
        try {
          _characters = cached
              .whereType<Map<String, dynamic>>()
              .map(PersonCharacter.fromJson)
              .toList();
        } catch (_) {}
      }
    }

    if (mounted) {
      setState(() {
        _loading = _displayPerson == null;
        _detailLoading = _detail == null;
        _subjectsLoading = _subjects.isEmpty;
        _charactersLoading = _characters.isEmpty;
        _error = null;
      });
    }

    PersonDetail? latestDetail;
    List<PersonSubject>? latestSubjects;
    List<PersonCharacter>? latestCharacters;
    Object? detailError;

    try {
      latestDetail = await api.getPerson(personId);
    } catch (error) {
      detailError = error;
    }
    try {
      latestSubjects = await api.getPersonSubjects(personId);
    } catch (_) {}
    try {
      latestCharacters = await api.getPersonCharacters(personId);
    } catch (_) {}

    if (!mounted) return;
    if (latestDetail == null && _displayPerson == null) {
      setState(() {
        _error = detailError == null ? '无法获取人物信息' : '加载失败: $detailError';
        _loading = false;
        _detailLoading = false;
        _subjectsLoading = false;
        _charactersLoading = false;
      });
      return;
    }

    setState(() {
      if (latestDetail != null) {
        _detail = latestDetail;
        _person = latestDetail;
      }
      if (latestSubjects != null) _subjects = latestSubjects;
      if (latestCharacters != null) _characters = latestCharacters;
      _loading = false;
      _detailLoading = false;
      _subjectsLoading = false;
      _charactersLoading = false;
      _error = null;
    });

    if (_detail != null) storage.setCache(_detailCacheKey, _detail!.toJson());
    storage.setCache(
      _subjectsCacheKey,
      _subjects.map((subject) => subject.toJson()).toList(),
    );
    storage.setCache(
      _charactersCacheKey,
      _characters.map((character) => character.toJson()).toList(),
    );
  }

  Future<void> _loadCollectionState(int personId) async {
    final auth = context.read<AuthProvider>();
    final username = auth.username;
    if (!auth.isLoggedIn || username == null || username.isEmpty) {
      if (mounted) setState(() => _collectionLoading = false);
      return;
    }
    setState(() => _collectionLoading = true);
    try {
      final collected = await context.read<ApiClient>().isPersonCollected(
        username: username,
        personId: personId,
      );
      if (mounted) setState(() => _isCollected = collected);
    } catch (_) {
      // 收藏状态失败不阻塞人物详情。
    } finally {
      if (mounted) setState(() => _collectionLoading = false);
    }
  }

  Future<void> _toggleCollection() async {
    final personId = _activePersonId;
    if (personId == null || _collectionUpdating) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先登录后再收藏人物')));
      return;
    }

    final nextCollected = !_isCollected;
    setState(() {
      _isCollected = nextCollected;
      _collectionUpdating = true;
    });
    try {
      final api = context.read<ApiClient>();
      if (nextCollected) {
        await api.collectPerson(personId);
      } else {
        await api.uncollectPerson(personId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(nextCollected ? '已收藏人物' : '已取消收藏人物')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _isCollected = !nextCollected);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('更新人物收藏失败: $error')));
      }
    } finally {
      if (mounted) setState(() => _collectionUpdating = false);
    }
  }

  Future<void> _openWebPage() async {
    final personId = _activePersonId;
    if (personId == null) return;
    final ok = await LinkNavigator.openBrowser(
      Uri.parse('${BgmConst.webBaseUrl}/person/$personId'),
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('打开网页失败')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _displayPerson == null) {
      return Scaffold(appBar: AppBar(), body: _buildPageSkeleton());
    }
    if (_error != null && _displayPerson == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('人物')),
        body: _buildErrorState(),
      );
    }
    if (_displayPerson == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('人物不存在')),
      );
    }

    return MonoDetailScaffold(
      scrollController: _scrollController,
      tabController: _tabController,
      tabs: _tabs
          .map((tab) => MonoDetailTab(label: tab.label, icon: tab.icon))
          .toList(),
      tabChildren: [
        _buildOverviewTab(),
        _buildSubjectsTab(),
        _buildCharactersTab(),
      ],
      selectedTabIndex: _selectedTabIndex,
      showCollapsedTitle: _showCollapsedTitle,
      title: _displayPerson!.name,
      header: _buildHeaderCard(),
      actions: [
        IconButton(
          key: const ValueKey('person_collection_button'),
          tooltip: _isCollected ? '取消收藏人物' : '收藏人物',
          onPressed: _collectionLoading || _collectionUpdating
              ? null
              : _toggleCollection,
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
          onPressed: _openWebPage,
          icon: const Icon(Icons.open_in_new_rounded),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () {
              final id = _activePersonId;
              if (id != null) _loadAllData(id);
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    final person = _displayPerson!;
    final colorScheme = Theme.of(context).colorScheme;
    return MonoEntityHeaderCard(
      imageUrl: person.images?.bestLarge ?? '',
      placeholderIcon: Icons.badge_outlined,
      title: person.name,
      chips: [
        MonoEntityChip(person.typeLabel),
        ...person.careerLabels.take(3).map(MonoEntityChip.new),
        if (person.careerLabels.length > 3)
          MonoEntityChip('+${person.careerLabels.length - 3}'),
      ],
      footer: (_detail?.collects ?? 0) > 0 || _isCollected
          ? Row(
              children: [
                if ((_detail?.collects ?? 0) > 0)
                  Text(
                    '${_detail!.collects} 次收藏',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                if (_isCollected) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.favorite_rounded,
                    size: 14,
                    color: colorScheme.primary,
                  ),
                ],
              ],
            )
          : null,
    );
  }

  Widget _buildOverviewTab() {
    final detail = _detail;
    final summary = detail?.summary ?? _person?.shortSummary ?? '';
    if (_detailLoading && detail == null && summary.isEmpty) {
      return _buildPageSkeleton();
    }
    final info = <String, String>{};
    final careerLabels = _displayPerson?.careerLabels ?? const <String>[];
    if (careerLabels.isNotEmpty) info['职业'] = careerLabels.join('、');
    if ((detail?.gender ?? '').isNotEmpty) info['性别'] = detail!.gender;
    if ((detail?.bloodTypeLabel ?? '').isNotEmpty) {
      info['血型'] = '${detail!.bloodTypeLabel}型';
    }
    if ((detail?.birthdayLabel ?? '').isNotEmpty) {
      info['生日'] = detail!.birthdayLabel;
    }
    if (detail != null) info.addAll(detail.infobox);

    final summarySection = MonoEntityOverviewSection(
      title: '简介',
      padding: EdgeInsets.zero,
      child: CopyableText(
        summary,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 14,
          height: 1.6,
        ),
        enableLongPressCopy: false,
      ),
    );
    final infoSection = MonoEntityOverviewSection(
      title: '详情',
      padding: EdgeInsets.zero,
      child: MonoEntityInfoTable(info: info),
    );
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: isLandscape
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                child: summary.isEmpty && info.isEmpty
                    ? const MonoEntityOverviewEmptyState()
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (summary.isNotEmpty)
                            Expanded(flex: 3, child: summarySection),
                          if (summary.isNotEmpty && info.isNotEmpty)
                            const SizedBox(width: 24),
                          if (info.isNotEmpty)
                            Expanded(flex: 2, child: infoSection),
                        ],
                      ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (summary.isNotEmpty)
                    MonoEntityOverviewSection(
                      title: '简介',
                      child: summarySection.child,
                    ),
                  if (info.isNotEmpty)
                    MonoEntityOverviewSection(
                      title: '详情',
                      child: infoSection.child,
                    ),
                  if (summary.isEmpty && info.isEmpty)
                    const MonoEntityOverviewEmptyState(),
                  const SizedBox(height: 16),
                ],
              ),
      ),
    );
  }

  Widget _buildSubjectsTab() {
    if (_subjectsLoading && _subjects.isEmpty) {
      return const MonoEntitySkeletonList(imageWidth: 74, imageHeight: 98);
    }
    if (_subjects.isEmpty) {
      return MonoEntityEmptyState(
        message: '暂无参与作品',
        icon: Icons.movie_outlined,
        onRefresh: _refresh,
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: _subjects.length,
        itemBuilder: (context, index) {
          final subject = _subjects[index];
          return MonoEntityListCard(
            key: ValueKey('person_subject_${subject.id}'),
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

  Widget _buildCharactersTab() {
    if (_charactersLoading && _characters.isEmpty) {
      return const MonoEntitySkeletonList(imageWidth: 74, imageHeight: 98);
    }
    if (_characters.isEmpty) {
      return MonoEntityEmptyState(
        message: '暂无关联角色',
        icon: Icons.theater_comedy_outlined,
        onRefresh: _refresh,
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: _characters.length,
        itemBuilder: (context, index) {
          final character = _characters[index];
          return MonoEntityListCard(
            key: ValueKey('person_character_${character.id}'),
            imageUrl: character.images?.bestSmall ?? '',
            placeholderIcon: Icons.theater_comedy_outlined,
            imageWidth: 74,
            imageHeight: 98,
            title: character.name,
            subtitle: character.displaySubjectName,
            chips: [
              if (character.staff.isNotEmpty)
                MonoEntityChip(
                  character.staff,
                  tone: MonoEntityChipTone.accent,
                ),
            ],
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CharacterPage(characterId: character.id),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _refresh() async {
    final id = _activePersonId;
    if (id != null) await _loadAllData(id);
  }

  Widget _buildPageSkeleton() {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: List.generate(
        4,
        (index) => Container(
          height: index == 0 ? 110 : 64,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _PersonTab {
  final String label;
  final IconData icon;

  const _PersonTab({required this.label, required this.icon});
}
