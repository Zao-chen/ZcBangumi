import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/mikan.dart';
import '../services/link_navigator.dart';

class MikanResourceList extends StatefulWidget {
  final List<MikanRecordItem> records;
  final bool scrollable;
  final String initialEpisode;
  final String initialSubgroup;

  const MikanResourceList({
    super.key,
    required this.records,
    this.scrollable = true,
    this.initialEpisode = '',
    this.initialSubgroup = '',
  });

  @override
  State<MikanResourceList> createState() => _MikanResourceListState();
}

class _MikanResourceListState extends State<MikanResourceList> {
  late String _episode;
  late String _subgroup;
  String _subtitleType = '';
  String _tag = '';

  @override
  void initState() {
    super.initState();
    _episode = _resolveInitialEpisode(widget.initialEpisode);
    _subgroup = _resolveInitialSubgroup(widget.initialSubgroup);
  }

  @override
  void didUpdateWidget(MikanResourceList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialEpisode != widget.initialEpisode) {
      _episode = _resolveInitialEpisode(widget.initialEpisode);
    }
    if (oldWidget.initialSubgroup != widget.initialSubgroup) {
      _subgroup = _resolveInitialSubgroup(widget.initialSubgroup);
    }
    if (oldWidget.records == widget.records) return;
    final episodes = _episodes;
    final subgroups = _subgroups;
    final subtitleTypes = _subtitleTypes;
    final tags = _tags;
    if (_episode.isNotEmpty && !episodes.contains(_episode)) {
      _episode = '';
    }
    if (_subgroup.isNotEmpty && !subgroups.contains(_subgroup)) {
      _subgroup = '';
    }
    if (_subtitleType.isNotEmpty && !subtitleTypes.contains(_subtitleType)) {
      _subtitleType = '';
    }
    if (_tag.isNotEmpty && !tags.contains(_tag)) {
      _tag = '';
    }
  }

  List<String> get _episodes {
    final values = <String>[];
    for (final item in widget.records) {
      final episode = item.episode.trim();
      if (episode.isEmpty ||
          values.any((value) => _sameEpisode(value, episode))) {
        continue;
      }
      values.add(episode);
    }
    values.sort(_compareEpisode);
    return values;
  }

  String _resolveInitialEpisode(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return '';
    final episodes = _episodes;
    if (episodes.contains(normalized)) return normalized;
    final target = num.tryParse(normalized);
    if (target == null) return '';
    for (final episode in episodes) {
      if (num.tryParse(episode) == target) return episode;
    }
    return '';
  }

  List<String> get _subtitleTypes {
    final values = widget.records
        .map((item) => item.subtitleType)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    values.sort();
    return values;
  }

  List<String> get _subgroups {
    final values = widget.records
        .map((item) => item.subgroupName)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    values.sort();
    return values;
  }

  String _resolveInitialSubgroup(String value) {
    final normalized = value.trim();
    return _subgroups.contains(normalized) ? normalized : '';
  }

  List<String> get _tags {
    final values = widget.records
        .expand((item) => item.tags)
        .where((tag) => tag.isNotEmpty && tag != '简' && tag != '繁')
        .toSet()
        .toList();
    values.sort(_compareTag);
    return values;
  }

  List<MikanRecordItem> get _filteredRecords {
    return widget.records.where((item) {
      if (_episode.isNotEmpty && !_sameEpisode(item.episode, _episode)) {
        return false;
      }
      if (_subgroup.isNotEmpty && item.subgroupName != _subgroup) return false;
      if (_subtitleType.isNotEmpty && item.subtitleType != _subtitleType) {
        return false;
      }
      if (_tag.isNotEmpty && !item.tags.contains(_tag)) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredRecords = _filteredRecords;
    final children = [
      if (_episodes.isNotEmpty ||
          _subgroups.isNotEmpty ||
          _subtitleTypes.isNotEmpty ||
          _tags.isNotEmpty)
        Padding(
          padding: EdgeInsets.fromLTRB(12, widget.scrollable ? 12 : 0, 12, 8),
          child: _MikanResourceFilters(
            episodes: _episodes,
            subgroups: _subgroups,
            subtitleTypes: _subtitleTypes,
            tags: _tags,
            selectedEpisode: _episode,
            selectedSubgroup: _subgroup,
            selectedSubtitleType: _subtitleType,
            selectedTag: _tag,
            filteredCount: filteredRecords.length,
            totalCount: widget.records.length,
            onEpisodeChanged: (value) => setState(() => _episode = value),
            onSubgroupChanged: (value) => setState(() => _subgroup = value),
            onSubtitleTypeChanged: (value) =>
                setState(() => _subtitleType = value),
            onTagChanged: (value) => setState(() => _tag = value),
          ),
        ),
      if (filteredRecords.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('没有符合筛选的资源')),
        )
      else if (widget.scrollable)
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            itemCount: filteredRecords.length,
            itemBuilder: (context, index) =>
                _MikanRecordTile(item: filteredRecords[index]),
          ),
        )
      else
        ...filteredRecords.map(
          (item) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0),
            child: _MikanRecordTile(item: item),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  int _compareEpisode(String a, String b) {
    final aNumber = num.tryParse(a);
    final bNumber = num.tryParse(b);
    if (aNumber != null && bNumber != null) {
      return aNumber.compareTo(bNumber);
    }
    return a.compareTo(b);
  }

  bool _sameEpisode(String a, String b) {
    final normalizedA = a.trim();
    final normalizedB = b.trim();
    if (normalizedA == normalizedB) return true;
    final aNumber = num.tryParse(normalizedA);
    final bNumber = num.tryParse(normalizedB);
    return aNumber != null && bNumber != null && aNumber == bNumber;
  }

  int _compareTag(String a, String b) {
    final aResolution = _resolution(a);
    final bResolution = _resolution(b);
    if (aResolution != null && bResolution != null) {
      return bResolution.compareTo(aResolution);
    }
    if (aResolution != null) return -1;
    if (bResolution != null) return 1;
    return a.compareTo(b);
  }

  int? _resolution(String value) {
    final match = RegExp(r'^(\d{3,4})P$').firstMatch(value.toUpperCase());
    return int.tryParse(match?.group(1) ?? '');
  }
}

