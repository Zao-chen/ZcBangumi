import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/collection.dart';
import '../pages/search_page.dart';
import '../pages/subject_page.dart';
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        title: const Text('进度'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索条目',
            onPressed: () => _showSearchPage(context),
          ),
        ],
        bottom: isLandscape
            ? null
            : TabBar(
                controller: _tabController,
                tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                indicatorSize: TabBarIndicatorSize.label,
              ),
      ),
      body: auth.isLoggedIn
          ? isLandscape
                ? _buildLandscapeLayout()
                : TabBarView(
                    controller: _tabController,
                    children: _tabs
                        .map((t) => _ProgressTabView(subjectType: t.type))
                        .toList(),
                  )
          : _buildNotLoggedIn(),
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
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  void _loadData() {
    final auth = context.read<AuthProvider>();
    if (auth.isLoggedIn && auth.username != null) {
      context.read<CollectionProvider>().loadDoingCollections(
        username: auth.username!,
        subjectType: widget.subjectType,
      );
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

    if (isLoading && collections.isEmpty) {
      return const Center(child: CircularProgressIndicator());
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
        if (auth.username != null) {
          await provider.loadDoingCollections(
            username: auth.username!,
            subjectType: widget.subjectType,
            refresh: true,
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
    final subject = widget.collection.subject;
    final episodes = provider.getEpisodeProgress(widget.collection.subjectId);
    final epLoading = provider.isEpisodeLoading(widget.collection.subjectId);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 条目信息栏
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 封面
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 56,
                      height: 80,
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
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
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
                            bookMaxProgress:
                                (subject?.eps ?? 0) > 0 ? subject!.eps : null,
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
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
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
}
