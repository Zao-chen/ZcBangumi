import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'copyable_text.dart';

enum MonoEntityChipTone { neutral, accent }

class MonoEntityChip {
  final String label;
  final MonoEntityChipTone tone;

  const MonoEntityChip(this.label, {this.tone = MonoEntityChipTone.neutral});
}

class MonoEntityListCard extends StatelessWidget {
  final String imageUrl;
  final IconData placeholderIcon;
  final String title;
  final String subtitle;
  final String description;
  final List<MonoEntityChip> chips;
  final VoidCallback onTap;
  final double imageWidth;
  final double imageHeight;
  final bool showChevron;

  const MonoEntityListCard({
    super.key,
    required this.imageUrl,
    required this.placeholderIcon,
    required this.title,
    this.subtitle = '',
    this.description = '',
    this.chips = const [],
    required this.onTap,
    this.imageWidth = 80,
    this.imageHeight = 104,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MonoEntityImage(
                imageUrl: imageUrl,
                placeholderIcon: placeholderIcon,
                width: imageWidth,
                height: imageHeight,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: chips.map(MonoEntityChipView.new).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              if (showChevron)
                SizedBox(
                  height: imageHeight,
                  child: const Center(child: Icon(Icons.chevron_right_rounded)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class MonoEntityHeaderCard extends StatelessWidget {
  final String imageUrl;
  final IconData placeholderIcon;
  final String title;
  final List<MonoEntityChip> chips;
  final Widget? footer;

  const MonoEntityHeaderCard({
    super.key,
    required this.imageUrl,
    required this.placeholderIcon,
    required this.title,
    this.chips = const [],
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MonoEntityImage(
              imageUrl: imageUrl,
              placeholderIcon: placeholderIcon,
              width: 84,
              height: 122,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShortCopyableText(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: chips.map(MonoEntityChipView.new).toList(),
                    ),
                  ],
                  if (footer != null) ...[const SizedBox(height: 8), footer!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MonoEntityChipView extends StatelessWidget {
  final MonoEntityChip chip;

  const MonoEntityChipView(this.chip, {super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = chip.tone == MonoEntityChipTone.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        chip.label,
        style: TextStyle(
          color: accent
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    );
  }
}

class MonoEntityImage extends StatelessWidget {
  final String imageUrl;
  final IconData placeholderIcon;
  final double width;
  final double height;

  const MonoEntityImage({
    super.key,
    required this.imageUrl,
    required this.placeholderIcon,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Container(
      width: width,
      height: height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(placeholderIcon),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: imageUrl.isEmpty
          ? placeholder()
          : CachedNetworkImage(
              imageUrl: imageUrl,
              width: width,
              height: height,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              placeholder: (_, _) => placeholder(),
              errorWidget: (_, _, _) => placeholder(),
            ),
    );
  }
}

class MonoEntityOverviewSection extends StatelessWidget {
  final String title;
  final Widget child;
  final EdgeInsets padding;

  const MonoEntityOverviewSection({
    super.key,
    required this.title,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class MonoEntityInfoTable extends StatelessWidget {
  final Map<String, String> info;
  final double labelWidth;

  const MonoEntityInfoTable({
    super.key,
    required this.info,
    this.labelWidth = 80,
  });

  @override
  Widget build(BuildContext context) {
    final entries = info.entries.toList();
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var index = 0; index < entries.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: labelWidth,
                  child: ShortCopyableText(
                    entries[index].key,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CopyableText(
                    entries[index].value,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class MonoEntityOverviewEmptyState extends StatelessWidget {
  final String message;

  const MonoEntityOverviewEmptyState({super.key, this.message = '暂无概述信息'});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 120, horizontal: 16),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(message, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class MonoEntityEmptyState extends StatelessWidget {
  final String message;
  final IconData icon;
  final Future<void> Function() onRefresh;

  const MonoEntityEmptyState({
    super.key,
    required this.message,
    required this.icon,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 140),
          Icon(icon, size: 58, color: Colors.grey[400]),
          const SizedBox(height: 14),
          Center(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class MonoEntitySkeletonList extends StatelessWidget {
  final double imageWidth;
  final double imageHeight;

  const MonoEntitySkeletonList({
    super.key,
    this.imageWidth = 80,
    this.imageHeight = 104,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: 4,
      itemBuilder: (context, index) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: imageWidth,
                height: imageHeight,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _skeletonLine(colorScheme, width: 140, height: 14),
                    const SizedBox(height: 8),
                    _skeletonLine(colorScheme, width: 90, height: 10),
                    const SizedBox(height: 8),
                    _skeletonLine(colorScheme, width: 180, height: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _skeletonLine(
    ColorScheme colorScheme, {
    required double width,
    required double height,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
