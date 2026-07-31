import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bangumi_index.dart';
import '../models/rakuen_topic_favorite.dart';
import '../pages/character_page.dart';
import '../pages/person_page.dart';
import '../pages/profile_page.dart';
import '../pages/subject_page.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/link_navigator.dart';
import '../services/storage_service.dart';
import '../widgets/bangumi_index_actions.dart';

class BangumiIndexPage extends StatefulWidget {
  final int indexId;

  const BangumiIndexPage({super.key, required this.indexId});

  @override
  State<BangumiIndexPage> createState() => _BangumiIndexPageState();
}

class _BangumiIndexPageState extends State<BangumiIndexPage> {
  static const _pageSize = 30;
  BangumiIndex? _index;
  final List<BangumiIndexRelated> _items = [];
  IndexRelatedCategory? _category;
  int? _subjectType;
  bool _loading = true;
  bool _relatedLoading = true;
  bool _loadingMore = false;
  bool _collecting = false;
  bool _manageMode = false;
  bool _savingOrder = false;
  int _relatedTotal = 0;
  int _relatedNextOffset = 0;
  int _detailRequestVersion = 0;
  int _relatedRequestVersion = 0;
  String? _viewerUsername;
  bool _dependenciesInitialized = false;
  String? _error;
  String? _relatedError;

  String get _detailCacheKey =>
      bangumiIndexDetailCacheKey(widget.indexId, _viewerUsername);
  String get _relatedCacheKey => bangumiIndexRelatedCacheKey(
    widget.indexId,
    _category,
    _subjectType,
    _viewerUsername,
  );

  bool get _isOwner {
    final userId = context.read<AuthProvider>().user?.id;
    return userId != null &&
        userId == _index?.uid &&
        _index?.type == BangumiIndexType.user;
  }

  bool get _canManage => _isOwner && !_isSystemIndex;