class _MikanResourceFilters extends StatelessWidget {
  final List<String> episodes;
  final List<String> subgroups;
  final List<String> subtitleTypes;
  final List<String> tags;
  final String selectedEpisode;
  final String selectedSubgroup;
  final String selectedSubtitleType;
  final String selectedTag;
  final int filteredCount;
  final int totalCount;
  final ValueChanged<String> onEpisodeChanged;
  final ValueChanged<String> onSubgroupChanged;
  final ValueChanged<String> onSubtitleTypeChanged;
  final ValueChanged<String> onTagChanged;

  const _MikanResourceFilters({
    required this.episodes,
    required this.subgroups,
    required this.subtitleTypes,
    required this.tags,
    required this.selectedEpisode,
    required this.selectedSubgroup,
    required this.selectedSubtitleType,
    required this.selectedTag,
    required this.filteredCount,
    required this.totalCount,
    required this.onEpisodeChanged,
    required this.onSubgroupChanged,
    required this.onSubtitleTypeChanged,
    required this.onTagChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      key: const ValueKey('mikan_resource_filters_scroll'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.filter_list, size: 18, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  '$filteredCount / $totalCount',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (episodes.isNotEmpty) ...[
            const SizedBox(width: 8),
            _MikanFilterDropdown(
              key: const ValueKey('mikan_episode_filter'),
              label: '集数',
              options: episodes,
              selected: selectedEpisode,
              optionLabel: (value) => 'EP.$value',
              onChanged: onEpisodeChanged,
            ),
          ],
          if (subgroups.isNotEmpty) ...[
            const SizedBox(width: 8),
            _MikanFilterDropdown(
              key: const ValueKey('mikan_subgroup_filter'),
              label: '字幕组',
              options: subgroups,
              selected: selectedSubgroup,
              onChanged: onSubgroupChanged,
            ),
          ],
          if (subtitleTypes.isNotEmpty) ...[
            const SizedBox(width: 8),
            _MikanFilterDropdown(
              key: const ValueKey('mikan_subtitle_filter'),
              label: '字幕',
              options: subtitleTypes,
              selected: selectedSubtitleType,
              onChanged: onSubtitleTypeChanged,
            ),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(width: 8),
            _MikanFilterDropdown(
              key: const ValueKey('mikan_tag_filter'),
              label: '标签',
              options: tags,
              selected: selectedTag,
              onChanged: onTagChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _MikanFilterDropdown extends StatelessWidget {
  final String label;
  final List<String> options;
  final String selected;
  final String Function(String value)? optionLabel;
  final ValueChanged<String> onChanged;

  const _MikanFilterDropdown({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.optionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.labelLarge;
    final width = switch (label) {
      '字幕' => 148.0,
      '字幕组' => 168.0,
      '集数' => 106.0,
      _ => 104.0,
    };
    return Container(
      height: 40,
      width: width,
      padding: const EdgeInsets.only(left: 10, right: 6),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selected,
            isDense: true,
            isExpanded: true,
            focusColor: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            style: textStyle?.copyWith(color: colorScheme.onSurface),
            icon: const Icon(Icons.arrow_drop_down, size: 20),
            onChanged: (value) {
              if (value == null) return;
              onChanged(value);
            },
            items: [
              DropdownMenuItem(value: '', child: Text('$label: 全部')),
              ...options.map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text('$label: ${optionLabel?.call(value) ?? value}'),
                ),
              ),
            ],
            selectedItemBuilder: (context) => [
              Text('$label: 全部', overflow: TextOverflow.ellipsis),
              ...options.map(
                (value) => Text(
                  '$label: ${optionLabel?.call(value) ?? value}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MikanRecordTile extends StatelessWidget {
  final MikanRecordItem item;

  const _MikanRecordTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetails(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              _MikanRecordMeta(item: item),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        if (item.size.isNotEmpty) item.size,
                        if (item.publishAt.isNotEmpty) item.publishAt,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                  IconButton(
                    onPressed: item.magnet.isEmpty
                        ? null
                        : () => _copyMagnet(context, item.magnet),
                    icon: const Icon(Icons.copy),
                    tooltip: '复制磁链',
                  ),
                  IconButton(
                    onPressed: item.magnet.isEmpty
                        ? null
                        : () => _openUri(context, item.magnet),
                    icon: const Icon(Icons.link),
                    tooltip: '打开磁链',
                  ),
                  IconButton(
                    onPressed: item.torrent.isEmpty
                        ? null
                        : () => _openUri(context, item.torrent),
                    icon: const Icon(Icons.download_outlined),
                    tooltip: '打开种子',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDetails(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: _MikanRecordDetails(
            item: item,
            onCopyMagnet: () => _copyMagnet(context, item.magnet),
            onOpenMagnet: () => _openUri(context, item.magnet),
            onOpenTorrent: () => _openUri(context, item.torrent),
            onOpenPage: () => _openUri(context, item.url),
          ),
        ),
      ),
    );
  }

  Future<void> _copyMagnet(BuildContext context, String magnet) async {
    await Clipboard.setData(ClipboardData(text: magnet));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('磁链已复制')));
  }

  Future<void> _openUri(BuildContext context, String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    final ok = await LinkNavigator.openBrowser(uri);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('打开失败')));
    }
  }
}

class _MikanRecordMeta extends StatelessWidget {
  final MikanRecordItem item;

  const _MikanRecordMeta({required this.item});

  @override
  Widget build(BuildContext context) {
    final chips = [
      if (item.subgroupName.isNotEmpty) item.subgroupName,
      if (item.episode.isNotEmpty) 'EP.${item.episode}',
      if (item.subtitleType.isNotEmpty) item.subtitleType,
      ...item.tags.where((tag) => tag != item.subtitleType),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips
          .map(
            (label) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _MikanRecordDetails extends StatelessWidget {
  final MikanRecordItem item;
  final VoidCallback onCopyMagnet;
  final VoidCallback onOpenMagnet;
  final VoidCallback onOpenTorrent;
  final VoidCallback onOpenPage;

  const _MikanRecordDetails({
    required this.item,
    required this.onCopyMagnet,
    required this.onOpenMagnet,
    required this.onOpenTorrent,
    required this.onOpenPage,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '资源详情',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(
            item.title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          _MikanRecordMeta(item: item),
          const SizedBox(height: 14),
          _MikanDetailRow(label: '大小', value: item.size),
          _MikanDetailRow(label: '发布时间', value: item.publishAt),
          _MikanDetailRow(label: '资源页', value: item.url),
          if (item.magnet.isNotEmpty)
            _MikanDetailRow(label: '磁链', value: item.magnet),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: item.magnet.isEmpty ? null : onCopyMagnet,
                icon: const Icon(Icons.copy),
                label: const Text('复制磁链'),
              ),
              FilledButton.tonalIcon(
                onPressed: item.magnet.isEmpty ? null : onOpenMagnet,
                icon: const Icon(Icons.link),
                label: const Text('打开磁链'),
              ),
              OutlinedButton.icon(
                onPressed: item.torrent.isEmpty ? null : onOpenTorrent,
                icon: const Icon(Icons.download_outlined),
                label: const Text('打开种子'),
              ),
              OutlinedButton.icon(
                onPressed: item.url.isEmpty ? null : onOpenPage,
                icon: const Icon(Icons.open_in_new),
                label: const Text('资源页'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MikanDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _MikanDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(value),
        ],
      ),
    );
  }
}
