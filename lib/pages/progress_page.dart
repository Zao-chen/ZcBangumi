import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/collection.dart';
import '../pages/search_page.dart';
import '../pages/subject_page.dart';
import '../providers/app_state_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/collection_provider.dart';
import '../widgets/progress_grid.dart';

/// 进度页面 - 分为动画、游戏、书籍三个标签
class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = [
    _TabConfig(
      type: BgmConst.subjectAnime,
      label: '动画',
      icon: Icons.movie_outlined,
    ),
    _TabConfig(
      type: BgmConst.subjectGame,
      label: '游戏',
      icon: Icons.sports_esports_outlined,
    ),
    _TabConfig(
      type: BgmConst.subjectBook,
      label: '书籍',
      icon: Icons.menu_book_outlined,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {}); // 触发重建以便子组件加载数据
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 显示搜索页面
  void _showSearchPage(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SearchPage()));
  }

  Future<void> _refreshCurrentTab() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn || auth.username == null) return;
    final forceNetwork = context
        .read<AppStateProvider>()
        .pullToRefreshForceNetwork;

    final subjectType = _tabs[_tabController.index].type;
    await context.read<CollectionProvider>().loadDoingCollections(
      username: auth.username!,
      subjectType: subjectType,
      refresh: true,
      forceNetwork: forceNetwork,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // 初始化中显示骨架屏，避免显示登陆提示
    final isInitializing = !auth.initialized;
    final bodyWidget = isInitializing
        ? (isLandscape
              ? _buildLandscapeInitializingLayout()
              : _buildProgressPageSkeletonList())
        : auth.isLoggedIn
        ? isLandscape
              ? _buildLandscapeLayout()
              : TabBarView(
                  controller: _tabController,
                  children: _tabs
                      .map((t) => _ProgressTabView(subjectType: t.type))
                      .toList(),
                )
        : _buildNotLoggedIn();

    return Scaffold(
      appBar: AppBar(
        title: const Text('进度'),
        centerTitle: false,
        actions: [
          if (isLandscape)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '刷新当前分区',
              onPressed: _refreshCurrentTab,
            ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索条目',
            onPressed: () => _showSearchPage(context),
          ),
        ],
        // TabBar 属于固定元素，初始化阶段也直接显示
        bottom: (!isLandscape)
            ? TabBar(
                controller: _tabController,
                tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                indicatorSize: TabBarIndicatorSize.label,
              )
            : null,
      ),
      body: bodyWidget,
    );
  }

  Widget _buildLandscapeLayout() {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        NavigationRail(
          selectedIndex: _tabController.index,
          onDestinationSelected: _tabController.animateTo,
          backgroundColor: colorScheme.surface,
          indicatorColor: colorScheme.primaryContainer,
          labelType: NavigationRailLabelType.all,
          destinations: _tabs
              .map(
                (tab) => NavigationRailDestination(
                  icon: Icon(tab.icon),
                  label: Text(tab.label),
                ),
              )
              .toList(),
        ),
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _tabs
                .map((t) => _ProgressTabView(subjectType: t.type))
                .toList(),
          ),
        ),
      ],
    );
  }

  /// 横屏初始化布局：固定 NavigationRail 保持不变，仅内容区骨架化
  Widget _buildLandscapeInitializingLayout() {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        NavigationRail(
          selectedIndex: _tabController.index,
          onDestinationSelected: _tabController.animateTo,
          backgroundColor: colorScheme.surface,
          indicatorColor: colorScheme.primaryContainer,
          labelType: NavigationRailLabelType.all,
          destinations: _tabs
              .map(
                (tab) => NavigationRailDestination(
                  icon: Icon(tab.icon),
                  label: Text(tab.label),
                ),
              )
              .toList(),
        ),
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(child: _buildProgressPageSkeletonList()),
      ],
    );
  }

  Widget _buildNotLoggedIn() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            '请先登录以查看进度',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  /// ProgressPage 初始化时的骨架屏（顶层页面级别）
  Widget _buildProgressPageSkeletonList() {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 3, // 显示3个骨架项
      itemBuilder: (context, index) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左侧图片骨架
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 56,
                    height: 80,
                    color: colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(width: 12),
                // 右侧信息骨架
                Expanded(
                  child: SizedBox(
                    height: 80,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 标题行
                        Container(
                          width: 150,
                          height: 12,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // 副标题行
                        Container(
                          width: 100,
                          height: 10,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const Spacer(),
                        // 底部信息行
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
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TabConfig {
  final int type;
  final String label;
  final IconData icon;
  const _TabConfig({
    required this.type,
    required this.label,
    required this.icon,
  });
}

/// 单个类型的在看列表 + 点格子
class _ProgressTabView extends StatefulWidget {
  final int subjectType;
  const _ProgressTabView({required this.subjectType});

  @override
  State<_ProgressTabView> createState() => _ProgressTabViewState();
}

class _ProgressTabViewState extends State<_ProgressTabView>
    with AutomaticKeepAliveClientMixin {
  String? _lastUsername;
  AuthProvider? _lastAuthProvider;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();

    // 监听登陆状态变化，如果用户刚登陆就重新加载
    if (auth.isLoggedIn &&
        auth.username != null &&
        _lastUsername != auth.username) {
      _lastUsername = auth.username;
      _loadData();
    }

    // 监听初始化完成，立刻加载最新数据
    if (auth.initialized && !identical(_lastAuthProvider, auth)) {
      _lastAuthProvider = auth;
      if (auth.isLoggedIn && auth.username != null) {
        _loadDataIfNeeded();
      }
    }
  }

  void _loadData() {
    final auth = context.read<AuthProvider>();
    final collectionProvider = context.read<CollectionProvider>();

    // 已登陆：从API加载（自动会先尝试缓存）
    if (auth.isLoggedIn && auth.username != null) {
      collectionProvider.loadDoingCollections(
        username: auth.username!,
        subjectType: widget.subjectType,
      );
    }
  }

  /// 仅在需要时加载（初始化完成但还没加载过）
  void _loadDataIfNeeded() {
    final auth = context.read<AuthProvider>();
    final collectionProvider = context.read<CollectionProvider>();

    if (auth.isLoggedIn && auth.username != null) {
      final collections = collectionProvider.getCollections(widget.subjectType);
      final isLoading = collectionProvider.isLoading(widget.subjectType);

      // 如果还没加载过（集合为空且不在加载中），立刻加载
      if (collections.isEmpty && !isLoading) {
        collectionProvider.loadDoingCollections(
          username: auth.username!,
          subjectType: widget.subjectType,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<CollectionProvider>();
    final collections = provider.getCollections(widget.subjectType);
    final isLoading = provider.isLoading(widget.subjectType);
    final error = provider.getError(widget.subjectType);

    // 逻辑：有缓存数据 -> 显示缓存；无缓存且初始化中 -> 显示骨架屏
    final hasCache = collections.isNotEmpty;
    final isInitializing = !auth.initialized;

    // 显示骨架屏的条件：初始化中 且 无缓存
    if (isInitializing && !hasCache) {
      return _buildProgressSkeletonList();
    }

    if (isLoading && collections.isEmpty) {
      return _buildProgressSkeletonList();
    }

    if (error != null && collections.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(error, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _loadData, child: const Text('重试')),
          ],
        ),
      );
    }

    if (collections.isEmpty) {
      final typeName = BgmConst.subjectTypeName(widget.subjectType);
      final statusLabel = BgmConst.collectionLabel(
        BgmConst.collectionDoing,
        subjectType: widget.subjectType,
      );

      // 已初始化但未登陆 -> 显示登陆提示
      if (!auth.isLoggedIn) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 12),
              Text(
                '登录后查看进度',
                style: TextStyle(fontSize: 16, color: Colors.grey[500]),
              ),
            ],
          ),
        );
      }

      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              '没有$statusLabel的$typeName',
              style: TextStyle(fontSize: 15, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        if (auth.isLoggedIn && auth.username != null) {
          final forceNetwork = context
              .read<AppStateProvider>()
              .pullToRefreshForceNetwork;
          await provider.loadDoingCollections(
            username: auth.username!,
            subjectType: widget.subjectType,
            refresh: true,
            forceNetwork: forceNetwork,
          );
        }
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: collections.length,
        itemBuilder: (context, index) {
          return _CollectionProgressCard(collection: collections[index]);
        },
      ),
    );
  }

  /// 进度列表的骨架屏
  Widget _buildProgressSkeletonList() {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 3, // 显示3个骨架项
      itemBuilder: (context, index) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左侧图片骨架
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 56,
                    height: 80,
                    color: colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(width: 12),
                // 右侧信息骨架
                Expanded(
                  child: SizedBox(
                    height: 80,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 标题行
                        Container(
                          width: 150,
                          height: 12,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // 副标题行
                        Container(
                          width: 100,
                          height: 10,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const Spacer(),
                        // 底部信息行
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
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 单个收藏条目的进度卡片（直接展示格子）
class _CollectionProgressCard extends StatefulWidget {
  final UserCollection collection;
  const _CollectionProgressCard({required this.collection});

  @override
  State<_CollectionProgressCard> createState() =>
      _CollectionProgressCardState();
}

class _CollectionProgressCardState extends State<_CollectionProgressCard> {
  @override
  void initState() {
    super.initState();
    // 自动加载章节进度
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CollectionProvider>().loadEpisodeProgress(
        widget.collection.subjectId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final provider = context.watch<CollectionProvider>();
    final appState = context.watch<AppStateProvider>();
    final subject = widget.collection.subject;
    final episodes = provider.getEpisodeProgress(widget.collection.subjectId);
    final epLoading = provider.isEpisodeLoading(widget.collection.subjectId);
    final densityScale = switch (appState.listDensityMode) {
      0 => 0.88,
      2 => 1.12,
      _ => 1.0,
    };
    final horizontalMargin = 12.0 * densityScale;
    final verticalMargin = 5.0 * densityScale;
    final cardPadding = 12.0 * densityScale;
    final coverWidth = 56.0 * densityScale;
    final coverHeight = 80.0 * densityScale;
    final coverRadius = appState.coverCornerRadius;
    final showSecondary = appState.showSecondaryInfo;

    return Card(
      margin: EdgeInsets.symmetric(
        horizontal: horizontalMargin,
        vertical: verticalMargin,
      ),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  SubjectPage(subjectId: widget.collection.subjectId),
            ),
          );
        },
        child: Padding(
          padding: EdgeInsets.all(cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 条目信息栏
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 封面
                  ClipRRect(
                    borderRadius: BorderRadius.circular(coverRadius),
                    child: SizedBox(
                      width: coverWidth,
                      height: coverHeight,
                      child: subject?.images?.grid.isNotEmpty == true
                          ? CachedNetworkImage(
                              imageUrl: subject!.images!.common.isNotEmpty
                                  ? subject.images!.common
                                  : subject.images!.grid,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: colorScheme.surfaceContainerHighest,
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.image, size: 20),
                              ),
                            )
                          : Container(
                              color: colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.image, size: 20),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 标题 + 进度格子
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subject?.displayName ?? '未知条目',
                          style: TextStyle(
                            fontSize: 14 * densityScale,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 4 * densityScale),
                        if (epLoading)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else if (episodes.isNotEmpty ||
                            widget.collection.subjectType ==
                                BgmConst.subjectBook ||
                            widget.collection.subjectType ==
                                BgmConst.subjectGame)
                          ProgressGrid(
                            episodes: episodes,
                            loading: false,
                            useNumberPicker:
                                widget.collection.subjectType ==
                                BgmConst.subjectBook,
                            useCollectionTypePicker:
                                widget.collection.subjectType ==
                                BgmConst.subjectGame,
                            bookCurrentProgress: widget.collection.epStatus,
                            bookMaxProgress: (subject?.eps ?? 0) > 0
                                ? subject!.eps
                                : null,
                            collectionSubjectType:
                                widget.collection.subjectType,
                            collectionType: widget.collection.type,
                            onSetStatus: (episodeId, newType) {
                              provider.setEpisodeStatus(
                                subjectId: widget.collection.subjectId,
                                episodeId: episodeId,
                                newType: newType,
                              );
                            },
                            onWatchUpTo: (sort) {
                              if (episodes.isNotEmpty) {
                                provider.watchUpTo(
                                  subjectId: widget.collection.subjectId,
                                  episodeSort: sort,
                                );
                              } else {
                                provider.setCollectionEpStatus(
                                  subjectId: widget.collection.subjectId,
                                  epStatus: sort,
                                );
                              }
                            },
                            onSetCollectionType: (newType) {
                              provider.setCollectionType(
                                subjectId: widget.collection.subjectId,
                                subjectType: widget.collection.subjectType,
                                newType: newType,
                              );
                            },
                          )
                        else
                          Text(
                            widget.collection.epStatus > 0
                                ? 'EP ${widget.collection.epStatus}'
                                : '暂无章节',
                            style: TextStyle(
                              fontSize: 12 * densityScale,
                              color: Colors.grey[500],
                            ),
                          ),
                        if (showSecondary) ...[
                          SizedBox(height: 6 * densityScale),
                          Text(
                            '更新时间 ${_formatDate(widget.collection.updatedAt)}',
                            style: TextStyle(
                              fontSize: 11 * densityScale,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
