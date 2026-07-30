import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';

class SubjectCoverCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageUrl;
  final double score;
  final int rank;
  final String date;
  final VoidCallback onTap;

  const SubjectCoverCard({
    super.key,
    required this.title,
    this.subtitle = '',
    required this.imageUrl,
    this.score = 0,
    this.rank = 0,
    this.date = '',
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appState = context.watch<AppStateProvider?>();
    final densityScale = switch (appState?.listDensityMode) {
      0 => 0.92,
      2 => 1.06,
      _ => 1.0,
    };
    final radius = appState?.coverCornerRadius ?? 6;
    final showSecondary = appState?.showSecondaryInfo ?? true;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(radius),
                ),
                child: SizedBox.expand(
                  child: imageUrl.isEmpty
                      ? _fallback(colorScheme)
                      : CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, _) =>
                              _fallback(colorScheme, showIcon: false),
                          errorWidget: (_, _, _) => _fallback(colorScheme),
                        ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                9 * densityScale,
                8 * densityScale,
                9 * densityScale,
                9 * densityScale,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isEmpty ? '未命名条目' : title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13 * densityScale,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5 * densityScale,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (showSecondary &&
                      (score > 0 || rank > 0 || date.isNotEmpty)) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (score > 0) ...[
                          Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: Colors.amber[700],
                          ),
                          const SizedBox(width: 2),
                          Text(
                            score.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 10.5 * densityScale,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (rank > 0) ...[
                          if (score > 0) const SizedBox(width: 7),
                          Text(
                            '#$rank',
                            style: TextStyle(
                              fontSize: 10.5 * densityScale,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (date.isNotEmpty) ...[
                          const Spacer(),
                          Flexible(
                            child: Text(
                              date,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5 * densityScale,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback(ColorScheme colorScheme, {bool showIcon = true}) {
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: showIcon
            ? Icon(
                Icons.movie_outlined,
                color: colorScheme.onSurfaceVariant,
                size: 32,
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
