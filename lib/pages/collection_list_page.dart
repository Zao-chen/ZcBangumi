import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models/collection.dart';
import '../pages/subject_page.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';

enum _SortMode {
  updatedAt('最近操作'),
  rateDesc('评分从高到低'),
  rateAsc('评分从低到高'),
  nameAsc('名称排序');

  final String label;
  const _SortMode(this.label);
}

class CollectionListPage extends StatefulWidget {
  final String username;
  final int initialSubjectType;
  final int initialCollectionType;

  const CollectionListPage({
    super.key,
    required this.username,
    this.initialSubjectType = BgmConst.subjectAnime,
    this.initialCollectionType = BgmConst.collectionDoing,
  });

  @override
  State<CollectionListPage> createState() => _CollectionListPageState();
}

class _CollectionListPageState extends State<CollectionListPage> {
  late int _subjectType;
  late int _collectionType;
  _SortMode _sortMode = _SortMode.updatedAt;

  List<UserCollection> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _total = 0;
  int _offset = 0;
  static const _pageSize = 30;

  static const _subjectTypes = [
    (type: BgmConst.subjectAnime, label: '动画', icon: Icons.movie_outlined),
    (
      type: BgmConst.subjectGame,
      label: '游戏',
      icon: Icons.sports_esports_outlined,
    ),
    (type: BgmConst.subjectBook, label: '书籍', icon: Icons.menu_book_outlined),
    (type: BgmConst.subjectMusic, label: '音乐', icon: Icons.music_note_outlined),
    (type: BgmConst.subjectReal, label: '三次元', icon: Icons.live_tv_outlined),
  ];

  static const _collectionTypes = [
    BgmConst.collectionDoing,
    BgmConst.collectionWish,
    BgmConst.collectionDone,
    BgmConst.collectionOnHold,
    BgmConst.collectionDropped,
  ];

  StorageService get _storage => context.read<StorageService>();
  String get _cacheKey =>
      'collection_list_${widget.username}_${_subjectType}_$_collectionType';

  @override
  void initState() {
    super.initState();
    _subjectType = widget.initialSubjectType;
    _collectionType = widget.initialCollectionType;
    _loadData();
  }

  Future<void> _loadData({bool refresh = true}) async {
    if (refresh) {
      if (_items.isEmpty) {
        final cached = _storage.getCache(_cacheKey);
        if (cached is List && cached.isNotEmpty) {
          try {
            _items = cached
                .map((e) => UserCollection.fromJson(e as Map<String, dynamic>))
                .toList();
          } catch (_) {}
        }
      }
      setState(() {
        _loading = _items.isEmpty;
        _error = null;
        _offset = 0;
      });
    }

    final api = context.read<ApiClient>();
    try {
      final result = await api.getUserCollections(
        username: widget.username,
        subjectType: _subjectType,
        collectionType: _collectionType,
        limit: _pageSize,
        offset: _offset,
      );
      setState(() {
        if (refresh) {
          _items = result.data;
        } else {
          _items = [..._items, ...result.data];
        }
        _total = result.total;
        _error = null;
      });
      if (refresh) {
        _storage.setCache(_cacheKey, _items.map((e) => e.toJson()).toList());
      }
    } catch (e) {
      if (_items.isEmpty) {
        setState(() => _error = '加载失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _items.length >= _total) {
      return;
    }
    setState(() => _loadingMore = true);
    _offset = _items.length;
    await _loadData(refresh: false);
  }

  void _switchSubjectType(int type) {
    if (_subjectType == type) {
      return;
    }
    setState(() {
      _subjectType = type;
      _items = [];
      _total = 0;
    });
    _loadData();
  }

  void _switchCollectionType(int type) {
    if (_collectionType == type) {
      return;
    }
    setState(() {
      _collectionType = type;
      _items = [];
      _total = 0;
    });
    _loadData();
  }

  void _switchSort(_SortMode mode) {
    if (_sortMode == mode) {
      return;
    }
    setState(() => _sortMode = mode);
  }

  int get _selectedSubjectIndex {
    final index = _subjectTypes.indexWhere((t) => t.type == _subjectType);
    return index >= 0 ? index : 0;
  }

  List<UserCollection> get _sortedItems {
    final list = List<UserCollection>.from(_items);
    switch (_sortMode) {
      case _SortMode.updatedAt:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      case _SortMode.rateDesc:
        list.sort((a, b) {
          final cmp = b.rate.compareTo(a.rate);
          return cmp != 0 ? cmp : b.updatedAt.compareTo(a.updatedAt);
        });
        break;
      case _SortMode.rateAsc:
        list.sort((a, b) {
          final cmp = a.rate.compareTo(b.rate);
          return cmp != 0 ? cmp : b.updatedAt.compareTo(a.updatedAt);
        });
        break;
      case _SortMode.nameAsc:
        list.sort((a, b) {
          final nameA = a.subject?.displayName ?? '';
          final nameB = b.subject?.displayName ?? '';
          return nameA.compareTo(nameB);
        });
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final collectionLabel = BgmConst.collectionLabel(
      _collectionType,
      subjectType: _subjectType,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(collectionLabel),
        centerTitle: false,
        actions: [
          PopupMenuButton<_SortMode>(
            icon: const Icon(Icons.sort),
            tooltip: '排序',
            onSelected: _switchSort,
            itemBuilder: (ctx) => _SortMode.values
                .map(
                  (m) => PopupMenuItem(
                    value: m,
                    child: Row(
                      children: [
                        if (_sortMode == m)
                          Icon(
                            Icons.check,
                            size: 18,
                            color: colorScheme.primary,
                          )
                        else
                          const SizedBox(width: 18),
                        const SizedBox(width: 8),
                        Text(m.label),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
      body: isLandscape
          ? Row(
              children: [
                SafeArea(
                  right: false,
                  child: NavigationRail(
                    selectedIndex: _selectedSubjectIndex,
                    onDestinationSelected: (index) {
                      _switchSubjectType(_subjectTypes[index].type);
                    },
                    labelType: NavigationRailLabelType.all,
                    backgroundColor: colorScheme.surface,
                    indicatorColor: colorScheme.primaryContainer,
                    destinations: _subjectTypes
                        .map(
                          (t) => NavigationRailDestination(
                            icon: Icon(t.icon),
                            label: Text(t.label),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: _buildPageContent(
                    colorScheme,
                    showSubjectTypeBar: false,
                  ),
                ),
              ],
            )
          : _buildPageContent(colorScheme, showSubjectTypeBar: true),
    );
  }

  Widget _buildPageContent(
    ColorScheme colorScheme, {
    required bool showSubjectTypeBar,
  }) {
    return Column(
      children: [
        if (showSubjectTypeBar) _buildSubjectTypeBar(colorScheme),
        _buildCollectionTypeBar(colorScheme),
        Expanded(child: _buildList(colorScheme)),
      ],
    );
  }

  Widget _buildSubjectTypeBar(ColorScheme colorScheme) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: _subjectTypes.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final t = _subjectTypes[i];
          final selected = _subjectType == t.type;
          return ChoiceChip(
            label: Text(t.label),
            avatar: Icon(t.icon, size: 16),
            selected: selected,
            onSelected: (_) => _switchSubjectType(t.type),
            visualDensity: VisualDensity.compact,
            showCheckmark: false,
          );
        },
      ),
    );
  }

  Widget _buildCollectionTypeBar(ColorScheme colorScheme) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: _collectionTypes.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final ct = _collectionTypes[i];
          final label = BgmConst.collectionLabel(ct, subjectType: _subjectType);
          final selected = _collectionType == ct;
          return FilterChip(
            label: Text(label, style: const TextStyle(fontSize: 13)),
            selected: selected,
            onSelected: (_) => _switchCollectionType(ct),
            visualDensity: VisualDensity.compact,
            showCheckmark: false,
          );
        },
      ),
    );
  }

  Widget _buildList(ColorScheme colorScheme) {
    if (_loading && _items.isEmpty) {
      return _buildCollectionSkeletonList(colorScheme);
    }

    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _loadData, child: const Text('重试')),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              '暂无收藏',
              style: TextStyle(fontSize: 15, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    final sorted = _sortedItems;
    final hasMore = _items.length < _total;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: sorted.length + (hasMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i == sorted.length) {
            if (!_loadingMore) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _loadMore();
              });
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
          return _CollectionItemCard(
            collection: sorted[i],
            subjectType: _subjectType,
          );
        },
      ),
    );
  }

