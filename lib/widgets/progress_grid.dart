import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/episode.dart';
import '../models/rakuen_topic.dart';
import '../pages/rakuen_topic_page.dart';

class ProgressGrid extends StatelessWidget {
  final List<UserEpisodeCollection> episodes;
  final bool loading;
  final bool useNumberPicker;
  final bool useCollectionTypePicker;
  final int bookCurrentProgress;
  final int? bookMaxProgress;
  final int collectionSubjectType;
  final int? collectionType;
  final void Function(int episodeId, int newType)? onSetStatus;
  final void Function(int episodeSort)? onWatchUpTo;
  final void Function(int newType)? onSetCollectionType;

  const ProgressGrid({
    super.key,
    required this.episodes,
    this.loading = false,
    this.useNumberPicker = false,
    this.useCollectionTypePicker = false,
    this.bookCurrentProgress = 0,
    this.bookMaxProgress,
    this.collectionSubjectType = BgmConst.subjectAnime,
    this.collectionType,
    this.onSetStatus,
    this.onWatchUpTo,
    this.onSetCollectionType,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (useCollectionTypePicker) {
      return _CollectionTypeCell(
        subjectType: collectionSubjectType,
        collectionType: collectionType ?? BgmConst.collectionDoing,
        onSetCollectionType: onSetCollectionType,
      );
    }

    if (episodes.isEmpty && !useNumberPicker) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          '\u6682\u65e0\u7ae0\u8282\u4fe1\u606f',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final mainEps = episodes.where((e) => e.episode.type == 0).toList();
    if (mainEps.isEmpty && !useNumberPicker) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          '\u6682\u65e0\u672c\u7bc7\u7ae0\u8282',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    mainEps.sort((a, b) => a.episode.sort.compareTo(b.episode.sort));

    if (useNumberPicker) {
      return _BookProgressSelector(
        episodes: mainEps,
        currentProgress: bookCurrentProgress,
        maxProgress: bookMaxProgress,
        onWatchUpTo: onWatchUpTo,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 3,
        runSpacing: 3,
        children: mainEps
            .map(
              (ep) => _EpisodeCell(
                episode: ep,
                onSetStatus: onSetStatus,
                onWatchUpTo: onWatchUpTo,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _CollectionTypeCell extends StatelessWidget {
  final int subjectType;
  final int collectionType;
  final void Function(int newType)? onSetCollectionType;

  const _CollectionTypeCell({
    required this.subjectType,
    required this.collectionType,
    this.onSetCollectionType,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (accentColor, textColor) = switch (collectionType) {
      BgmConst.collectionDoing => (
        colorScheme.primary,
        colorScheme.onPrimaryContainer,
      ),
      BgmConst.collectionDone => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
      ),
      BgmConst.collectionWish => (
        colorScheme.secondaryContainer,
        colorScheme.onSecondaryContainer,
      ),
      BgmConst.collectionDropped => (
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
      BgmConst.collectionOnHold => (
        colorScheme.tertiaryContainer,
        colorScheme.onTertiaryContainer,
      ),
      _ => (colorScheme.surfaceContainerHighest, colorScheme.onSurfaceVariant),
    };
    final isDoing = collectionType == BgmConst.collectionDoing;
    final label = BgmConst.collectionLabel(
      collectionType,
      subjectType: subjectType,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Tooltip(
        message: '\u70b9\u51fb\u4fee\u6536\u85cf\u72b6\u6001',
        child: SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTapUp: (details) => _showMenu(context, details.globalPosition),
            child: Container(
              height: 28,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Stack(
                  children: [
                    if (!isDoing) Container(color: accentColor.withAlpha(110)),
                    if (isDoing)
                      const _IndeterminateProgressOverlay(enabled: true),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMenu(BuildContext context, Offset position) {
    const options = <int>[
      BgmConst.collectionWish,
      BgmConst.collectionDoing,
      BgmConst.collectionDone,
      BgmConst.collectionOnHold,
      BgmConst.collectionDropped,
    ];
    final items = options
        .map(
          (type) => PopupMenuItem<int>(
            value: type,
            child: Text(
              BgmConst.collectionLabel(type, subjectType: subjectType),
            ),
          ),
        )
        .toList();

    showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: items,
    ).then((value) {
      if (value == null || value == collectionType) return;
      onSetCollectionType?.call(value);
    });
  }
}

class _BookProgressSelector extends StatelessWidget {
  final List<UserEpisodeCollection> episodes;
  final int currentProgress;
  final int? maxProgress;
  final void Function(int episodeSort)? onWatchUpTo;

  const _BookProgressSelector({
    required this.episodes,
    required this.currentProgress,
    this.maxProgress,
    this.onWatchUpTo,
  });

  List<int> _availableSorts() {
    final maxByInput = maxProgress ?? 0;
    final sorts = episodes
        .map((e) => e.episode.sort)
        .where((s) => s > 0)
        .map((s) => s.toInt())
        .toSet()
        .toList();
    if (sorts.isEmpty) {
      final fallbackMax = maxByInput > 0
          ? maxByInput
          : (currentProgress > 0 ? currentProgress + 100 : 100);
      return List<int>.generate(fallbackMax, (i) => i + 1);
    }
    if (maxByInput > 0 && !sorts.contains(maxByInput)) {
      sorts.add(maxByInput);
    }
    if (currentProgress > 0 && !sorts.contains(currentProgress)) {
      sorts.add(currentProgress);
    }
    sorts.sort();
    return sorts;
  }

  int _currentDoneSort() {
    if (episodes.isEmpty) return currentProgress;
    final doneSorts = episodes
        .where((e) => e.type == BgmConst.episodeDone)
        .map((e) => e.episode.sort)
        .where((s) => s > 0)
        .toList();
    if (doneSorts.isEmpty) return currentProgress;
    doneSorts.sort();
    return doneSorts.last.toInt() > currentProgress
        ? doneSorts.last.toInt()
        : currentProgress;
  }

  Future<int?> _showSortPicker(
    BuildContext context,
    List<int> sorts,
    int currentSort,
  ) async {
    if (sorts.isEmpty) return null;
    final initialIndex = (() {
      final idx = sorts.indexWhere((s) => s >= currentSort && currentSort > 0);
      if (idx != -1) return idx;
      return 0;
    })();
    final controller = FixedExtentScrollController(initialItem: initialIndex);
    var selectedIndex = initialIndex;
    var selected = sorts[selectedIndex];

    return showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> jumpToIndex(int target) async {
              final clamped = target.clamp(0, sorts.length - 1);
              setModalState(() {
                selectedIndex = clamped;
                selected = sorts[selectedIndex];
              });
              await controller.animateToItem(
                clamped,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
              );
            }

            Future<void> inputChapter() async {
              final textController = TextEditingController(
                text: selected.toString(),
              );
              final input = await showDialog<int>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text('\u8f93\u5165\u7ae0\u8282\u53f7'),
                    content: TextField(
                      controller: textController,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: '\u4f8b\u5982: 52',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('\u53d6\u6d88'),
                      ),
                      FilledButton(
                        onPressed: () {
                          final value = int.tryParse(
                            textController.text.trim(),
                          );
                          Navigator.pop(context, value);
                        },
                        child: const Text('\u786e\u5b9a'),
                      ),
                    ],
                  );
                },
              );
              if (input == null) return;
              final idx = sorts.indexWhere((v) => v >= input);
              await jumpToIndex(idx == -1 ? sorts.length - 1 : idx);
            }

            return SafeArea(
              child: SizedBox(
                height: 380,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('\u53d6\u6d88'),
                          ),
                          const Spacer(),
                          Text(
                            '\u9009\u62e9\u7ae0\u8282',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(context, selected),
                            child: const Text('\u786e\u5b9a'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          ListWheelScrollView.useDelegate(
                            controller: controller,
                            itemExtent: 44,
                            perspective: 0.003,
                            useMagnifier: true,
                            magnification: 1.08,
                            onSelectedItemChanged: (index) {
                              setModalState(() {
                                selectedIndex = index;
                                selected = sorts[index];
                              });
                            },
                            childDelegate: ListWheelChildBuilderDelegate(
                              childCount: sorts.length,
                              builder: (context, index) {
                                if (index < 0 || index >= sorts.length)
                                  return null;
                                final isSelected = index == selectedIndex;
                                return Center(
                                  child: Text(
                                    '\u7b2c ${sorts[index]} \u7ae0',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                          color: isSelected
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                );
                              },
                            ),
                          ),
                          IgnorePointer(
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              height: 44,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 1.4,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: selectedIndex > 0
                                ? () => jumpToIndex(selectedIndex - 1)
                                : null,
                            icon: const Icon(Icons.remove),
                            label: const Text('-1'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: selectedIndex < sorts.length - 1
                                ? () => jumpToIndex(selectedIndex + 1)
                                : null,
                            icon: const Icon(Icons.add),
                            label: const Text('+1'),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: inputChapter,
                            icon: const Icon(Icons.keyboard),
                            label: const Text('\u76f4\u63a5\u8f93\u5165'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sorts = _availableSorts();
    final currentDoneSort = _currentDoneSort();
    final knownMax = (maxProgress != null && maxProgress! > 0)
        ? maxProgress
        : null;
    final displayMax = knownMax?.toString() ?? '??';
    final progressText = '$currentDoneSort/$displayMax';
    final enabled = onWatchUpTo != null && sorts.isNotEmpty;
    final isIndeterminate = knownMax == null;
    final progressRatio = (knownMax != null && knownMax > 0)
        ? (currentDoneSort / knownMax).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Tooltip(
        message: '\u9009\u62e9\u7ae0\u8282',
        child: SizedBox(
          width: double.infinity,
          child: InkWell(
            borderRadius: BorderRadius.circular(5),
            onTap: !enabled
                ? null
                : () async {
                    final picked = await _showSortPicker(
                      context,
                      sorts,
                      currentDoneSort,
                    );
                    if (picked != null) {
                      onWatchUpTo?.call(picked);
                    }
                  },
            child: Container(
              height: 28,
              decoration: BoxDecoration(
                color: enabled
                    ? colorScheme.surfaceContainerHighest
                    : colorScheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final filledWidth = constraints.maxWidth * progressRatio;
                    return Stack(
                      children: [
                        if (isIndeterminate)
                          _IndeterminateProgressOverlay(enabled: enabled),
                        if (!isIndeterminate && filledWidth > 0)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: filledWidth,
                              color: enabled
                                  ? colorScheme.primary.withAlpha(90)
                                  : colorScheme.onSurface.withAlpha(20),
                            ),
                          ),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              progressText,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: enabled
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeCell extends StatelessWidget {
  static const int _menuWatchUpTo = -1;
  static const int _menuOpenDiscussion = -2;

  final UserEpisodeCollection episode;
  final void Function(int episodeId, int newType)? onSetStatus;
  final void Function(int episodeSort)? onWatchUpTo;

  const _EpisodeCell({
    required this.episode,
    this.onSetStatus,
    this.onWatchUpTo,
  });

  bool _isAired() {
    if (episode.episode.airdate.isEmpty) return false;
    try {
      final airdateTime = DateTime.parse(episode.episode.airdate);
      return airdateTime.isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAired = _isAired();

    Color bgColor;
    Color textColor;
    switch (episode.type) {
      case BgmConst.episodeDone:
        bgColor = colorScheme.primary;
        textColor = colorScheme.onPrimary;
        break;
      case BgmConst.episodeWish:
        bgColor = colorScheme.primaryContainer;
        textColor = colorScheme.onPrimaryContainer;
        break;
      case BgmConst.episodeDropped:
        bgColor = colorScheme.errorContainer;
        textColor = colorScheme.onErrorContainer;
        break;
      default:
        bgColor = colorScheme.surfaceContainerHighest;
        textColor = colorScheme.onSurfaceVariant;
    }

    if (!isAired) {
      final dimmedAlpha = ((bgColor.a * 255.0) * 0.4).round().clamp(0, 255);
      bgColor = bgColor.withAlpha(dimmedAlpha);
    }

    return Tooltip(
      message: _tooltipText(),
      child: GestureDetector(
        onTapUp: (details) => _showMenu(context, details.globalPosition),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(5),
          ),
          alignment: Alignment.center,
          child: Text(
            episode.episode.sortLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  void _showMenu(BuildContext context, Offset position) {
    final ep = episode;
    final currentType = ep.type;

    final items = <PopupMenuEntry<int>>[];

    if (currentType != BgmConst.episodeDone) {
      items.add(
        const PopupMenuItem(
          value: BgmConst.episodeDone,
          height: 40,
          child: _MenuRow(
            icon: Icons.check_circle,
            label: '\u770b\u8fc7',
            color: Colors.blue,
          ),
        ),
      );
    }

    items.add(
      PopupMenuItem(
        value: _menuWatchUpTo,
        height: 40,
        child: _MenuRow(
          icon: Icons.fast_forward,
          label: '\u770b\u5230',
          color: Colors.teal,
        ),
      ),
    );

    if (currentType != BgmConst.episodeWish) {
      items.add(
        const PopupMenuItem(
          value: BgmConst.episodeWish,
          height: 40,
          child: _MenuRow(
            icon: Icons.bookmark_outline,
            label: '\u60f3\u770b',
            color: Colors.orange,
          ),
        ),
      );
    }

    if (currentType != BgmConst.episodeDropped) {
      items.add(
        const PopupMenuItem(
          value: BgmConst.episodeDropped,
          height: 40,
          child: _MenuRow(
            icon: Icons.block,
            label: '\u629b\u5f03',
            color: Colors.red,
          ),
        ),
      );
    }

    if (currentType != BgmConst.episodeNotCollected) {
      items.add(const PopupMenuDivider(height: 8));
      items.add(
        const PopupMenuItem(
          value: BgmConst.episodeNotCollected,
          height: 40,
          child: _MenuRow(
            icon: Icons.undo,
            label: '\u64a4\u9500',
            color: Colors.grey,
          ),
        ),
      );
    }

    items.add(const PopupMenuDivider(height: 8));
    items.add(
      const PopupMenuItem(
        value: _menuOpenDiscussion,
        height: 40,
        child: _MenuRow(
          icon: Icons.forum_outlined,
          label: '\u8ba8\u8bba',
          color: Colors.indigo,
        ),
      ),
    );

    showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: items,
    ).then((value) async {
      if (value == null) return;
      if (value == _menuWatchUpTo) {
        onWatchUpTo?.call(ep.episode.sort.toInt());
      } else if (value == _menuOpenDiscussion) {
        await _openEpisodeDiscussion(context, ep.episode);
      } else {
        onSetStatus?.call(ep.episode.id, value);
      }
    });
  }

  Future<void> _openEpisodeDiscussion(
    BuildContext context,
    Episode episodeInfo,
  ) async {
    final navigator = Navigator.of(context);
    final topic = RakuenTopic(
      id: 'ep_${episodeInfo.id}',
      type: 'ep',
      title: episodeInfo.displayName,
      topicUrl: '${BgmConst.webBaseUrl}/rakuen/topic/ep/${episodeInfo.id}',
      avatarUrl: '',
      replyCount: 0,
      timeText: '',
      sourceTitle: null,
      sourceUrl: null,
      authorName: null,
    );

    await navigator.push(
      MaterialPageRoute(
        builder: (_) => RakuenTopicPage(topic: topic, episode: episodeInfo),
      ),
    );
  }

  String _tooltipText() {
    final ep = episode.episode;
    final name = ep.displayName;
    final status = switch (episode.type) {
      BgmConst.episodeDone => '\u770b\u8fc7',
      BgmConst.episodeWish => '\u60f3\u770b',
      BgmConst.episodeDropped => '\u629b\u5f03',
      _ => '\u672a\u6536\u85cf',
    };
    final airedStatus = _isAired()
        ? '\u5df2\u653e\u9001'
        : '\u672a\u653e\u9001';
    return 'EP.${ep.sortLabel} $name [$status] [$airedStatus]';
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MenuRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 14)),
      ],
    );
  }
}

class _IndeterminateProgressOverlay extends StatefulWidget {
  final bool enabled;

  const _IndeterminateProgressOverlay({required this.enabled});

  @override
  State<_IndeterminateProgressOverlay> createState() =>
      _IndeterminateProgressOverlayState();
}

class _IndeterminateProgressOverlayState
    extends State<_IndeterminateProgressOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    _opacityAnim = Tween<double>(
      begin: 0.03,
      end: 0.10,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = widget.enabled
        ? colorScheme.primary
        : colorScheme.onSurface;

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _opacityAnim,
        builder: (context, child) {
          return Container(color: baseColor.withOpacity(_opacityAnim.value));
        },
      ),
    );
  }
}
