import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/calendar.dart';
import '../providers/discovery_provider.dart';
import '../widgets/subject_cover_card.dart';
import 'subject_page.dart';

class WeeklyCalendarPage extends StatefulWidget {
  final int? initialWeekday;

  const WeeklyCalendarPage({super.key, this.initialWeekday});

  @override
  State<WeeklyCalendarPage> createState() => _WeeklyCalendarPageState();
}

class _WeeklyCalendarPageState extends State<WeeklyCalendarPage> {
  late int _selectedWeekday;

  @override
  void initState() {
    super.initState();
    _selectedWeekday =
        widget.initialWeekday?.clamp(1, 7) ?? DateTime.now().weekday;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<DiscoveryProvider>().loadCalendar();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final discovery = context.watch<DiscoveryProvider>();
    final selected = _dayFor(discovery.calendar, _selectedWeekday);

    return Scaffold(
      appBar: AppBar(
        title: const Text('本周放送'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: discovery.calendarLoading
                ? null
                : () => discovery.loadCalendar(forceNetwork: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => discovery.loadCalendar(forceNetwork: true),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _WeekdaySelector(
                days: discovery.calendar,
                selectedWeekday: _selectedWeekday,
                onSelected: (value) {
                  setState(() => _selectedWeekday = value);
                },
              ),
            ),
            if (discovery.calendarError != null &&
                discovery.calendar.isNotEmpty)
              SliverToBoxAdapter(
                child: MaterialBanner(
                  content: Text(discovery.calendarError!),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          discovery.loadCalendar(forceNetwork: true),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            if (discovery.calendarLoading && discovery.calendar.isEmpty)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (selected == null || selected.items.isEmpty)
              SliverFillRemaining(
                child: _CalendarMessage(
                  icon: discovery.calendarError == null
                      ? Icons.event_busy_outlined
                      : Icons.error_outline_rounded,
                  message: discovery.calendarError ?? '当天暂无放送条目',
                  onRetry: discovery.calendarError == null
                      ? null
                      : () => discovery.loadCalendar(forceNetwork: true),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    childAspectRatio: 0.58,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _calendarCard(context, selected.items[index]),
                    childCount: selected.items.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  CalendarDay? _dayFor(List<CalendarDay> days, int weekday) {
    for (final day in days) {
      if (day.weekday.id == weekday) return day;
    }
    return null;
  }

  Widget _calendarCard(BuildContext context, CalendarSubject subject) {
    return SubjectCoverCard(
      title: subject.displayName,
      subtitle: subject.nameCn.isNotEmpty && subject.name != subject.nameCn
          ? subject.name
          : '',
      imageUrl: subject.images?.common ?? '',
      score: subject.rating?.score ?? 0,
      rank: subject.rank ?? 0,
      date: subject.airDate ?? '',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SubjectPage(subjectId: subject.id)),
      ),
    );
  }
}

class _WeekdaySelector extends StatelessWidget {
  final List<CalendarDay> days;
  final int selectedWeekday;
  final ValueChanged<int> onSelected;

  const _WeekdaySelector({
    required this.days,
    required this.selectedWeekday,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: List.generate(7, (index) {
          final value = index + 1;
          final day = days
              .where((item) => item.weekday.id == value)
              .firstOrNull;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: value == selectedWeekday,
              label: Text(day?.weekday.cn ?? _fallbackWeekday(value)),
              onSelected: (_) => onSelected(value),
            ),
          );
        }),
      ),
    );
  }

  String _fallbackWeekday(int weekday) => switch (weekday) {
    1 => '星期一',
    2 => '星期二',
    3 => '星期三',
    4 => '星期四',
    5 => '星期五',
    6 => '星期六',
    _ => '星期日',
  };
}

class _CalendarMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  const _CalendarMessage({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        if (onRetry != null) ...[
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ),
        ],
      ],
    );
  }
}
