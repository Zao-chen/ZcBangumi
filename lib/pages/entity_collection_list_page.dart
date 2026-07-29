import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/collection.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../widgets/centered_content.dart';
import '../widgets/mono_entity_widgets.dart';
import 'character_page.dart';
import 'person_page.dart';

enum EntityCollectionKind { character, person }

enum _EntityCollectionSort {
  newest('最近收藏'),
  oldest('最早收藏'),
  name('名称排序');

  final String label;
  const _EntityCollectionSort(this.label);
}

class EntityCollectionListPage extends StatefulWidget {
  final String username;
  final EntityCollectionKind initialKind;

  const EntityCollectionListPage({
    super.key,
    required this.username,
    this.initialKind = EntityCollectionKind.character,
  });

  @override
  State<EntityCollectionListPage> createState() =>
      _EntityCollectionListPageState();
}

class _EntityCollectionListPageState extends State<EntityCollectionListPage> {
  static const _pageSize = 30;

  final TextEditingController _searchController = TextEditingController();
  late EntityCollectionKind _kind;
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
    _kind = widget.initialKind;
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _cacheKey(EntityCollectionKind kind) =>
      'entity_collections_${widget.username}_${kind.name}';

  String get _searchQuery => _searchController.text.trim().toLowerCase();

  bool get _hasSearchQuery => _searchQuery.isNotEmpty;

  bool get _needsCompleteList =>
      _hasSearchQuery || _sort != _EntityCollectionSort.newest;

  Future<PagedResult<UserEntityCollection>> _fetchPage({
    required EntityCollectionKind kind,
    required int offset,
  }) async {
    final api = context.read<ApiClient>();
    switch (kind) {
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

  List<UserEntityCollection> _readCachedItems(EntityCollectionKind kind) {
    final cached = context.read<StorageService>().getCache(_cacheKey(kind));
    if (cached is! List) return const [];

    try {
      return cached.whereType<Map>().map((item) {
        final json = Map<String, dynamic>.from(item);
        return switch (kind) {
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

  Future<void> _writeCache(
    EntityCollectionKind kind,
    List<UserEntityCollection> items,
  ) async {
    await context.read<StorageService>().setCache(
      _cacheKey(kind),
      items.map((item) => item.toJson()).toList(),
    );
  }

  Future<void> _loadData({bool refresh = true}) async {
    final requestedKind = _kind;
    final generation = refresh ? ++_generation : _generation;
    final offset = refresh ? 0 : _items.length;
    var pageLoaded = false;

    if (refresh) {
      final cached = _items.isEmpty
          ? _readCachedItems(requestedKind)
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
      final result = await _fetchPage(kind: requestedKind, offset: offset);
      if (!mounted || generation != _generation || requestedKind != _kind) {
        return;
      }
      final nextItems = refresh ? result.data : _mergeById(_items, result.data);
      setState(() {
        _items = nextItems;
        _total = result.total;
        _error = null;
      });
      await _writeCache(requestedKind, nextItems);
      pageLoaded = true;
    } catch (error) {
      if (!mounted || generation != _generation || requestedKind != _kind) {
        return;
      }
      if (_items.isEmpty) {
        setState(() => _error = '加载失败: $error');
      }
    } finally {
      if (mounted && generation == _generation && requestedKind == _kind) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
    if (pageLoaded &&
        mounted &&
        generation == _generation &&
        requestedKind == _kind &&
        _needsCompleteList &&
        _items.length < _total) {
      await _loadAllRemaining();
    }
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
    final requestedKind = _kind;
    final generation = _generation;
    setState(() => _loadingMore = true);

    try {
      while (mounted &&
          generation == _generation &&
          requestedKind == _kind &&
          _items.length < _total) {
        final result = await _fetchPage(
          kind: requestedKind,
          offset: _items.length,
        );
        if (!mounted || generation != _generation || requestedKind != _kind) {
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
      if (mounted && generation == _generation && requestedKind == _kind) {
        await _writeCache(requestedKind, _items);
      }
    } catch (error) {
      if (mounted && generation == _generation && requestedKind == _kind) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载更多失败: $error')));
      }
    } finally {
      if (mounted && generation == _generation && requestedKind == _kind) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _switchKind(EntityCollectionKind kind) {
    if (_kind == kind) return;
    _generation++;
    setState(() {
      _kind = kind;
      _items = [];
      _total = 0;
      _loading = true;
      _loadingMore = false;
      _error = null;
    });
    _loadData();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('角色与人物收藏'),
        centerTitle: false,
        actions: [
          PopupMenuButton<_EntityCollectionSort>(
            icon: const Icon(Icons.sort),
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
      body: ResponsiveContent(
        maxWidth: 900,
        child: Column(
          children: [
            _buildToolbar(colorScheme),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<EntityCollectionKind>(
              key: const ValueKey('entity_collection_kind_selector'),
              segments: const [
                ButtonSegment(
                  value: EntityCollectionKind.character,
                  icon: Icon(Icons.theater_comedy_outlined),
                  label: Text('角色'),
                ),
                ButtonSegment(
                  value: EntityCollectionKind.person,
                  icon: Icon(Icons.badge_outlined),
                  label: Text('人物'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (selection) {
                _switchKind(selection.first);
              },
              showSelectedIcon: false,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('entity_collection_search'),
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: _kind == EntityCollectionKind.character
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
            ),
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 8),
          Text(
            '${_kind == EntityCollectionKind.character ? '角色' : '人物'}收藏 · $_total',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading && _items.isEmpty) {
      return const MonoEntitySkeletonList(imageWidth: 72, imageHeight: 96);
    }

    if (_error != null && _items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Icon(Icons.error_outline, size: 52, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: FilledButton.tonal(
                onPressed: _loadData,
                child: const Text('重试'),
              ),
            ),
          ],
        ),
      );
    }

    final visible = _visibleItems;
    final isCompletingSearch =
        _hasSearchQuery && _loadingMore && _items.length < _total;
    if (_items.isEmpty || (visible.isEmpty && !isCompletingSearch)) {
      return MonoEntityEmptyState(
        message: _hasSearchQuery ? '没有找到相关收藏' : '暂无收藏',
        icon: _kind == EntityCollectionKind.character
            ? Icons.theater_comedy_outlined
            : Icons.badge_outlined,
        onRefresh: _loadData,
      );
    }

    final hasMore = !_hasSearchQuery && _items.length < _total;
    final itemCount = visible.length + (hasMore || isCompletingSearch ? 1 : 0);
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
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
      ),
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
      imageUrl: item.images?.bestSmall ?? '',
      placeholderIcon: item is UserCharacterCollection
          ? Icons.theater_comedy_outlined
          : Icons.badge_outlined,
      imageWidth: 72,
      imageHeight: 96,
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
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '收藏于 ${date.year}-$month-$day';
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
    if (mounted) await _loadData();
  }
}