  bool get _isSystemIndex {
    if (_index?.isSystemSyncIndex == true) return true;
    final cached = context.read<StorageService>().getCache(
      rakuenFavoriteIndexCacheKey(_viewerUsername),
    );
    return cached is int
        ? cached == widget.indexId
        : int.tryParse('$cached') == widget.indexId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final username = Provider.of<AuthProvider>(context).username?.trim();
    if (!_dependenciesInitialized) {
      _dependenciesInitialized = true;
      _viewerUsername = username;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
      return;
    }
    if (bangumiIndexViewerCacheScope(_viewerUsername) ==
        bangumiIndexViewerCacheScope(username)) {
      _viewerUsername = username;
      return;
    }
    _viewerUsername = username;
    _detailRequestVersion++;
    _relatedRequestVersion++;
    setState(() {
      _index = null;
      _items.clear();
      _loading = true;
      _relatedLoading = true;
      _relatedNextOffset = 0;
      _relatedTotal = 0;
      _manageMode = false;
      _error = null;
      _relatedError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final storage = context.read<StorageService>();
    final cached = storage.getCache(_detailCacheKey);
    if (_index == null && cached is Map) {
      try {
        _index = BangumiIndex.fromJson(Map<String, dynamic>.from(cached));
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _loading = _index == null;
        _error = null;
      });
    }
    await Future.wait([_loadDetail(), _loadRelated()]);
  }

  Future<void> _loadDetail() async {
    final cacheKey = _detailCacheKey;
    final requestVersion = ++_detailRequestVersion;
    try {
      final result = await context.read<ApiClient>().getBangumiIndex(
        widget.indexId,
      );
      if (!mounted || requestVersion != _detailRequestVersion) return;
      setState(() {
        _index = result;
        _error = null;
      });
      await context.read<StorageService>().setCache(cacheKey, result.toJson());
    } catch (error) {
      if (mounted &&
          requestVersion == _detailRequestVersion &&
          _index == null) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted && requestVersion == _detailRequestVersion) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadRelated({bool useCache = true}) async {
    final storage = context.read<StorageService>();
    final category = _category;
    final subjectType = _subjectType;
    final cacheKey = _relatedCacheKey;
    final requestVersion = ++_relatedRequestVersion;
    if (useCache && _items.isEmpty) {
      final cached = storage.getCache(cacheKey);
      if (cached is List) {
        for (final raw in cached.whereType<Map>()) {
          try {
            _items.add(
              BangumiIndexRelated.fromJson(Map<String, dynamic>.from(raw)),
            );
          } catch (_) {}
        }
      }
    }
    if (mounted) {
      setState(() {
        _relatedLoading = _items.isEmpty;
        _loadingMore = false;
        _relatedError = null;
      });
    }
    try {
      final loaded = <BangumiIndexRelated>[];
      var nextOffset = 0;
      var total = 0;
      do {
        final result = await context.read<ApiClient>().getIndexRelated(
          indexId: widget.indexId,
          category: category,
          subjectType: subjectType,
          limit: _pageSize,
          offset: nextOffset,
        );
        loaded.addAll(result.data);
        total = result.total;
        nextOffset += _pageSize;
      } while (loaded.isEmpty && nextOffset < total);
      if (!mounted || requestVersion != _relatedRequestVersion) return;
      setState(() {
        _items
          ..clear()
          ..addAll(loaded);
        _relatedTotal = total;
        _relatedNextOffset = nextOffset;
      });
      await storage.setCache(
        cacheKey,
        _items.map((item) => item.toJson()).toList(),
      );
    } catch (error) {
      if (mounted &&
          requestVersion == _relatedRequestVersion &&
          _items.isEmpty) {
        setState(() => _relatedError = '$error');
      }
    } finally {
      if (mounted && requestVersion == _relatedRequestVersion) {
        setState(() => _relatedLoading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore ||
        _manageMode ||
        _relatedNextOffset >= _relatedTotal ||
        _relatedLoading) {
      return;
    }
    setState(() => _loadingMore = true);
    final requestVersion = _relatedRequestVersion;
    final category = _category;
    final subjectType = _subjectType;
    final cacheKey = _relatedCacheKey;
    try {
      final additions = <BangumiIndexRelated>[];
      var nextOffset = _relatedNextOffset;
      var total = _relatedTotal;
      do {
        final result = await context.read<ApiClient>().getIndexRelated(
          indexId: widget.indexId,
          category: category,
          subjectType: subjectType,
          limit: _pageSize,
          offset: nextOffset,
        );
        additions.addAll(
          result.data.where(
            (item) =>
                !_items.any((existing) => existing.id == item.id) &&
                !additions.any((existing) => existing.id == item.id),
          ),
        );
        total = result.total;
        nextOffset += _pageSize;
      } while (additions.isEmpty && nextOffset < total);
      if (!mounted || requestVersion != _relatedRequestVersion) return;
      setState(() {
        _items.addAll(additions);
        _relatedTotal = total;
        _relatedNextOffset = nextOffset;
      });
      await context.read<StorageService>().setCache(
        cacheKey,
        _items.map((item) => item.toJson()).toList(growable: false),
      );
    } catch (error) {
      if (mounted && requestVersion == _relatedRequestVersion) {
        _showMessage('$error');
      }
    } finally {
      if (mounted && requestVersion == _relatedRequestVersion) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _selectCategory(IndexRelatedCategory? category) async {
    if (_savingOrder || _category == category) return;
    final keepManaging = _manageMode;
    setState(() {
      _category = category;
      _subjectType = null;
      _items.clear();
      _relatedNextOffset = 0;
      _relatedTotal = 0;
      _loadingMore = false;
    });
    if (keepManaging) {
      if (category == null) {
        setState(() => _manageMode = false);
        await _loadRelated();
      } else {
        await _loadManagementItems();
      }
    } else {
      await _loadRelated();
    }
  }

  Future<void> _selectSubjectType(int? type) async {
    if (_savingOrder || _manageMode || _subjectType == type) return;
    setState(() {
      _subjectType = type;
      _items.clear();
      _relatedNextOffset = 0;
      _relatedTotal = 0;
      _loadingMore = false;
    });
    await _loadRelated();
  }

  Future<void> _toggleCollection() async {
    final auth = context.read<AuthProvider>();
    final storage = context.read<StorageService>();
    final username = auth.username;
    if (!auth.isLoggedIn) {
      _showMessage('请先登录后再收藏目录');
      return;
    }
    if (_collecting || _index == null || _isSystemIndex) return;
    final wasCollected = _index!.isCollected;
    setState(() => _collecting = true);
    try {
      final api = context.read<ApiClient>();
      if (wasCollected) {
        await api.uncollectBangumiIndex(widget.indexId);
      } else {
        await api.collectBangumiIndex(widget.indexId);
      }
      await invalidateBangumiIndexCaches(
        storage,
        indexId: widget.indexId,
        username: username,
      );
      await _loadDetail();
    } catch (error) {
      if (mounted) _showMessage('$error');
    } finally {
      if (mounted) setState(() => _collecting = false);
    }
  }

  Future<void> _editIndex() async {
    final index = _index;
    if (!_canManage || index == null) return;
    final result = await showBangumiIndexEditor(context, existing: index);
    if (result == null || !mounted) return;
    await context.read<StorageService>().removeCache(_detailCacheKey);
    await _loadDetail();
  }

  Future<void> _deleteIndex() async {
    if (!_canManage || _index == null) return;
    final api = context.read<ApiClient>();
    final storage = context.read<StorageService>();
    final username = context.read<AuthProvider>().username;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除目录？'),
        content: Text('“${_index!.title}”删除后无法在应用内恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await api.deleteBangumiIndex(widget.indexId);
      await invalidateBangumiIndexCaches(
        storage,
        indexId: widget.indexId,
        username: username,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) _showMessage('$error');
    }
  }

  Future<void> _enterManageMode() async {
    if (!_canManage) return;
    final category =
        _category ??
        IndexRelatedCategory.values.firstWhere(
          (item) => _index!.stats.countFor(item) > 0,
          orElse: () => IndexRelatedCategory.subject,
        );
    setState(() {
      _category = category;
      _subjectType = null;
      _manageMode = true;
      _items.clear();
      _relatedNextOffset = 0;
      _relatedTotal = 0;
    });
    await _loadManagementItems();
  }

  Future<void> _loadManagementItems() async {
    final category = _category;
    if (!_manageMode || category == null) return;
    final requestVersion = ++_relatedRequestVersion;
    setState(() {
      _relatedLoading = true;
      _relatedError = null;
      _loadingMore = false;
    });
    try {
      final api = context.read<ApiClient>();
      final all = <BangumiIndexRelated>[];
      var offset = 0;
      var total = 0;
      while (true) {
        final page = await api.getIndexRelated(
          indexId: widget.indexId,
          category: category,
          limit: 100,
          offset: offset,
        );
        all.addAll(page.data);
        total = page.total;
        offset += 100;
        if (offset >= page.total) break;
      }
      if (mounted && requestVersion == _relatedRequestVersion) {
        setState(() {
          _items
            ..clear()
            ..addAll(all);
          _relatedTotal = total;
          _relatedNextOffset = offset;
        });
        await context.read<StorageService>().setCache(
          bangumiIndexRelatedCacheKey(
            widget.indexId,
            category,
            null,
            _viewerUsername,
          ),
          all.map((item) => item.toJson()).toList(growable: false),
        );
      }
    } catch (error) {
      if (mounted && requestVersion == _relatedRequestVersion) {
        setState(() => _manageMode = false);
        _showMessage('$error');
      }
    } finally {
      if (mounted && requestVersion == _relatedRequestVersion) {
        setState(() => _relatedLoading = false);
      }
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (_savingOrder) return;
    final storage = context.read<StorageService>();
    final username = context.read<AuthProvider>().username;
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() {
      final moved = _items.removeAt(oldIndex);
      _items.insert(newIndex, moved);
      _savingOrder = true;
    });
    try {
      final api = context.read<ApiClient>();
      final updates = buildBangumiIndexOrderUpdates(_items);
      for (var i = 0; i < _items.length; i++) {
        final item = _items[i];
        final nextOrder = updates[item.id];
        if (nextOrder == null) continue;
        await api.updateBangumiIndexRelated(
          indexId: widget.indexId,
          relatedId: item.id,
          order: nextOrder,
          comment: item.comment,
        );
      }
      await invalidateBangumiIndexCaches(
        storage,
        indexId: widget.indexId,
        username: username,
      );
      await _loadManagementItems();
    } catch (error) {
      if (mounted) {
        _showMessage('排序未完整保存，已重新载入：$error');
        await _loadManagementItems();
      }
    } finally {
      if (mounted) setState(() => _savingOrder = false);
    }
  }

  Future<void> _editRelated(BangumiIndexRelated item) async {
    final controller = TextEditingController(text: item.comment);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('编辑备注：${item.title}'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: '备注',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true && mounted) {
      try {
        await context.read<ApiClient>().updateBangumiIndexRelated(
          indexId: widget.indexId,
          relatedId: item.id,
          order: item.order,
          comment: controller.text,
        );
        await _invalidateRelatedRef(item.category, item.sid);
        await _reloadRelatedForMode();
      } catch (error) {
        if (mounted) _showMessage('$error');
      }
    }
    controller.dispose();
  }

  Future<void> _deleteRelated(BangumiIndexRelated item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移出目录？'),
        content: Text('确定将“${item.title}”移出此目录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<ApiClient>().deleteBangumiIndexRelated(
        indexId: widget.indexId,
        relatedId: item.id,
      );
      await _invalidateRelatedRef(item.category, item.sid);
      await _loadDetail();
      await _reloadRelatedForMode();
    } catch (error) {
      if (mounted) _showMessage('$error');
    }
  }

  Future<void> _showPasteLinkDialog() async {
    if (!_canManage) return;
    final linkController = TextEditingController();
    final commentController = TextEditingController();
    String? error;
    var adding = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          Future<void> add() async {
            final ref = BangumiIndexContentRef.parse(linkController.text);
            if (ref == null) {
              setState(() => error = '无法识别该 Bangumi 链接');
              return;
            }
            setState(() {
              adding = true;
              error = null;
            });
            try {
              var offset = 0;
              var maxOrder = 0;
              final api = context.read<ApiClient>();
              while (true) {
                final page = await api.getIndexRelated(
                  indexId: widget.indexId,
                  category: ref.category,
                  limit: 100,
                  offset: offset,
                );
                for (final item in page.data) {
                  if (item.order > maxOrder) maxOrder = item.order;
                }
                offset += 100;
                if (offset >= page.total) break;
              }
              await api.addBangumiIndexRelated(
                indexId: widget.indexId,
                category: ref.category,
                subjectId: ref.id,
                order: maxOrder + 10,
                comment: commentController.text,
              );
              await _invalidateRelatedRef(ref.category, ref.id);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              await _loadDetail();
              await _reloadRelatedForMode();
            } catch (e) {
              if (dialogContext.mounted) {
                setState(() {
                  adding = false;
                  error = '$e';
                });
              }
            }
          }

          return PopScope(
            canPop: !adding,
            child: AlertDialog(
              title: const Text('通过链接添加内容'),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: linkController,
                        autofocus: true,
                        enabled: !adding,
                        decoration: const InputDecoration(
                          labelText: 'Bangumi 链接',
                          hintText: 'https://bgm.tv/subject/123',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: commentController,
                        minLines: 2,
                        maxLines: 5,
                        enabled: !adding,
                        decoration: const InputDecoration(
                          labelText: '备注（可选）',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: adding ? null : () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: adding ? null : add,
                  child: adding
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('添加'),
                ),
              ],
            ),
          );
        },
      ),
    );
    linkController.dispose();
    commentController.dispose();
  }

  Future<void> _invalidateRelatedRef(
    IndexRelatedCategory category,
    int id,
  ) async {
    final storage = context.read<StorageService>();
    await invalidateBangumiIndexCaches(
      storage,
      indexId: widget.indexId,
      username: context.read<AuthProvider>().username,
      category: category,
      contentId: id,
    );
  }

  Future<void> _reloadRelatedForMode() {
    return _manageMode ? _loadManagementItems() : _loadRelated(useCache: false);
  }

  void _openRelated(BangumiIndexRelated item) {
    final page = switch (item.category) {
      IndexRelatedCategory.subject => SubjectPage(subjectId: item.sid),
      IndexRelatedCategory.character => CharacterPage(characterId: item.sid),
      IndexRelatedCategory.person => PersonPage(personId: item.sid),
      _ => null,
    };
    if (page != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    } else {
      LinkNavigator.open(context, Uri.parse(item.webUrl));
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final index = _index;
    return Scaffold(
      appBar: AppBar(
        title: Text(index?.title ?? '目录'),
        actions: [
          if (_canManage)
            IconButton(
              tooltip: '通过链接添加',
              onPressed: _showPasteLinkDialog,
              icon: const Icon(Icons.add_link_rounded),
            ),
          if (_canManage)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') _editIndex();
                if (value == 'manage') {
                  _manageMode
                      ? setState(() => _manageMode = false)
                      : _enterManageMode();
                }
                if (value == 'delete') _deleteIndex();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('编辑目录')),
                PopupMenuItem(
                  value: 'manage',
                  child: Text(_manageMode ? '退出内容管理' : '管理目录内容'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'delete', child: Text('删除目录')),
              ],
            ),
          IconButton(
            tooltip: '打开网页',
            onPressed: () => LinkNavigator.openBrowser(
              Uri.parse('https://bgm.tv/index/${widget.indexId}'),
            ),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: _showPasteLinkDialog,
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加内容'),
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _index == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _index == null) {
      return _PageMessage(message: _error!, onRetry: _load);
    }
    if (_index == null) {
      return _PageMessage(message: '目录不存在', onRetry: _load);
    }

    final list = _manageMode
        ? ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            header: _buildHeader(),
            itemCount: _items.length,
            onReorder: _reorder,
            itemBuilder: (context, index) => _buildRelatedCard(
              _items[index],
              key: ValueKey(_items[index].id),
              reorderIndex: index,
            ),
          )
        : NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.extentAfter < 360) _loadMore();
              return false;
            },
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: _items.length + 2 + (_loadingMore ? 1 : 0),
                itemBuilder: (context, position) {
                  if (position == 0) return _buildHeader();
                  if (position == 1) return _buildRelatedState();
                  final index = position - 2;
                  if (index >= _items.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _buildRelatedCard(_items[index]);
                },
              ),
            ),
          );
    return list;
  }

  Widget _buildHeader() {
    final index = _index!;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 24,
                        foregroundImage: index.userAvatar.isEmpty
                            ? null
                            : CachedNetworkImageProvider(index.userAvatar),
                        child: index.userAvatar.isEmpty
                            ? const Icon(Icons.person_outline)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              index.title,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: index.username.isEmpty
                                  ? null
                                  : () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => OtherUserProfilePage(
                                          username: index.username,
                                        ),
                                      ),
                                    ),
                              child: Text(
                                'by ${index.userName}',
                                style: TextStyle(color: colors.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_collecting)
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else if (!_isSystemIndex)
                        IconButton.filledTonal(
                          tooltip: index.isCollected ? '取消收藏' : '收藏目录',
                          onPressed: _toggleCollection,
                          icon: Icon(
                            index.isCollected
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                          ),
                        ),
                    ],
                  ),
                  if (index.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    SelectableText(index.description.trim()),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MetaChip(
                        icon: Icons.format_list_bulleted_rounded,
                        text: '${index.total} 项',
                      ),
                      _MetaChip(
                        icon: Icons.favorite_outline_rounded,
                        text: '${index.collects} 收藏',
                      ),
                      _MetaChip(
                        icon: Icons.category_outlined,
                        text: index.type.label,
                      ),
                      if (index.isPrivate)
                        const _MetaChip(
                          icon: Icons.lock_outline_rounded,
                          text: '私密',
                        ),
                      if (_isSystemIndex)
                        const _MetaChip(
                          icon: Icons.sync_lock_rounded,
                          text: '系统同步目录 · 只读',
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            children: [
              ChoiceChip(
                label: Text('全部 ${index.total}'),
                selected: _category == null,
                onSelected: _manageMode ? null : (_) => _selectCategory(null),
              ),
              for (final category in IndexRelatedCategory.values) ...[
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text(
                    '${category.label} ${index.stats.countFor(category)}',
                  ),
                  selected: _category == category,
                  onSelected: (_) => _selectCategory(category),
                ),
              ],
            ],
          ),
        ),
        if (_category == IndexRelatedCategory.subject && !_manageMode)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                _subjectTypeChip(null, '全部'),
                _subjectTypeChip(2, '动画'),
                _subjectTypeChip(1, '书籍'),
                _subjectTypeChip(3, '音乐'),
                _subjectTypeChip(4, '游戏'),
                _subjectTypeChip(6, '三次元'),
              ],
            ),
          ),
        if (_manageMode)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _savingOrder
                  ? '正在保存顺序…'
                  : '拖动右侧把手排序；当前管理“${_category?.label ?? ''}”分类。',
            ),
          ),
      ],
    );
  }

  Widget _subjectTypeChip(int? type, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: _subjectType == type,
        onSelected: (_) => _selectSubjectType(type),
      ),
    );
  }

  Widget _buildRelatedState() {
    if (_relatedLoading && _items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(36),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_relatedError != null && _items.isEmpty) {
      return _InlineMessage(
        text: _relatedError!,
        onPressed: () => _loadRelated(useCache: false),
      );
    }
    if (_items.isEmpty) {
      return _InlineMessage(
        text: '此分类暂无内容',
        onPressed: _canManage ? _showPasteLinkDialog : null,
        actionLabel: '添加内容',
      );
    }
    return const SizedBox(height: 4);
  }

  Widget _buildRelatedCard(
    BangumiIndexRelated item, {
    Key? key,
    int? reorderIndex,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => _openRelated(item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 48,
                  height: 48,
                  color: colors.surfaceContainerHighest,
                  child: item.imageUrl.isEmpty
                      ? Icon(_categoryIcon(item.category))
                      : CachedNetworkImage(
                          imageUrl: item.imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) =>
                              Icon(_categoryIcon(item.category)),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (item.subtitle.isNotEmpty)
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    if (item.comment.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        item.comment.trim(),
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              if (_manageMode) ...[
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') _editRelated(item);
                    if (value == 'delete') _deleteRelated(item);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑备注')),
                    PopupMenuItem(value: 'delete', child: Text('移出目录')),
                  ],
                ),
                if (reorderIndex != null)
                  ReorderableDragStartListener(
                    index: reorderIndex,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.drag_handle_rounded),
                    ),
                  ),
              ] else
                const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _categoryIcon(IndexRelatedCategory category) =>
      switch (category) {
        IndexRelatedCategory.subject => Icons.movie_outlined,
        IndexRelatedCategory.character => Icons.face_outlined,
        IndexRelatedCategory.person => Icons.badge_outlined,
        IndexRelatedCategory.episode => Icons.play_circle_outline_rounded,
        IndexRelatedCategory.blog => Icons.article_outlined,
        IndexRelatedCategory.groupTopic => Icons.forum_outlined,
        IndexRelatedCategory.subjectTopic => Icons.chat_bubble_outline_rounded,
      };
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(text),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _PageMessage extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _PageMessage({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 46),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final String actionLabel;

  const _InlineMessage({
    required this.text,
    this.onPressed,
    this.actionLabel = '重试',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          children: [
            Text(text, textAlign: TextAlign.center),
            if (onPressed != null)
              TextButton(onPressed: onPressed, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
