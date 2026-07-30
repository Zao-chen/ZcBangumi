import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models/calendar.dart';
import '../models/navigation_config.dart';
import '../models/recent_view_item.dart';
import '../models/subject.dart';
import '../models/subject_browse.dart';
import '../providers/app_state_provider.dart';
import '../providers/discovery_provider.dart';
import '../services/link_navigator.dart';
import '../widgets/subject_cover_card.dart';
import 'anime_tag_page.dart';
import 'character_page.dart';
import 'person_page.dart';
import 'rakuen_topic_page.dart';
import 'search_page.dart';
import 'subject_browse_page.dart';
import 'subject_page.dart';
import 'weekly_calendar_page.dart';

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({super.key});

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage> {
  static const _wideBreakpoint = 900.0;
  static const _maxContentWidth = 1440.0;

  int _previewType = BgmConst.subjectAnime;
  SubjectBrowseSort _previewSort = SubjectBrowseSort.rank;
  bool? _wasVisible;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<DiscoveryProvider>().initialize(rankingType: _previewType);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.watch<AppStateProvider?>();
    final isVisible =
        appState == null || appState.currentNavTabId == AppNavTabId.discover;
    final becameVisible = _wasVisible == false && isVisible;
    _wasVisible = isVisible;
    if (becameVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<DiscoveryProvider>().refreshRecentItems();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final discovery = context.watch<DiscoveryProvider>();
    final today = _calendarDay(discovery.calendar, DateTime.now().weekday);
    final preview = discovery.previewFor(_previewType, _previewSort);
    final loading =
        discovery.calendarLoading ||
        discovery.previewLoading(_previewType, _previewSort);

    return Scaffold(
      appBar: AppBar(
        title: const Text('发现'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: loading
                ? null
                : () => discovery.refreshHome(_previewType, sort: _previewSort),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= _wideBreakpoint) {
            return _buildWideBody(discovery, today, preview);
          }
          return _buildCompactBody(discovery, today, preview);
        },
      ),
    );
  }

  Widget _buildWideBody(
    DiscoveryProvider discovery,
    CalendarDay? today,
    List<SlimSubject> preview,
  ) {
    return RefreshIndicator(
      onRefresh: () => discovery.refreshHome(_previewType, sort: _previewSort),
      child: SingleChildScrollView(
        key: const Key('discovery_wide_dashboard'),
        primary: true,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 40),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildWideActions(),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SectionHeader(
                            title: '今日放送',
                            subtitle: today?.weekday.cn,
                            actionLabel: '完整周历',
                            onAction: _openWeeklyCalendar,
                            padding: EdgeInsets.zero,
                          ),
                          const SizedBox(height: 10),
                          _buildCalendarGrid(discovery, today),
                          const SizedBox(height: 30),
                          _buildWidePreviewHeader(),
                          const SizedBox(height: 12),
                          _buildTypeSelector(padding: EdgeInsets.zero),
                          const SizedBox(height: 14),
                          _buildPreviewGrid(discovery, preview),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    SizedBox(width: 320, child: _buildRecentPanel(discovery)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactBody(
    DiscoveryProvider discovery,
    CalendarDay? today,
    List<SlimSubject> preview,
  ) {
    return RefreshIndicator(
      onRefresh: () => discovery.refreshHome(_previewType, sort: _previewSort),
      child: CustomScrollView(
        primary: true,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            sliver: SliverToBoxAdapter(child: _buildSearchEntry()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            sliver: SliverToBoxAdapter(child: _buildCompactQuickActions()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _buildCompactRecentPanel(discovery),
            ),
          ),
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: '今日放送',
              subtitle: today?.weekday.cn,
              actionLabel: '本周放送',
              onAction: _openWeeklyCalendar,
            ),
          ),
          SliverToBoxAdapter(child: _buildCalendarSection(discovery, today)),
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: _previewSort == SubjectBrowseSort.rank ? '热门条目' : '最新条目',
              actionLabel: '查看全部',
              onAction: _openBrowse,
            ),
          ),
          SliverToBoxAdapter(child: _buildSortSelector()),
          SliverToBoxAdapter(child: _buildTypeSelector()),
          SliverToBoxAdapter(child: _buildPreviewSection(discovery, preview)),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }

  Widget _buildWideActions() {
    return Row(
      children: [
        Expanded(child: _buildSearchEntry()),
        const SizedBox(width: 12),
        FilledButton.tonalIcon(
          key: const Key('discovery_seasonal_entry'),
          onPressed: _openSeasonalAnime,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('本季新番'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          key: const Key('discovery_anime_tags_button'),
          onPressed: _openAnimeTags,
          icon: const Icon(Icons.sell_outlined),
          label: const Text('动画标签'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchEntry() {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: const Key('discovery_search_entry'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openPage(const SearchPage()),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Icon(Icons.search_rounded),
              SizedBox(width: 12),
              Expanded(child: Text('搜索条目、角色或人物...')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactQuickActions() {
    return Row(
      children: [
        Expanded(
          child: _QuickActionCard(
            key: const Key('discovery_seasonal_entry'),
            icon: Icons.auto_awesome_outlined,
            title: '本季新番',
            subtitle: '浏览当季动画',
            onTap: _openSeasonalAnime,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionCard(
            key: const Key('discovery_anime_tags_entry'),
            icon: Icons.sell_outlined,
            title: '动画标签',
            subtitle: kIsWeb ? '在 Bangumi 打开' : '按标签探索',
            onTap: _openAnimeTags,
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarSection(
    DiscoveryProvider discovery,
    CalendarDay? today,
  ) {
    if (discovery.calendarLoading && discovery.calendar.isEmpty) {
      return _horizontalSkeleton();
    }
    final items = today?.items.take(10).toList(growable: false) ?? const [];
    if (items.isEmpty) {
      return _InlineState(
        message: discovery.calendarError ?? '今天暂无放送条目',
        onRetry: discovery.calendarError == null
            ? null
            : () => discovery.loadCalendar(forceNetwork: true),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (discovery.calendarError != null)
          _refreshError(
            discovery.calendarError!,
            () => discovery.loadCalendar(forceNetwork: true),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          ),
        _horizontalCards(
          itemCount: items.length,
          builder: (context, index) => _calendarCard(items[index]),
        ),
      ],
    );
  }

  Widget _buildCalendarGrid(DiscoveryProvider discovery, CalendarDay? today) {
    if (discovery.calendarLoading && discovery.calendar.isEmpty) {
      return _gridSkeleton();
    }
    final items = today?.items.take(8).toList(growable: false) ?? const [];
    if (items.isEmpty) {
      return _InlineState(
        message: discovery.calendarError ?? '今天暂无放送条目',
        onRetry: discovery.calendarError == null
            ? null
            : () => discovery.loadCalendar(forceNetwork: true),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (discovery.calendarError != null)
          _refreshError(
            discovery.calendarError!,
            () => discovery.loadCalendar(forceNetwork: true),
            padding: const EdgeInsets.only(bottom: 8),
          ),
        _adaptiveGrid(
          itemCount: items.length,
          builder: (_, index) => _calendarCard(items[index]),
        ),
      ],
    );
  }

  Widget _buildWidePreviewHeader() {
    return Row(
      children: [
        Text(
          _previewSort == SubjectBrowseSort.rank ? '热门条目' : '最新条目',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        _buildSortSelector(compact: true),
        const SizedBox(width: 8),
        TextButton(onPressed: _openBrowse, child: const Text('查看全部')),
      ],
    );
  }

  Widget _buildSortSelector({bool compact = false}) {
    return Padding(
      padding: compact
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SegmentedButton<SubjectBrowseSort>(
        key: const Key('discovery_sort_selector'),
        segments: const [
          ButtonSegment(
            value: SubjectBrowseSort.rank,
            icon: Icon(Icons.leaderboard_outlined),
            label: Text('热门'),
          ),
          ButtonSegment(
            value: SubjectBrowseSort.date,
            icon: Icon(Icons.new_releases_outlined),
            label: Text('最新'),
          ),
        ],
        selected: {_previewSort},
        showSelectedIcon: false,
        onSelectionChanged: (selection) {
          final next = selection.first;
          if (next == _previewSort) return;
          setState(() => _previewSort = next);
          context.read<DiscoveryProvider>().loadPreview(_previewType, next);
        },
        style: compact
            ? ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 10),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildTypeSelector({EdgeInsetsGeometry? padding}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding ?? const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: subjectBrowseTypes.map((type) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: Key('discovery_type_$type'),
              selected: type == _previewType,
              label: Text(subjectTypeLabel(type)),
              onSelected: (_) {
                if (_previewType == type) return;
                setState(() => _previewType = type);
                context.read<DiscoveryProvider>().loadPreview(
                  type,
                  _previewSort,
                );
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPreviewSection(
    DiscoveryProvider discovery,
    List<SlimSubject> preview,
  ) {
    if (discovery.previewLoading(_previewType, _previewSort) &&
        preview.isEmpty) {
      return _horizontalSkeleton();
    }
    if (preview.isEmpty) {
      return _InlineState(
        message:
            discovery.previewError(_previewType, _previewSort) ??
            (_previewSort == SubjectBrowseSort.rank ? '暂无热门条目' : '暂无最新条目'),
        onRetry: () => discovery.loadPreview(
          _previewType,
          _previewSort,
          forceNetwork: true,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (discovery.previewError(_previewType, _previewSort) != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _errorText(
              discovery.previewError(_previewType, _previewSort)!,
            ),
          ),
        _horizontalCards(
          itemCount: preview.length,
          builder: (context, index) => _subjectCard(preview[index]),
        ),
      ],
    );
  }

  Widget _buildPreviewGrid(
    DiscoveryProvider discovery,
    List<SlimSubject> preview,
  ) {
    if (discovery.previewLoading(_previewType, _previewSort) &&
        preview.isEmpty) {
      return _gridSkeleton();
    }
    if (preview.isEmpty) {
      return _InlineState(
        message:
            discovery.previewError(_previewType, _previewSort) ??
            (_previewSort == SubjectBrowseSort.rank ? '暂无热门条目' : '暂无最新条目'),
        onRetry: () => discovery.loadPreview(
          _previewType,
          _previewSort,
          forceNetwork: true,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (discovery.previewError(_previewType, _previewSort) != null) ...[
          _errorText(discovery.previewError(_previewType, _previewSort)!),
          const SizedBox(height: 8),
        ],
        _adaptiveGrid(
          itemCount: preview.length,
          builder: (_, index) => _subjectCard(preview[index]),
        ),
      ],
    );
  }

  Widget _buildRecentPanel(DiscoveryProvider discovery) {
    final recent = discovery.recentItems.take(5).toList(growable: false);
    return _DashboardPanel(
      title: '最近浏览',
      action: recent.isEmpty
          ? null
          : TextButton(
              onPressed: discovery.clearRecentItems,
              child: const Text('清空'),
            ),
      child: recent.isEmpty
          ? const _PanelEmptyState(
              icon: Icons.history_rounded,
              message: '浏览过的内容会出现在这里',
            )
          : Column(
              children: [
                for (var index = 0; index < recent.length; index++) ...[
                  _RecentViewTile(
                    item: recent[index],
                    onTap: () => _openRecentItem(recent[index]),
                  ),
                  if (index != recent.length - 1)
                    const Divider(height: 14, indent: 56),
                ],
              ],
            ),
    );
  }

  Widget _buildCompactRecentPanel(DiscoveryProvider discovery) {
    final colorScheme = Theme.of(context).colorScheme;
    final recent = discovery.recentItems.take(5).toList(growable: false);
    return Card(
      key: const Key('discovery_compact_recent'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: ValueKey('compact_recent_${recent.isNotEmpty}'),
        initiallyExpanded: recent.isNotEmpty,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.history_rounded),
        title: Row(
          children: [
            const Text('最近浏览', style: TextStyle(fontWeight: FontWeight.w700)),
            if (recent.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                '${recent.length}',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(recent.isEmpty ? '浏览记录会保存在本机' : '最近查看的内容'),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        children: [
          if (recent.isEmpty)
            const _PanelEmptyState(
              icon: Icons.history_rounded,
              message: '浏览过的内容会出现在这里',
            )
          else ...[
            for (var index = 0; index < recent.length; index++) ...[
              _RecentViewTile(
                item: recent[index],
                onTap: () => _openRecentItem(recent[index]),
              ),
              if (index != recent.length - 1)
                const Divider(height: 14, indent: 56),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: discovery.clearRecentItems,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('清空记录'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _adaptiveGrid({
    required int itemCount,
    required Widget Function(BuildContext context, int index) builder,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.58,
      ),
      itemCount: itemCount,
      itemBuilder: builder,
    );
  }

  Widget _gridSkeleton() {
    final color = Theme.of(context).colorScheme.surfaceContainerLow;
    return _adaptiveGrid(
      itemCount: 5,
      builder: (_, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _horizontalSkeleton() {
    final color = Theme.of(context).colorScheme.surfaceContainerLow;
    return SizedBox(
      height: 250,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, _) => Container(
          width: 142,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemCount: 5,
      ),
    );
  }

  Widget _horizontalCards({
    required int itemCount,
    required Widget Function(BuildContext context, int index) builder,
  }) {
    return SizedBox(
      height: 250,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) =>
            SizedBox(width: 142, child: builder(context, index)),
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemCount: itemCount,
      ),
    );
  }

  Widget _calendarCard(CalendarSubject subject) {
    return SubjectCoverCard(
      title: subject.displayName,
      subtitle: subject.nameCn.isNotEmpty && subject.name != subject.nameCn
          ? subject.name
          : '',
      imageUrl: subject.images?.common ?? '',
      score: subject.rating?.score ?? 0,
      rank: subject.rank ?? 0,
      date: subject.airDate ?? '',
      onTap: () => _openSubject(subject.id),
    );
  }

  Widget _subjectCard(SlimSubject subject) {
    return SubjectCoverCard(
      title: subject.displayName,
      subtitle: subject.nameCn.isNotEmpty && subject.name != subject.nameCn
          ? subject.name
          : '',
      imageUrl: subject.images?.common ?? '',
      score: subject.score,
      rank: subject.rank,
      date: subject.date,
      onTap: () => _openSubject(subject.id),
    );
  }

  Widget _errorText(String message) {
    return Text(
      message,
      style: TextStyle(
        color: Theme.of(context).colorScheme.error,
        fontSize: 12,
      ),
    );
  }

  Widget _refreshError(
    String message,
    VoidCallback onRetry, {
    required EdgeInsetsGeometry padding,
  }) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: _errorText(message)),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }

  CalendarDay? _calendarDay(List<CalendarDay> days, int weekday) {
    for (final day in days) {
      if (day.weekday.id == weekday) return day;
    }
    return null;
  }

  Future<void> _openWeeklyCalendar() {
    return _openPage(
      WeeklyCalendarPage(initialWeekday: DateTime.now().weekday),
    );
  }

  Future<void> _openAnimeTags() async {
    if (kIsWeb) {
      final opened = await LinkNavigator.openBrowser(
        Uri.parse('${BgmConst.webBaseUrl}/anime/tag'),
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开动画标签页面')));
      }
      return;
    }
    if (!mounted) return;
    await _openPage(const AnimeTagPage());
  }

  Future<void> _openSeasonalAnime() {
    final current = DateTime.now();
    final seasonStartMonth = ((current.month - 1) ~/ 3) * 3 + 1;
    return _openPage(
      SubjectBrowsePage(
        initialFilter: SubjectBrowseFilter(
          type: BgmConst.subjectAnime,
          category: 1,
          year: current.year,
          month: seasonStartMonth,
          sort: SubjectBrowseSort.date,
        ),
      ),
    );
  }

  Future<void> _openBrowse() {
    return _openPage(
      SubjectBrowsePage(
        initialFilter: SubjectBrowseFilter(
          type: _previewType,
          sort: _previewSort,
        ),
      ),
    );
  }

  Future<void> _openRecentItem(RecentViewItem item) async {
    final numericId = item.numericId;
    final page = switch (item.kind) {
      RecentViewKind.subject when numericId != null => SubjectPage(
        subjectId: numericId,
      ),
      RecentViewKind.topic when item.topic != null => RakuenTopicPage(
        topic: item.topic!,
      ),
      RecentViewKind.character when numericId != null => CharacterPage(
        characterId: numericId,
      ),
      RecentViewKind.person when numericId != null => PersonPage(
        personId: numericId,
      ),
      _ => null,
    };
    if (page == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('这条浏览记录已失效')));
      return;
    }
    await _openPage(page);
  }

  Future<void> _openSubject(int subjectId) async {
    await _openPage(SubjectPage(subjectId: subjectId));
  }

  Future<void> _openPage(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) {
      context.read<DiscoveryProvider>().refreshRecentItems();
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  final EdgeInsetsGeometry padding;

  const _SectionHeader({
    required this.title,
    this.subtitle,
    required this.actionLabel,
    required this.onAction,
    this.padding = const EdgeInsets.fromLTRB(16, 18, 8, 10),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (subtitle?.isNotEmpty == true) ...[
            const SizedBox(width: 8),
            Text(
              subtitle!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
          const Spacer(),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
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
}

class _DashboardPanel extends StatelessWidget {
  final String title;
  final Widget? action;
  final Widget child;

  const _DashboardPanel({
    required this.title,
    this.action,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                ?action,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _RecentViewTile extends StatelessWidget {
  final RecentViewItem item;
  final VoidCallback onTap;

  const _RecentViewTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final imageUrl = item.imageUrl;
    final fallbackIcon = switch (item.kind) {
      RecentViewKind.subject => Icons.movie_outlined,
      RecentViewKind.topic => Icons.forum_outlined,
      RecentViewKind.character => Icons.theater_comedy_outlined,
      RecentViewKind.person => Icons.badge_outlined,
    };
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 44,
                height: 60,
                child: imageUrl.isEmpty
                    ? ColoredBox(
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(fallbackIcon, size: 21),
                      )
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => ColoredBox(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title.isEmpty ? '未命名${item.kindLabel}' : item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.subtitle.isEmpty
                        ? item.kindLabel
                        : '${item.kindLabel} · ${item.subtitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

class _PanelEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _PanelEmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _InlineState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _InlineState({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 8),
            Text(message),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
