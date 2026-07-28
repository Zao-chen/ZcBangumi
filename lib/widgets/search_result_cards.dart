import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/character.dart';
import '../models/person.dart';
import '../models/subject.dart';
import '../pages/character_page.dart';
import '../pages/person_page.dart';
import '../pages/subject_page.dart';
import '../providers/app_state_provider.dart';

class SubjectSearchResultCard extends StatelessWidget {
  final SlimSubject subject;

  const SubjectSearchResultCard({super.key, required this.subject});

  @override
  Widget build(BuildContext context) {
    final details = <Widget>[
      if (subject.score > 0) ...[
        Icon(Icons.star_rounded, size: 14, color: Colors.amber[700]),
        const SizedBox(width: 2),
        Text(subject.score.toStringAsFixed(1)),
      ],
      if (subject.rank > 0) ...[
        const SizedBox(width: 10),
        Text('#${subject.rank}'),
      ],
      if (subject.collectionTotal > 0) ...[
        const Spacer(),
        const Icon(Icons.people_outline, size: 14),
        const SizedBox(width: 2),
        Text('${subject.collectionTotal}'),
      ],
    ];
    return SearchEntityResultCard(
      imageUrl: subject.images?.common ?? '',
      fallbackIcon: Icons.movie_outlined,
      title: subject.displayName,
      subtitle: subject.nameCn.isNotEmpty && subject.name != subject.nameCn
          ? subject.name
          : '',
      summary: subject.shortSummary,
      footer: details,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SubjectPage(subjectId: subject.id)),
      ),
    );
  }
}

class CharacterSearchResultCard extends StatelessWidget {
  final Character character;

  const CharacterSearchResultCard({super.key, required this.character});

  @override
  Widget build(BuildContext context) {
    final imageUrl = character.images.isEmpty
        ? ''
        : _bestImage(
            character.images.first.medium,
            character.images.first.small,
            character.images.first.grid,
          );
    return SearchEntityResultCard(
      imageUrl: imageUrl,
      fallbackIcon: Icons.face_outlined,
      title: character.name,
      subtitle: character.type,
      summary: character.summary,
      footer: [
        if (character.collects > 0) ...[
          const Icon(Icons.favorite_border, size: 14),
          const SizedBox(width: 3),
          Text('${character.collects} 人收藏'),
        ],
        if (character.comments > 0) ...[
          const Spacer(),
          const Icon(Icons.chat_bubble_outline, size: 13),
          const SizedBox(width: 3),
          Text('${character.comments}'),
        ],
      ],
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CharacterPage(character: character)),
      ),
    );
  }
}

class PersonSearchResultCard extends StatelessWidget {
  final PersonSummary person;

  const PersonSearchResultCard({super.key, required this.person});

  @override
  Widget build(BuildContext context) {
    final careerLabels = person.careerLabels;
    return SearchEntityResultCard(
      imageUrl: person.images?.bestSmall ?? '',
      fallbackIcon: Icons.person_outline,
      title: person.name,
      subtitle: [
        person.typeLabel,
        if (careerLabels.isNotEmpty) careerLabels.join(' · '),
      ].join(' · '),
      summary: person.shortSummary,
      footer: const [],
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => PersonPage(person: person))),
    );
  }
}

class SearchEntityResultCard extends StatelessWidget {
  final String imageUrl;
  final IconData fallbackIcon;
  final String title;
  final String subtitle;
  final String summary;
  final List<Widget> footer;
  final VoidCallback onTap;

  const SearchEntityResultCard({
    super.key,
    required this.imageUrl,
    required this.fallbackIcon,
    required this.title,
    required this.subtitle,
    required this.summary,
    required this.footer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appState = context.watch<AppStateProvider?>();
    final densityScale = switch (appState?.listDensityMode) {
      0 => 0.88,
      2 => 1.12,
      _ => 1.0,
    };
    final cardPadding = 10.0 * densityScale;
    final coverWidth = 56.0 * densityScale;
    final coverHeight = 80.0 * densityScale;
    final coverRadius = appState?.coverCornerRadius ?? 6.0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(cardPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(coverRadius),
                child: SizedBox(
                  width: coverWidth,
                  height: coverHeight,
                  child: imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, _) =>
                              _fallback(colorScheme, showIcon: false),
                          errorWidget: (_, _, _) => _fallback(colorScheme),
                        )
                      : _fallback(colorScheme),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: coverHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14 * densityScale,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle.isNotEmpty) ...[
                        SizedBox(height: 4 * densityScale),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11 * densityScale,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (summary.isNotEmpty) ...[
                        SizedBox(height: 4 * densityScale),
                        Text(
                          summary,
                          style: TextStyle(
                            fontSize: 11 * densityScale,
                            color: colorScheme.onSurfaceVariant,
                            height: 1.2,
                          ),
                          maxLines: subtitle.isNotEmpty ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (footer.isNotEmpty) ...[
                        const Spacer(),
                        DefaultTextStyle(
                          style: TextStyle(
                            fontSize: 11 * densityScale,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          child: IconTheme(
                            data: IconThemeData(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            child: Row(children: footer),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallback(ColorScheme colorScheme, {bool showIcon = true}) {
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: showIcon ? Icon(fallbackIcon, size: 26) : const SizedBox.shrink(),
    );
  }
}

String _bestImage(String first, String second, String third) {
  if (first.isNotEmpty) return first;
  if (second.isNotEmpty) return second;
  return third;
}
