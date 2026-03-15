import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/timeline.dart';
import '../constants.dart';
import '../pages/subject_page.dart';
import '../providers/auth_provider.dart';
import '../providers/app_state_provider.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';

/// 动态页面标签类型
enum _TimelineTab { global, friends, mine }

/// 动态页面 - 全站 / 好友 / 我的
class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key});

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  _TimelineTab _currentTab = _TimelineTab.global;
  AuthProvider? _authProvider;
  bool _wasLoggedIn = false;

  // ==================== 全站动态 ====================
  List<TimelineItem> _globalItems = [];
  bool _globalLoading = false;
  String? _globalError;
  int _globalPage = 1;
  bool _globalLoadingMore = false;

  // ==================== 好友动态 ====================
  List<TimelineItem> _friendItems = [];
  bool _friendLoading = false;
  String? _friendError;
  int? _friendUntil; // 游标分页：上一页最后一条的 createdAt
  bool _friendLoadingMore = false;
  bool _friendHasMore = true;

  // ==================== 我的动态 ====================
  List<TimelineItem> _myItems = [];
  bool _myLoading = false;
  String? _myError;
  int? _myUntil; // 游标分页
  bool _myLoadingMore = false;
  bool _myHasMore = true;

  @override
  void initState() {
    super.initState();
    // 从 AppStateProvider 恢复之前选中的标签
    final appState = context.read<AppStateProvider>();
    _currentTab = _TimelineTab.values[appState.timelineTabIndex];
    _ensureLoadedForTab(_currentTab);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (!identical(_authProvider, auth)) {
      _authProvider?.removeListener(_handleAuthChanged);
      _authProvider = auth;
      _wasLoggedIn = auth.isLoggedIn;
      _authProvider?.addListener(_handleAuthChanged);
    }
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_handleAuthChanged);
    super.dispose();
  }

  void _handleAuthChanged() {
    final auth = _authProvider;
    if (auth == null) return;

    final isLoggedIn = auth.isLoggedIn;
    final becameLoggedIn = !_wasLoggedIn && isLoggedIn;
    _wasLoggedIn = isLoggedIn;

    if (!becameLoggedIn || !mounted) return;
    _ensureLoadedForTab(_currentTab);
  }

  void _ensureLoadedForTab(_TimelineTab tab) {
    switch (tab) {
      case _TimelineTab.global:
        if (_globalItems.isEmpty && !_globalLoading) {
          _loadGlobal();
        }
        break;
      case _TimelineTab.friends:
        final auth = context.read<AuthProvider>();
        if (auth.isLoggedIn && _friendItems.isEmpty && !_friendLoading) {
          _loadFriends();
        }
        break;
      case _TimelineTab.mine:
        final auth = context.read<AuthProvider>();
        if (auth.isLoggedIn &&
            auth.username != null &&
            _myItems.isEmpty &&
            !_myLoading) {
          _loadMine();
        }
        break;
    }
  }

  // ========== 全站动态 加载 ==========

  /// 从缓存还原 TimelineItem 列表
  List<TimelineItem> _parseCachedTimeline(dynamic cached) {
    if (cached is! List) return [];
    try {
      return cached
          .map((e) => TimelineItem.fromCacheJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  StorageService get _storage => context.read<StorageService>();

  Future<void> _loadGlobal({bool refresh = true}) async {
    if (refresh) {
      // 无感加载：若列表为空则先从缓存恢复
      if (_globalItems.isEmpty) {
        final cached = _parseCachedTimeline(
          _storage.getCache('timeline_global'),
        );
        if (cached.isNotEmpty) {
          _globalItems = cached;
        }
      }
      setState(() {
        _globalLoading = _globalItems.isEmpty; // 有缓存则不显示转圈
        _globalError = null;
        _globalPage = 1;
      });
    }

    final api = context.read<ApiClient>();
    try {
      final items = await api.getTimeline(page: _globalPage);
      setState(() {
        if (refresh) {
          _globalItems = items;
        } else {
          _globalItems = [..._globalItems, ...items];
        }
        _globalError = null;
      });
      // 缓存第一页
      if (refresh) {
        _storage.setCache(
          'timeline_global',
          items.map((e) => e.toJson()).toList(),
        );
      }
    } catch (e) {
      // 有缓存数据时静默失败
      if (_globalItems.isEmpty) {
        setState(() => _globalError = '加载失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _globalLoading = false;
          _globalLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMoreGlobal() async {
    if (_globalLoadingMore) return;
    setState(() => _globalLoadingMore = true);
    _globalPage++;
    await _loadGlobal(refresh: false);
  }

  // ========== 好友动态 加载 ==========

  Future<void> _loadFriends({bool refresh = true}) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return;

    if (refresh) {
      // 无感加载：先从缓存恢复
      if (_friendItems.isEmpty) {
        final cached = _parseCachedTimeline(
          _storage.getCache('timeline_friends'),
        );
        if (cached.isNotEmpty) {
          _friendItems = cached;
        }
      }
      setState(() {
        _friendLoading = _friendItems.isEmpty;
        _friendError = null;
        _friendUntil = null;
        _friendHasMore = true;
      });
    }

    final api = context.read<ApiClient>();
    try {
      final items = await api.getFriendTimeline(limit: 20, until: _friendUntil);
      setState(() {
        if (refresh) {
          _friendItems = items;
        } else {
          _friendItems = [..._friendItems, ...items];
        }
        _friendError = null;
        _friendHasMore = items.isNotEmpty;
        if (items.isNotEmpty && items.last.createdAt != null) {
          _friendUntil = items.last.createdAt;
        }
      });
      if (refresh) {
        _storage.setCache(
          'timeline_friends',
          items.map((e) => e.toJson()).toList(),
        );
      }
    } catch (e) {
      if (_friendItems.isEmpty) {
        setState(() => _friendError = '加载失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _friendLoading = false;
          _friendLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMoreFriends() async {
    if (_friendLoadingMore || !_friendHasMore) return;
    setState(() => _friendLoadingMore = true);
    await _loadFriends(refresh: false);
  }

  // ========== 我的动态 加载 ==========

  Future<void> _loadMine({bool refresh = true}) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn || auth.username == null) return;

    if (refresh) {
      // 无感加载：先从缓存恢复
      if (_myItems.isEmpty) {
        final cached = _parseCachedTimeline(
          _storage.getCache('timeline_mine_${auth.username}'),
        );
        if (cached.isNotEmpty) {
          _myItems = cached;
        }
      }
      setState(() {
        _myLoading = _myItems.isEmpty;
        _myError = null;
        _myUntil = null;
        _myHasMore = true;
      });
    }

    final api = context.read<ApiClient>();
    try {
      final items = await api.getUserTimeline(
        username: auth.username!,
        limit: 20,
        until: _myUntil,
        fallbackUser: {
          'username': auth.username ?? '',
          'nickname': auth.user?.nickname ?? auth.username ?? '',
          'avatar': {
            'large': auth.user?.avatar.large ?? '',
            'medium': auth.user?.avatar.medium ?? '',
            'small': auth.user?.avatar.small ?? '',
          },
        },
      );
      setState(() {
        if (refresh) {
          _myItems = items;
        } else {
          _myItems = [..._myItems, ...items];
        }
        _myError = null;
        _myHasMore = items.isNotEmpty;
        if (items.isNotEmpty && items.last.createdAt != null) {
          _myUntil = items.last.createdAt;
        }
      });
      if (refresh) {
        _storage.setCache(
          'timeline_mine_${auth.username}',
          items.map((e) => e.toJson()).toList(),
        );
      }
    } catch (e) {
      if (_myItems.isEmpty) {
        setState(() => _myError = '加载失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _myLoading = false;
          _myLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMoreMine() async {
    if (_myLoadingMore || !_myHasMore) return;
    setState(() => _myLoadingMore = true);
    await _loadMine(refresh: false);
  }

  // ========== 切换标签 ==========

  void _onTabChanged(_TimelineTab tab) {
    if (_currentTab == tab) return;
    setState(() => _currentTab = tab);

    // 保存选择到 AppStateProvider
    context.read<AppStateProvider>().setTimelineTabIndex(tab.index);

    _ensureLoadedForTab(tab);
  }

  Future<void> _refreshCurrentTab() {
    switch (_currentTab) {
      case _TimelineTab.global:
        return _loadGlobal();
      case _TimelineTab.friends:
        return _loadFriends();
      case _TimelineTab.mine:
        return _loadMine();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        title: const Text('动态'),
        centerTitle: false,
        actions: [
          if (isLandscape)
            IconButton(
              tooltip: '刷新当前列表',
              onPressed: _refreshCurrentTab,
              icon: const Icon(Icons.refresh_rounded),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<_TimelineTab>(
              segments: const [
                ButtonSegment(value: _TimelineTab.global, label: Text('全站')),
                ButtonSegment(value: _TimelineTab.friends, label: Text('好友')),
                ButtonSegment(value: _TimelineTab.mine, label: Text('我的')),
              ],
              selected: {_currentTab},
              onSelectionChanged: (val) => _onTabChanged(val.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: WidgetStatePropertyAll(
                  TextStyle(fontSize: 13, color: colorScheme.onSurface),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_currentTab) {
      case _TimelineTab.global:
        return _buildTimelineList(
          items: _globalItems,
          loading: _globalLoading,
          error: _globalError,
          loadingMore: _globalLoadingMore,
          onRefresh: _loadGlobal,
          onLoadMore: _loadMoreGlobal,
          requireLogin: false,
        );
      case _TimelineTab.friends:
        return _buildTimelineList(
          items: _friendItems,
          loading: _friendLoading,
          error: _friendError,
          loadingMore: _friendLoadingMore,
          onRefresh: () => _loadFriends(),
          onLoadMore: _loadMoreFriends,
          requireLogin: true,
          emptyText: '暂无好友动态',
        );
      case _TimelineTab.mine:
        return _buildTimelineList(
          items: _myItems,
          loading: _myLoading,
          error: _myError,
          loadingMore: _myLoadingMore,
          onRefresh: () => _loadMine(),
          onLoadMore: _loadMoreMine,
          requireLogin: true,
          emptyText: '暂无我的动态',
        );
    }
  }

  Widget _buildTimelineList({
    required List<TimelineItem> items,
    required bool loading,
    required String? error,
    required bool loadingMore,
    required Future<void> Function() onRefresh,
    required Future<void> Function()? onLoadMore,
    required bool requireLogin,
    String emptyText = '暂无动态',
  }) {
    // 需要登陆的页面，检查初始化状态
    if (requireLogin) {
      final auth = context.watch<AuthProvider>();

      // 还在初始化中 -> 显示骨架屏
      if (!auth.initialized) {
        return _buildTimelineSkeletonList();
      }

      // 已初始化但未登陆，且无缓存数据 -> 显示登陆提示
      if (!auth.isLoggedIn && items.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_outline, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 12),
              Text(
                '登录后查看动态',
                style: TextStyle(fontSize: 16, color: Colors.grey[500]),
              ),
            ],
          ),
        );
      }
    }

    if (loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null && items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(error, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRefresh, child: const Text('重试')),
          ],
        ),
      );
    }

    if (items.isEmpty) {
      return Center(child: Text(emptyText));
    }

    final hasLoadMore = onLoadMore != null;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length + (hasLoadMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (hasLoadMore && index == items.length) {
            // 自动加载更多
            if (!loadingMore) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                onLoadMore.call();
              });
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return _TimelineFeedItem(item: items[index]);
        },
      ),
    );
  }

  /// 动态列表的骨架屏
  Widget _buildTimelineSkeletonList() {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 3, // 显示3个骨架项
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧头像骨架
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              // 右侧内容骨架
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 用户名行
                    Container(
                      width: 120,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 动作描述行
                    Container(
                      width: 200,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 时间行
                    Container(
                      width: 80,
                      height: 8,
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
      },
    );
  }
}

/// 单条"谁做了什么"动态卡片
class _TimelineFeedItem extends StatelessWidget {
  final TimelineItem item;

  const _TimelineFeedItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧头像
          GestureDetector(
            onTap: () => _openUserPage(item.username),
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: item.avatarUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: item.avatarUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.person, size: 20),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.person, size: 20),
                          ),
                        )
                      : Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.person, size: 20),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 右侧内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildActionLine(context),
                if (item.subjectId != null || item.subjectCoverUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _buildSubjectCard(context),
                  ),
                const SizedBox(height: 4),
                Divider(
                  height: 12,
                  thickness: 0.5,
                  color: colorScheme.outlineVariant.withAlpha(80),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionLine(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 0,
      children: [
        GestureDetector(
          onTap: () => _openUserPage(item.username),
          child: Text(
            item.nickname,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
        ),
        Text(
          ' ${item.actionText} ',
          style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
        ),
        if (item.targetText != null && item.targetText!.isNotEmpty)
          Text(
            item.targetText!,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colorScheme.primary,
            ),
          ),
        Text(
          '  ${item.timeText}',
          style: TextStyle(fontSize: 12, color: Colors.grey[400]),
        ),
      ],
    );
  }

  Widget _buildSubjectCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () {
        if (item.subjectId != null) _openSubjectPage(context, item.subjectId!);
      },
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: colorScheme.outlineVariant.withAlpha(80),
            width: 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.subjectCoverUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10),
                ),
                child: SizedBox(
                  width: 50,
                  height: 70,
                  child: CachedNetworkImage(
                    imageUrl: item.subjectCoverUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        Container(color: colorScheme.surfaceContainerHighest),
                    errorWidget: (context, url, error) => Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.movie, size: 20),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displaySubjectName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.subjectInfo != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.subjectInfo!,
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (item.score != null || item.rank != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (item.rank != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                item.rank!,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (item.score != null) ...[
                            Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: Colors.amber[700],
                            ),
                            const SizedBox(width: 2),
                            Text(
                              item.score!.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber[800],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openUserPage(String username) async {
    final uri = Uri.parse('${BgmConst.webBaseUrl}/user/$username');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openSubjectPage(BuildContext context, int subjectId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SubjectPage(subjectId: subjectId)),
    );
  }
}