  Widget _buildCollectionSkeletonList(ColorScheme colorScheme) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 0),
      itemBuilder: (context, index) =>
          _buildCollectionSkeletonCard(colorScheme),
    );
  }

  Widget _buildCollectionSkeletonCard(ColorScheme colorScheme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 80,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 150,
                    height: 14,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
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
                    width: 180,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: List.generate(
                      3,
                      (_) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Container(
                          width: 46,
                          height: 18,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionItemCard extends StatelessWidget {
  final UserCollection collection;
  final int subjectType;

  const _CollectionItemCard({
    required this.collection,
    required this.subjectType,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subject = collection.subject;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openSubjectPage(context, collection.subjectId),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 56,
                  height: 80,
                  child: subject?.images?.common.isNotEmpty == true
                      ? CachedNetworkImage(
                          imageUrl: subject!.images!.common,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: colorScheme.surfaceContainerHighest,
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.image, size: 24),
                          ),
                        )
                      : Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.image, size: 24),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 80,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject?.displayName ?? 'ID: ${collection.subjectId}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      _buildBottomRow(context, colorScheme),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomRow(BuildContext context, ColorScheme colorScheme) {
    final subject = collection.subject;

    return Row(
      children: [
        if (collection.rate > 0) ...[
          Icon(Icons.star_rounded, size: 14, color: Colors.amber[700]),
          const SizedBox(width: 2),
          Text(
            '${collection.rate}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.amber[800],
            ),
          ),
          const SizedBox(width: 10),
        ],
        if (subject != null && subject.score > 0) ...[
          Icon(Icons.people_outline, size: 13, color: Colors.grey[500]),
          const SizedBox(width: 2),
          Text(
            subject.score.toStringAsFixed(1),
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          const SizedBox(width: 10),
        ],
        if (subject != null && subject.rank > 0) ...[
          Text(
            '#${subject.rank}',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
        ],
        const Spacer(),
        if (collection.epStatus > 0) ...[
          Text(
            'EP ${collection.epStatus}',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          if (subject != null && subject.eps > 0)
            Text(
              ' / ${subject.eps}',
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
        ],
        if (collection.epStatus == 0)
          Text(
            _formatDate(collection.updatedAt),
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  void _openSubjectPage(BuildContext context, int subjectId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SubjectPage(subjectId: subjectId)),
    );
  }
}
