import 'dart:async';
import 'dart:collection';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bangumi_index.dart';
import '../pages/index_page.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';

typedef BangumiIndexPageLoader =
    Future<PagedResult<BangumiIndexSummary>> Function(int limit, int offset);

class BangumiIndexListView extends StatefulWidget {
  final BangumiIndexPageLoader loadPage;
  final String cacheKey;
  final String emptyText;
  final EdgeInsetsGeometry padding;
  final bool hideSystemIndexes;
  final Set<int> hiddenIndexIds;
  final String? viewerUsername;
  final String? fallbackAuthorUsername;
  final ScrollPhysics? physics;
  final bool shrinkWrap;

  const BangumiIndexListView({
    super.key,
    required this.loadPage,
    required this.cacheKey,
    this.emptyText = '暂无相关目录',
    this.padding = const EdgeInsets.all(12),
    this.hideSystemIndexes = true,
    this.hiddenIndexIds = const {},
    this.viewerUsername,
    this.fallbackAuthorUsername,
    this.physics,
    this.shrinkWrap = false,
  });

  @override
  State<BangumiIndexListView> createState() => BangumiIndexListViewState();
}

class BangumiIndexListViewState extends State<BangumiIndexListView> {
  static const _pageSize = 30;
  final List<BangumiIndexSummary> _items = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  String? _error;
  int _nextOffset = 0;
  bool _hasMore = true;
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  @override
  void didUpdateWidget(covariant BangumiIndexListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey) {
      _requestVersion++;
      setState(() {
        _items.clear();
        _nextOffset = 0;
        _hasMore = true;
        _loading = true;
        _refreshing = false;
        _loadingMore = false;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
    } else if (oldWidget.hideSystemIndexes != widget.hideSystemIndexes ||
        !setEquals(oldWidget.hiddenIndexIds, widget.hiddenIndexIds)) {
      setState(() => _items.removeWhere(_shouldHide));
    }
  }

  Future<void> refresh() async {
    if (!mounted) return;
    final requestVersion = ++_requestVersion;
    final cacheKey = widget.cacheKey;
    _refreshing = true;
    _loadingMore = false;
    final storage = context.read<StorageService>();
    if (_items.isEmpty) {
      final cached = storage.getCache(cacheKey);
      if (cached is List) {
        for (final raw in cached.whereType<Map>()) {
          try {
            final item = BangumiIndexSummary.fromJson(
              Map<String, dynamic>.from(raw),
            );
            if (!_shouldHide(item)) _items.add(item);
          } catch (_) {}
        }
      }
    }
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      var result = await widget.loadPage(_pageSize, 0);
      final visible = result.data.where((item) => !_shouldHide(item)).toList();
      var nextOffset = _pageSize;
      var total = result.total;
      while (visible.isEmpty && nextOffset < total) {
        result = await widget.loadPage(_pageSize, nextOffset);
        visible.addAll(result.data.where((item) => !_shouldHide(item)));
        nextOffset += _pageSize;
        total = result.total;
      }
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _items
          ..clear()
          ..addAll(visible);
        _nextOffset = nextOffset;
        _hasMore = _nextOffset < total;
      });
      await _writeCache(storage, cacheKey: cacheKey);
    } catch (error) {
      if (mounted && requestVersion == _requestVersion && _items.isEmpty) {
        setState(() => _error = '$error');
      } else if (mounted && requestVersion == _requestVersion) {
        setState(() => _hasMore = false);
      }
    } finally {
      if (mounted && requestVersion == _requestVersion) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  bool _shouldHide(BangumiIndexSummary item) =>
      widget.hiddenIndexIds.contains(item.id) ||
      (widget.hideSystemIndexes && item.isSystemSyncIndex);

  Future<void> loadMore() async {
    if (_loading || _refreshing || _loadingMore || !_hasMore) return;
    final requestVersion = _requestVersion;
    final cacheKey = widget.cacheKey;
    setState(() => _loadingMore = true);
    try {
      final additions = <BangumiIndexSummary>[];
      var nextOffset = _nextOffset;
      var total = _nextOffset + 1;
      do {
        final result = await widget.loadPage(_pageSize, nextOffset);
        additions.addAll(
          result.data.where(
            (item) =>
                !_shouldHide(item) &&
                !_items.any((existing) => existing.id == item.id) &&
                !additions.any((existing) => existing.id == item.id),
          ),
        );
        nextOffset += _pageSize;
        total = result.total;
      } while (additions.isEmpty && nextOffset < total);
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _items.addAll(additions);
        _nextOffset = nextOffset;
        _hasMore = _nextOffset < total;
      });
      await _writeCache(context.read<StorageService>(), cacheKey: cacheKey);
    } catch (error) {
      if (mounted && requestVersion == _requestVersion) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted && requestVersion == _requestVersion) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _writeCache(StorageService storage, {required String cacheKey}) {
    return storage.setCache(
      cacheKey,
      _items.map((item) => item.toJson()).toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return _IndexListMessage(
        icon: Icons.cloud_off_outlined,
        message: _error!,
        action: TextButton(onPressed: refresh, child: const Text('重试')),
      );
    }
    if (_items.isEmpty) {
      return _IndexListMessage(
        icon: Icons.format_list_bulleted_rounded,
        message: widget.emptyText,
        action: TextButton(onPressed: refresh, child: const Text('刷新')),
      );
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 320) loadMore();
          return false;
        },
        child: ListView.separated(
          padding: widget.padding,
          physics: widget.physics ?? const AlwaysScrollableScrollPhysics(),
          shrinkWrap: widget.shrinkWrap,
          itemCount: _items.length + (_loadingMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index >= _items.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final item = _items[index];
            return BangumiIndexCard(
              index: item,
              viewerUsername: widget.viewerUsername,
              fallbackAuthorUsername: widget.fallbackAuthorUsername,
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BangumiIndexPage(indexId: item.id),
                  ),
                );
                if (mounted) await refresh();
              },
            );
          },
        ),
      ),
    );
  }
}

