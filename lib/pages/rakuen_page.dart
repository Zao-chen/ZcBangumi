import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/rakuen_topic.dart';
import '../pages/subject_page.dart';
import '../pages/rakuen_topic_page.dart';
import '../providers/app_state_provider.dart';
import '../services/api_client.dart';

class RakuenPage extends StatefulWidget {
  const RakuenPage({super.key});

  @override
  State<RakuenPage> createState() => _RakuenPageState();
}

enum _RakuenTab { all, group, subject, ep, character, person }

class _RakuenTabState {
  final List<RakuenTopic> items = [];
  bool loading = false;
  bool loadingMore = false;
  bool hasMore = true;
  int page = 1;
  String? error;
}

class _RakuenPageState extends State<RakuenPage>
    with SingleTickerProviderStateMixin {
  static const _tabs = [
    _RakuenTabConfig(tab: _RakuenTab.all, label: '全部'),
    _RakuenTabConfig(tab: _RakuenTab.group, label: '小组'),
    _RakuenTabConfig(tab: _RakuenTab.subject, label: '条目'),
    _RakuenTabConfig(tab: _RakuenTab.ep, label: '章节'),
    _RakuenTabConfig(tab: _RakuenTab.character, label: '角色'),
    _RakuenTabConfig(tab: _RakuenTab.person, label: '人物'),
  ];

  late final TabController _tabController;
  late final Map<_RakuenTab, _RakuenTabState> _tabStates;

  _RakuenTab get _currentTab => _tabs[_tabController.index].tab;

  @override
  void initState() {
    super.initState();
    final initialIndex = context.read<AppStateProvider>().rakuenTabIndex;
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: initialIndex.clamp(0, _tabs.length - 1),
    );
    _tabStates = {for (final tab in _RakuenTab.values) tab: _RakuenTabState()};
    _tabController.addListener(_handleTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureLoaded(_currentTab);
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) return;
    context.read<AppStateProvider>().setRakuenTabIndex(_tabController.index);
    _ensureLoaded(_currentTab);
    setState(() {});
  }

  Future<void> _ensureLoaded(_RakuenTab tab) async {
    final state = _tabStates[tab]!;
    if (state.items.isNotEmpty || state.loading) return;
    await _load(tab);
  }

  Future<void> _load(_RakuenTab tab, {bool refresh = true}) async {
    final state = _tabStates[tab]!;
    if (state.loading || state.loadingMore) return;

    setState(() {
      if (refresh) {
        state.loading = true;
        state.error = null;
        state.page = 1;
        state.hasMore = true;
      } else {
        state.loadingMore = true;
      }
    });

    try {
      final api = context.read<ApiClient>();
      final items = await api.getRakuenTopics(
        type: _typeForTab(tab),
        filter: _filterForTab(tab),
        page: state.page,
      );

      if (!mounted) return;
      setState(() {
        if (refresh) {
          state.items
            ..clear()
            ..addAll(items);
        } else {
          state.items.addAll(items);
        }
        state.error = null;
        state.hasMore = items.isNotEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (state.items.isEmpty) {
          state.error = '加载失败: $e';
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          state.loading = false;
          state.loadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore(_RakuenTab tab) async {
    final state = _tabStates[tab]!;
    if (!state.hasMore || state.loading || state.loadingMore) return;
    state.page += 1;
    await _load(tab, refresh: false);
  }

  String? _typeForTab(_RakuenTab tab) {
    switch (tab) {
      case _RakuenTab.all:
        return null;
      case _RakuenTab.group:
        return 'group';
      case _RakuenTab.subject:
        return 'subject';
      case _RakuenTab.ep:
        return 'ep';
      case _RakuenTab.character:
      case _RakuenTab.person:
        return 'mono';
    }
  }

  String? _filterForTab(_RakuenTab tab) {
    switch (tab) {
      case _RakuenTab.character:
        return 'character';
      case _RakuenTab.person:
        return 'person';
      case _RakuenTab.all:
      case _RakuenTab.group:
      case _RakuenTab.subject:
      case _RakuenTab.ep:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        title: const Text('超展开'),
        centerTitle: false,
        bottom: isLandscape
            ? null
            : TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: _tabs.map((tab) => Tab(text: tab.label)).toList(),
              ),
      ),
      body: isLandscape ? _buildLandscapeLayout() : _buildTabBarView(),
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
                  icon: const Icon(Icons.forum_outlined),
                  selectedIcon: const Icon(Icons.forum),
                  label: Text(tab.label),
                ),
              )
              .toList(),
        ),
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(child: _buildTabBarView()),
      ],
    );
  }

  Widget _buildTabBarView() {
    return TabBarView(
      controller: _tabController,
      children: _tabs.map((config) => _buildTabView(config.tab)).toList(),
    );
  }

  Widget _buildTabView(_RakuenTab tab) {
    final state = _tabStates[tab]!;
    if (state.loading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(state.error!, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => _load(tab),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (state.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(tab),
        child: ListView(
          children: const [
            SizedBox(height: 180),
            Center(child: Text('暂无主题')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(tab),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: state.items.length + 1,
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            if (state.hasMore && !state.loadingMore) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _loadMore(tab);
              });
            }
            if (!state.hasMore) {
              return const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Center(child: Text('没有更多了')),
              );
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

          return _RakuenTopicCard(topic: state.items[index]);
        },
      ),
    );
  }
}

class _RakuenTopicCard extends StatelessWidget {
  final RakuenTopic topic;

  const _RakuenTopicCard({required this.topic});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RakuenTopicPage(topic: topic)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: topic.avatarUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: topic.avatarUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: colorScheme.surfaceContainerHighest,
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.forum_outlined),
                          ),
                        )
                      : Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.forum_outlined),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _TypeChip(label: topic.displayTypeLabel),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            topic.timeText,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      topic.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    if (topic.sourceTitle != null &&
                        topic.sourceTitle!.isNotEmpty)
                      Text(
                        topic.sourceTitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (topic.authorName != null &&
                        topic.authorName!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '@${topic.authorName!}',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${topic.replyCount}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const Spacer(),
                        if (_tryGetSubjectId(topic.sourceUrl)
                            case final subjectId?)
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    SubjectPage(subjectId: subjectId),
                              ),
                            ),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              minimumSize: const Size(0, 28),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('条目'),
                          ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static int? _tryGetSubjectId(String? url) {
    final match = RegExp(r'/subject/(\d+)').firstMatch(url ?? '');
    return match != null ? int.tryParse(match.group(1) ?? '') : null;
  }
}

class _TypeChip extends StatelessWidget {
  final String label;

  const _TypeChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _RakuenTabConfig {
  final _RakuenTab tab;
  final String label;

  const _RakuenTabConfig({required this.tab, required this.label});
}
