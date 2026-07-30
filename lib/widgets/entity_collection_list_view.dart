import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/collection.dart';
import '../pages/character_page.dart';
import '../pages/person_page.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import 'mono_entity_widgets.dart';

enum EntityCollectionKind { character, person }

enum _EntityCollectionSort {
  newest('最近收藏'),
  oldest('最早收藏'),
  name('名称排序');

  final String label;
  const _EntityCollectionSort(this.label);
}

class EntityCollectionListView extends StatefulWidget {
  final String username;
  final EntityCollectionKind kind;

  const EntityCollectionListView({
    super.key,
    required this.username,
    required this.kind,
  });

  @override
  State<EntityCollectionListView> createState() =>
      EntityCollectionListViewState();
}

class EntityCollectionListViewState extends State<EntityCollectionListView> {
  static const _pageSize = 30;

  final TextEditingController _searchController = TextEditingController();
  _EntityCollectionSort _sort = _EntityCollectionSort.newest;
  List<UserEntityCollection> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _total = 0;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant EntityCollectionListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.username == widget.username &&
        oldWidget.kind == widget.kind) {
      return;
    }
    _generation++;
    _items = [];
    _total = 0;
    _loading = true;
    _loadingMore = false;
    _error = null;
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _cacheKey =>
      'entity_collections_${widget.username}_${widget.kind.name}';

  String get _searchQuery => _searchController.text.trim().toLowerCase();

  bool get _hasSearchQuery => _searchQuery.isNotEmpty;

  bool get _needsCompleteList =>
      _hasSearchQuery || _sort != _EntityCollectionSort.newest;

  Future<void> refresh() => _loadData();

  Future<PagedResult<UserEntityCollection>> _fetchPage(int offset) async {
    final api = context.read<ApiClient>();
    switch (widget.kind) {
      case EntityCollectionKind.character:
        final result = await api.getUserCharacterCollections(
          username: widget.username,
          limit: _pageSize,
          offset: offset,
        );
        return PagedResult<UserEntityCollection>(
          total: result.total,
          limit: result.limit,
          offset: result.offset,
          data: List<UserEntityCollection>.of(result.data),
        );
      case EntityCollectionKind.person:
        final result = await api.getUserPersonCollections(
          username: widget.username,
          limit: _pageSize,
          offset: offset,
        );
        return PagedResult<UserEntityCollection>(
          total: result.total,
          limit: result.limit,
          offset: result.offset,
          data: List<UserEntityCollection>.of(result.data),
        );
    }
  }

  List<UserEntityCollection> _readCachedItems() {
    final cached = context.read<StorageService>().getCache(_cacheKey);
    if (cached is! List) return const [];

    try {
      return cached.whereType<Map>().map((item) {
        final json = Map<String, dynamic>.from(item);
        return switch (widget.kind) {
          EntityCollectionKind.character => UserCharacterCollection.fromJson(
            json,
          ),
          EntityCollectionKind.person => UserPersonCollection.fromJson(json),
        };
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeCache(List<UserEntityCollection> items) async {
    await context.read<StorageService>().setCache(
      _cacheKey,
      items.map((item) => item.toJson()).toList(),
    );
  }

  Future<void> _loadData({bool refresh = true}) async {
    final requestedKind = widget.kind;
    final requestedUsername = widget.username;
    final generation = refresh ? ++_generation : _generation;
    final offset = refresh ? 0 : _items.length;
    var pageLoaded = false;

    if (refresh) {
      final cached = _items.isEmpty
          ? _readCachedItems()
          : const <UserEntityCollection>[];
      if (cached.isNotEmpty) {
        _items = cached;
        _total = cached.length;
      }
      setState(() {
        _loading = _items.isEmpty;
        _error = null;
      });
    }

    try {
      final result = await _fetchPage(offset);
      if (!_isCurrentRequest(requestedKind, requestedUsername, generation)) {
        return;
      }
      final nextItems = refresh ? result.data : _mergeById(_items, result.data);
      setState(() {
        _items = nextItems;
        _total = result.total;
        _error = null;
      });
      await _writeCache(nextItems);
      pageLoaded = true;
    } catch (error) {
      if (!_isCurrentRequest(requestedKind, requestedUsername, generation)) {
        return;
      }
      if (_items.isEmpty) setState(() => _error = '加载失败: $error');
    } finally {
      if (_isCurrentRequest(requestedKind, requestedUsername, generation)) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }

    if (pageLoaded &&
        _isCurrentRequest(requestedKind, requestedUsername, generation) &&
        _needsCompleteList &&
        _items.length < _total) {
      await _loadAllRemaining();
    }
  }

  bool _isCurrentRequest(
    EntityCollectionKind kind,
    String username,
    int generation,
  ) {
    return mounted &&
        generation == _generation &&
        kind == widget.kind &&
        username == widget.username;
  }

  List<UserEntityCollection> _mergeById(
    List<UserEntityCollection> current,
    List<UserEntityCollection> incoming,
  ) {
    final result = List<UserEntityCollection>.of(current);
    final ids = current.map((item) => item.id).toSet();
    for (final item in incoming) {
      if (ids.add(item.id)) result.add(item);
    }
    return result;
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _items.length >= _total) return;
    setState(() => _loadingMore = true);
    await _loadData(refresh: false);
  }

  Future<void> _loadAllRemaining() async {
    if (_loadingMore || _items.length >= _total) return;
    final requestedKind = widget.kind;
    final requestedUsername = widget.username;
    final generation = _generation;
    setState(() => _loadingMore = true);

    try {
      while (_isCurrentRequest(requestedKind, requestedUsername, generation) &&
          _items.length < _total) {
        final result = await _fetchPage(_items.length);
        if (!_isCurrentRequest(requestedKind, requestedUsername, generation)) {
          return;
        }
        if (result.data.isEmpty) break;
        final merged = _mergeById(_items, result.data);
        if (merged.length == _items.length) break;
        setState(() {
          _items = merged;
          _total = result.total;
        });
      }
      if (_isCurrentRequest(requestedKind, requestedUsername, generation)) {
        await _writeCache(_items);
      }
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          requestedKind == widget.kind &&
          requestedUsername == widget.username) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载更多失败: $error')));
      }
    } finally {
      if (_isCurrentRequest(requestedKind, requestedUsername, generation)) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _switchSort(_EntityCollectionSort sort) {
    if (_sort == sort) return;
    setState(() => _sort = sort);
    if (_needsCompleteList) _loadAllRemaining();
  }

  void _onSearchChanged(String value) {
    setState(() {});
    if (_hasSearchQuery) _loadAllRemaining();
  }

  void _clearSearch() {
    if (_searchController.text.isEmpty) return;
    _searchController.clear();
    setState(() {});
  }

  List<UserEntityCollection> get _visibleItems {
    final query = _searchQuery;
    final filtered = query.isEmpty
        ? List<UserEntityCollection>.of(_items)
        : _items.where((item) => _matchesSearch(item, query)).toList();
    filtered.sort((a, b) {
      return switch (_sort) {
        _EntityCollectionSort.newest => b.createdAt.compareTo(a.createdAt),
        _EntityCollectionSort.oldest => a.createdAt.compareTo(b.createdAt),
        _EntityCollectionSort.name => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
      };
    });
    return filtered;
  }

  bool _matchesSearch(UserEntityCollection item, String query) {
    final fields = <String>[
      '${item.id}',
      item.name,
      item.typeLabel,
      if (item is UserPersonCollection) ...item.careerLabels,
    ];
    return fields.any((field) => field.toLowerCase().contains(query));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildToolbar(colorScheme),
        const SizedBox(height: 8),
        _buildList(colorScheme),
      ],
    );
  }

  Widget _buildToolbar(ColorScheme colorScheme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              const Spacer(),
              PopupMenuButton<_EntityCollectionSort>(
                icon: const Icon(Icons.sort, size: 20),
                tooltip: '排序',
                onSelected: _switchSort,
                itemBuilder: (context) => _EntityCollectionSort.values
                    .map(
                      (sort) => PopupMenuItem(
                        value: sort,
                        child: Row(
                          children: [
                            if (_sort == sort)
                              Icon(
                                Icons.check,
                                size: 18,
                                color: colorScheme.primary,
                              )
                            else
                              const SizedBox(width: 18),
                            const SizedBox(width: 8),
                            Text(sort.label),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: TextField(
            key: const ValueKey('entity_collection_search'),
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: widget.kind == EntityCollectionKind.character
                  ? '搜索角色收藏'
                  : '搜索人物收藏',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _hasSearchQuery
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: '清除搜索',
                      onPressed: _clearSearch,
                    )
                  : null,
              isDense: true,
              filled: true,
              fillColor: colorScheme.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onChanged: _onSearchChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildList(ColorScheme colorScheme) {
    if (_loading && _items.isEmpty) {
      return const MonoEntitySkeletonList(
        imageWidth: 56,
        imageHeight: 80,
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
      );
    }

    if (_error != null && _items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 72),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: refresh, child: const Text('重试')),
          ],
        ),
      );
    }

    final visible = _visibleItems;
    final isCompletingSearch =
        _hasSearchQuery && _loadingMore && _items.length < _total;
    if (_items.isEmpty || (visible.isEmpty && !isCompletingSearch)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 72),
        child: Column(
          children: [
            Icon(
              _hasSearchQuery ? Icons.search_off_rounded : Icons.inbox_outlined,
              size: 56,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              _hasSearchQuery ? '没有找到相关收藏' : '暂无收藏',
              style: TextStyle(fontSize: 15, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    final hasMore = !_hasSearchQuery && _items.length < _total;
    final itemCount = visible.length + (hasMore || isCompletingSearch ? 1 : 0);
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == visible.length) {
          if (!_loadingMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
          }
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _buildCollectionCard(visible[index]);
      },
    );
  }

  Widget _buildCollectionCard(UserEntityCollection item) {
    final personCareers = item is UserPersonCollection
        ? item.careerLabels
        : const <String>[];
    return MonoEntityListCard(
      key: ValueKey(
        'entity_collection_${item is UserCharacterCollection ? 'character' : 'person'}_${item.id}',
      ),
      margin: const EdgeInsets.symmetric(vertical: 4),
      imageUrl: item.images?.bestSmall ?? '',
      placeholderIcon: item is UserCharacterCollection
          ? Icons.theater_comedy_outlined
          : Icons.badge_outlined,
      imageWidth: 56,
      imageHeight: 80,
      title: item.name,
      subtitle: _formatCollectionDate(item.createdAt),
      chips: [
        MonoEntityChip(item.typeLabel, tone: MonoEntityChipTone.accent),
        ...personCareers.take(3).map(MonoEntityChip.new),
      ],
      onTap: () => _openDetail(item),
    );
  }

  String _formatCollectionDate(DateTime date) {
    if (date.millisecondsSinceEpoch == 0) return '';
    final localDate = date.toLocal();
    final month = localDate.month.toString().padLeft(2, '0');
    final day = localDate.day.toString().padLeft(2, '0');
    return '收藏于 ${localDate.year}-$month-$day';
  }

  Future<void> _openDetail(UserEntityCollection item) async {
    if (item is UserCharacterCollection) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CharacterPage(characterId: item.id)),
      );
    } else if (item is UserPersonCollection) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => PersonPage(personId: item.id)));
    }
    if (mounted) await refresh();
  }
}