class BangumiIndexCard extends StatefulWidget {
  final BangumiIndexSummary index;
  final VoidCallback? onTap;
  final String? viewerUsername;
  final String? fallbackAuthorUsername;

  const BangumiIndexCard({
    super.key,
    required this.index,
    this.onTap,
    this.viewerUsername,
    this.fallbackAuthorUsername,
  });

  @override
  State<BangumiIndexCard> createState() => _BangumiIndexCardState();
}

class _BangumiIndexCardState extends State<BangumiIndexCard> {
  static const _maxCachedAuthors = 200;
  static const _maxConcurrentAuthorLoads = 4;
  static final Map<String, Map<String, dynamic>> _authors = {};
  static final Map<String, Future<Map<String, dynamic>?>> _pendingAuthors = {};
  static final Queue<Completer<void>> _authorLoadWaiters = Queue();
  static int _activeAuthorLoads = 0;
  Map<String, dynamic>? _author;

  String get _authorCacheKey =>
      bangumiIndexDetailCacheKey(widget.index.id, widget.viewerUsername);

  @override
  void initState() {
    super.initState();
    _author = widget.index.user ?? _authors[_authorCacheKey];
    if (_author == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadAuthor());
    }
  }

  @override
  void didUpdateWidget(covariant BangumiIndexCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index.id != widget.index.id ||
        oldWidget.index.user != widget.index.user ||
        oldWidget.viewerUsername != widget.viewerUsername ||
        oldWidget.fallbackAuthorUsername != widget.fallbackAuthorUsername) {
      _author = widget.index.user ?? _authors[_authorCacheKey];
      if (_author == null) _loadAuthor();
    }
  }

  Future<void> _loadAuthor() async {
    if (!mounted || _author != null || widget.index.id <= 0) {
      return;
    }
    final key = _authorCacheKey;
    final api = context.read<ApiClient>();
    final future = _pendingAuthors.putIfAbsent(key, () async {
      return _withAuthorLoadSlot(() async {
        try {
          return (await api.getBangumiIndex(widget.index.id)).user;
        } catch (_) {
          return null;
        }
      });
    });
    final author = await future;
    _pendingAuthors.remove(key);
    if (author != null) {
      _authors[key] = author;
      if (_authors.length > _maxCachedAuthors) {
        _authors.remove(_authors.keys.first);
      }
    }
    if (mounted && key == _authorCacheKey) {
      setState(() => _author = author);
    }
  }

  static Future<T> _withAuthorLoadSlot<T>(Future<T> Function() load) async {
    if (_activeAuthorLoads >= _maxConcurrentAuthorLoads) {
      final waiter = Completer<void>();
      _authorLoadWaiters.add(waiter);
      await waiter.future;
    } else {
      _activeAuthorLoads++;
    }
    try {
      return await load();
    } finally {
      if (_authorLoadWaiters.isNotEmpty) {
        _authorLoadWaiters.removeFirst().complete();
      } else {
        _activeAuthorLoads--;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.index;
    final colors = Theme.of(context).colorScheme;
    final avatar = _authorAvatar;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: colors.surfaceContainerHighest,
                foregroundImage: avatar.isEmpty
                    ? null
                    : CachedNetworkImageProvider(avatar),
                child: avatar.isEmpty
                    ? const Icon(Icons.person_outline_rounded)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            index.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (index.isPrivate)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(Icons.lock_outline_rounded, size: 16),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'by $_authorName · ${index.total} 项 · ${_date(index.updatedAt)}更新',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  String get _authorName {
    final nickname = '${_author?['nickname'] ?? ''}'.trim();
    if (nickname.isNotEmpty) return nickname;
    final username = '${_author?['username'] ?? ''}'.trim();
    if (username.isNotEmpty) return username;
    final fallback = widget.fallbackAuthorUsername?.trim() ?? '';
    return fallback.isNotEmpty ? fallback : '用户 #${widget.index.uid}';
  }

  String get _authorAvatar {
    final raw = _author?['avatar'];
    final avatar = raw is Map ? Map<String, dynamic>.from(raw) : null;
    return '${avatar?['medium'] ?? avatar?['small'] ?? avatar?['large'] ?? ''}';
  }

  static String _date(DateTime value) {
    if (value.millisecondsSinceEpoch == 0) return '未知时间';
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}

class _IndexListMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final Widget action;

  const _IndexListMessage({
    required this.icon,
    required this.message,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            action,
          ],
        ),
      ),
    );
  }
}
