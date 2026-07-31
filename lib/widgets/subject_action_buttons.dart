import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models/collection.dart';
import '../models/mikan.dart';
import '../models/subject.dart';
import '../providers/auth_provider.dart';
import '../providers/mikan_provider.dart';
import '../pages/settings_page.dart';
import '../services/api_client.dart';
import '../services/mikan_service.dart';
import '../services/platform_feature_support.dart';
import '../utils/mikan_error.dart';
import 'mikan_resource_list.dart';

/// 条目操作按钮组件
/// 包含编辑按钮，打开统一对话框修改收藏、评分、评论。
class SubjectActionButtons extends StatefulWidget {
  final Subject subject;
  final UserCollection? existingCollection;
  final VoidCallback onCollectionChanged;

  const SubjectActionButtons({
    super.key,
    required this.subject,
    this.existingCollection,
    required this.onCollectionChanged,
  });

  @override
  State<SubjectActionButtons> createState() => _SubjectActionButtonsState();
}

class _SubjectActionButtonsState extends State<SubjectActionButtons> {
  late UserCollection? _collection;

  @override
  void initState() {
    super.initState();
    _collection = widget.existingCollection;
  }

  @override
  void didUpdateWidget(SubjectActionButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.existingCollection != widget.existingCollection) {
      _collection = widget.existingCollection;
    }
  }

  void _showEditDialog() {
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isLoggedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('\u8bf7\u5148\u767b\u5f55')));
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) => _UnifiedEditDialog(
        subject: widget.subject,
        collection: _collection,
        onChanged: () {
          setState(() {});
          widget.onCollectionChanged();
        },
      ),
    );
  }

  String _getCollectionTypeLabel(int? type) {
    switch (type) {
      case 1:
        return '\u60f3\u770b';
      case 2:
        return '\u770b\u8fc7';
      case 3:
        return '\u5728\u770b';
      case 4:
        return '\u6401\u7f6e';
      case 5:
        return '\u629b\u5f03';
      default:
        return '\u7f16\u8f91';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = _getCollectionTypeLabel(_collection?.type);
    final isCollected = _collection?.type != null && _collection!.type > 0;

    return FilledButton.icon(
      onPressed: _showEditDialog,
      icon: const Icon(Icons.edit, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        backgroundColor: isCollected
            ? colorScheme.primary
            : colorScheme.surface,
        foregroundColor: isCollected
            ? colorScheme.onPrimary
            : colorScheme.onSurface,
      ),
    );
  }
}

class MikanSubscriptionButton extends StatefulWidget {
  final Subject subject;

  const MikanSubscriptionButton({super.key, required this.subject});

  @override
  State<MikanSubscriptionButton> createState() =>
      _MikanSubscriptionButtonState();
}

class _MikanSubscriptionButtonState extends State<MikanSubscriptionButton> {
  MikanSubjectMapping? _mapping;

  bool get _isAnime => widget.subject.type == BgmConst.subjectAnime;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isAnime) return;
    if (!PlatformFeatureSupport.mikan) return;
    _mapping ??= context.read<MikanProvider>().mappingForSubject(
      widget.subject.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAnime) return const SizedBox.shrink();
    if (!PlatformFeatureSupport.mikan) return const SizedBox.shrink();

    final mikan = context.watch<MikanProvider>();
    if (!mikan.isEnabled) return const SizedBox.shrink();

    final mapping = _mapping ?? mikan.mappingForSubject(widget.subject.id);
    final subscribed = mapping?.subscribed == true;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: OutlinedButton.icon(
        onPressed: _handlePressed,
        icon: Icon(
          subscribed
              ? Icons.notifications_active
              : Icons.notifications_none_outlined,
          size: 18,
        ),
        label: const Text('追番', style: TextStyle(fontSize: 13)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
    );
  }

  Future<void> _handlePressed() async {
    await showMikanSubscriptionDialog(context, widget.subject);
    if (!mounted) return;
    setState(() {
      _mapping = context.read<MikanProvider>().mappingForSubject(
        widget.subject.id,
      );
    });
  }
}

Future<void> showMikanSubscriptionDialog(
  BuildContext context,
  Subject subject, {
  String initialEpisode = '',
  String initialSubgroup = '',
  bool showResources = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _MikanSubscriptionDialog(
      subject: subject,
      initialEpisode: initialEpisode,
      initialSubgroup: initialSubgroup,
      showResources: showResources,
    ),
  );
}

class _MikanSubscriptionDialog extends StatefulWidget {
  final Subject subject;
  final String initialEpisode;
  final String initialSubgroup;
  final bool showResources;

  const _MikanSubscriptionDialog({
    required this.subject,
    required this.initialEpisode,
    required this.initialSubgroup,
    required this.showResources,
  });

  @override
  State<_MikanSubscriptionDialog> createState() =>
      _MikanSubscriptionDialogState();
}

class _MikanSubscriptionDialogState extends State<_MikanSubscriptionDialog> {
  bool _loading = false;
  MikanSubjectMapping? _mapping;
  Future<MikanBangumiDetail>? _detailFuture;
  late bool _showResources;
  late String _resourceEpisode;
  late String _resourceSubgroup;

  @override
  void initState() {
    super.initState();
    _mapping = context.read<MikanProvider>().mappingForSubject(
      widget.subject.id,
    );
    _showResources = widget.showResources;
    _resourceEpisode = widget.initialEpisode;
    _resourceSubgroup = widget.initialSubgroup;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshMapping());
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final mikan = context.watch<MikanProvider>();
    final mapping = _mapping ?? mikan.mappingForSubject(widget.subject.id);
    final subjectTitle = widget.subject.nameCn.isNotEmpty
        ? widget.subject.nameCn
        : widget.subject.name;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: size.width * 0.06,
        vertical: size.height * 0.06,
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size.width * 0.88,
        height: size.height * 0.88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _showResources ? 'Mikan 资源' : 'Mikan 订阅',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subjectTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _loading ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: mapping == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _selectBangumi,
                          icon: const Icon(Icons.search),
                          label: const Text('选择 Mikan 番组'),
                        ),
                      ),
                    )
                  : _buildSubgroupList(context, mikan, mapping),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _loading ? null : () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubgroupList(
    BuildContext context,
    MikanProvider mikan,
    MikanSubjectMapping mapping,
  ) {
    _detailFuture ??= mikan.getBangumiDetail(mapping.bangumiId);
    return FutureBuilder<MikanBangumiDetail>(
      future: _detailFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _buildLoadError(context, snapshot.error!);
        }

        final detail = snapshot.data;
        final subgroups = detail?.subgroupBangumis ?? const [];
        if (detail == null || subgroups.isEmpty) {
          return const Center(child: Text('暂无字幕组或资源'));
        }

        if (_showResources) {
          return _buildResources(context, mikan, detail);
        }

        final subgroupList = Column(
          children: subgroups
              .map(
                (item) => _MikanSubgroupActionTile(
                  mapping: _mappingForSubgroup(mapping, detail, item),
                  subgroup: item,
                  loggedIn: mikan.isLoggedIn,
                  loading: _loading,
                  onSubscribe: () => _syncSubgroup(
                    mapping: _mappingForSubgroup(mapping, detail, item),
                    subscribe: !item.subscribed,
                  ),
                  onLogin: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  ),
                  onResources: () {
                    final target = _mappingForSubgroup(mapping, detail, item);
                    setState(() {
                      _showResources = true;
                      _resourceEpisode = '';
                      _resourceSubgroup = target.subgroupName;
                    });
                  },
                ),
              )
              .toList(),
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: subgroupList,
        );
      },
    );
  }

  Widget _buildResources(
    BuildContext context,
    MikanProvider mikan,
    MikanBangumiDetail detail,
  ) {
    final records = mikan.recordsFromDetail(detail);
    final episode = _resourceEpisode.trim();
    final hasEpisode =
        episode.isEmpty ||
        records.any((item) => _sameEpisode(item.episode, episode));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('mikan_resources_back'),
                onPressed: () => setState(() => _showResources = false),
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: '返回字幕组与订阅',
              ),
              Expanded(
                child: Text(
                  episode.isEmpty ? '整季资源' : 'EP.$episode 资源',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${records.length} 个',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (!hasEpisode)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('未识别到 EP.$episode 的资源，当前显示整季 ${records.length} 个资源。'),
          ),
        if (records.isEmpty)
          const Expanded(child: Center(child: Text('暂无资源')))
        else
          Expanded(
            child: MikanResourceList(
              records: records,
              initialEpisode: _resourceEpisode,
              initialSubgroup: _resourceSubgroup,
            ),
          ),
      ],
    );
  }

  bool _sameEpisode(String a, String b) {
    final normalizedA = a.trim();
    final normalizedB = b.trim();
    if (normalizedA == normalizedB) return true;
    final numberA = num.tryParse(normalizedA);
    final numberB = num.tryParse(normalizedB);
    return numberA != null && numberB != null && numberA == numberB;
  }

  Widget _buildLoadError(BuildContext context, Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 42),
            const SizedBox(height: 12),
            Text(mikanErrorMessage(error), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(onPressed: _retryDetail, child: const Text('重试')),
                OutlinedButton(
                  onPressed: _switchSite,
                  child: const Text('切换站点'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _retryDetail() {
    setState(() => _detailFuture = null);
  }

  Future<void> _switchSite() async {
    final mikan = context.read<MikanProvider>();
    final urls = MikanService.availableBaseUrls;
    final index = urls.indexOf(mikan.baseUrl);
    await mikan.setBaseUrl(urls[(index + 1) % urls.length]);
    if (!mounted) return;
    _retryDetail();
  }

  Future<void> _refreshMapping() async {
    final mikan = context.read<MikanProvider>();
    final saved = _mapping;
    if (saved == null) {
      final exact = await _runWithLoading(
        () => mikan.findExactMapping(widget.subject),
      );
      if (!mounted || exact == null) return;
      setState(() {
        _mapping = exact;
        _detailFuture = null;
      });
      return;
    }

    final refreshed = await _runWithLoading(() => mikan.refreshMapping(saved));
    if (!mounted || refreshed == null) return;
    setState(() {
      _mapping = refreshed;
      _detailFuture = null;
    });
  }

  Future<void> _selectBangumi() async {
    final mikan = context.read<MikanProvider>();
    final candidates = await _runWithLoading(
      () => mikan.searchBangumiCandidates(widget.subject),
    );
    if (!mounted || candidates == null) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有找到 Mikan 候选番组')));
      return;
    }

    final selectedBangumi = await showModalBottomSheet<MikanBangumi>(
      context: context,
      showDragHandle: true,
      builder: (context) => _MikanBangumiPicker(candidates: candidates),
    );
    if (selectedBangumi == null || !mounted) return;

    final detail = await _runWithLoading(
      () => mikan.getBangumiDetail(selectedBangumi.id),
    );
    if (detail == null || !mounted) return;

    final mapping = MikanSubjectMapping.fromSelection(
      subjectId: widget.subject.id,
      bangumi: MikanBangumi(
        id: selectedBangumi.id,
        name: detail.name.isNotEmpty ? detail.name : selectedBangumi.name,
        cover: detail.cover.isNotEmpty ? detail.cover : selectedBangumi.cover,
        subscribed: detail.subscribed || selectedBangumi.subscribed,
      ),
    );
    await mikan.saveMapping(mapping);
    if (!mounted) return;
    setState(() {
      _mapping = mapping;
      _detailFuture = Future.value(detail);
    });
  }

  Future<void> _syncSubgroup({
    required MikanSubjectMapping mapping,
    required bool subscribe,
  }) async {
    final mikan = context.read<MikanProvider>();
    final next = await _runWithLoading(() async {
      await mikan.syncSubscription(mapping: mapping, subscribe: subscribe);
      return mikan.refreshMapping(mapping);
    });
    if (!mounted || next == null) return;
    setState(() {
      _mapping = next;
      _detailFuture = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(subscribe ? 'Mikan 已订阅' : 'Mikan 已取消订阅')),
    );
  }

  MikanSubjectMapping _mappingForSubgroup(
    MikanSubjectMapping base,
    MikanBangumiDetail detail,
    MikanSubgroupBangumi subgroup,
  ) {
    return base.copyWith(
      bangumiName: detail.name.isNotEmpty ? detail.name : base.bangumiName,
      bangumiCover: detail.cover.isNotEmpty ? detail.cover : base.bangumiCover,
      subgroupId: subgroup.dataId,
      subgroupName: subgroup.name,
      rss: subgroup.rss,
      subscribed: subgroup.subscribed,
      updatedAt: DateTime.now(),
    );
  }

  Future<T?> _runWithLoading<T>(Future<T> Function() run) async {
    if (mounted) setState(() => _loading = true);
    try {
      return await run();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mikanErrorMessage(e))));
      }
      return null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _UnifiedEditDialog extends StatefulWidget {
  final Subject subject;
  final UserCollection? collection;
  final VoidCallback onChanged;

  const _UnifiedEditDialog({
    required this.subject,
    required this.collection,
    required this.onChanged,
  });

  @override
  State<_UnifiedEditDialog> createState() => _UnifiedEditDialogState();
}

class _UnifiedEditDialogState extends State<_UnifiedEditDialog> {
  late int _selectedType;
  late int _selectedRating;
  late bool _isPrivate;
  late final TextEditingController _commentController;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.collection?.type ?? 0;
    _selectedRating = widget.collection?.rate ?? 0;
    _isPrivate = widget.collection?.private_ ?? false;
    _commentController = TextEditingController(
      text: widget.collection?.comment ?? '',
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (_selectedType == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('\u8bf7\u9009\u62e9\u6536\u85cf\u72b6\u6001'),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final api = context.read<ApiClient>();
      final comment = _commentController.text.trim();
      final existingComment = widget.collection?.comment?.trim() ?? '';
      final existingPrivate = widget.collection?.private_ ?? false;

      await api.patchCollection(
        subjectId: widget.subject.id,
        type: _selectedType,
        rate: _selectedRating > 0 ? _selectedRating : null,
        comment: comment != existingComment ? comment : null,
        private_: _isPrivate != existingPrivate ? _isPrivate : null,
      );

      if (!mounted) return;
      widget.onChanged();
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('\u5df2\u4fdd\u5b58')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('\u4fdd\u5b58\u5931\u8d25: $e')));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  Widget _buildCollectionTypeSelector(BuildContext context) {
    const options = <(int, String)>[
      (1, '\u60f3\u770b'),
      (2, '\u770b\u8fc7'),
      (3, '\u5728\u770b'),
      (4, '\u6401\u7f6e'),
      (5, '\u629b\u5f03'),
    ];
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 6.0;
        final itemWidth =
            (constraints.maxWidth - gap * (options.length - 1)) /
            options.length;
        final compact = itemWidth < 64;

        return Row(
          children: List.generate(options.length, (index) {
            final (value, label) = options[index];
            final selected = _selectedType == value;
            return Padding(
              padding: EdgeInsets.only(
                right: index == options.length - 1 ? 0 : gap,
              ),
              child: SizedBox(
                width: itemWidth,
                child: OutlinedButton(
                  onPressed: _loading
                      ? null
                      : () {
                          setState(() => _selectedType = value);
                        },
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 2 : 4,
                      vertical: compact ? 8 : 10,
                    ),
                    visualDensity: compact
                        ? const VisualDensity(horizontal: -3, vertical: -2)
                        : VisualDensity.standard,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: BorderSide(
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.outline,
                    ),
                    foregroundColor: selected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface,
                    backgroundColor: selected
                        ? colorScheme.primary
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label, maxLines: 1),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildRatingSection(
    BuildContext context,
    ColorScheme colorScheme, {
    bool compact = false,
  }) {
    final starSize = compact ? 26.0 : 28.0;
    final topGap = compact ? 6.0 : 8.0;
    final cardPadding = compact ? 10.0 : 12.0;
    final starGap = compact ? 3.0 : 4.0;
    final scoreGap = compact ? 6.0 : 8.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSectionTitle(context, '\u8bc4\u5206'),
            const Spacer(),
            TextButton(
              onPressed: _loading || _selectedRating == 0
                  ? null
                  : () => setState(() => _selectedRating = 0),
              child: const Text('\u6e05\u9664\u8bc4\u5206'),
            ),
          ],
        ),
        SizedBox(height: topGap),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(cardPadding),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (starIndex) {
                  final fullStarThreshold = (starIndex + 1) * 2;

                  bool isFull = _selectedRating >= fullStarThreshold;
                  bool isHalf =
                      _selectedRating >= (starIndex * 2 + 1) &&
                      _selectedRating < fullStarThreshold;

                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: starGap),
                    child: GestureDetector(
                      onTapDown: _loading
                          ? null
                          : (details) {
                              final isHalfTap =
                                  details.localPosition.dx < starSize / 2;
                              setState(() {
                                _selectedRating = isHalfTap
                                    ? (starIndex + 1) * 2 - 1
                                    : (starIndex + 1) * 2;
                              });
                            },
                      behavior: HitTestBehavior.opaque,
                      child: SizedBox(
                        width: starSize,
                        height: starSize,
                        child: Stack(
                          children: [
                            Icon(
                              Icons.star,
                              color: colorScheme.outline,
                              size: starSize,
                            ),
                            if (isHalf)
                              ClipRect(
                                clipper: _HalfClipper(isLeftHalf: true),
                                child: Icon(
                                  Icons.star,
                                  color: Colors.amber.shade700,
                                  size: starSize,
                                ),
                              )
                            else if (isFull)
                              Icon(
                                Icons.star,
                                color: Colors.amber.shade700,
                                size: starSize,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
              SizedBox(height: scoreGap),
              Text(
                _selectedRating > 0
                    ? '\u5f53\u524d\u8bc4\u5206 $_selectedRating / 10'
                    : '\u5f53\u524d\u672a\u8bc4\u5206',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape &&
        size.width >= 700;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: size.width * 0.06,
        vertical: size.height * 0.06,
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size.width * 0.88,
        height: size.height * 0.88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '\u7f16\u8f91\u6536\u85cf',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.subject.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _loading ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: '\u5173\u95ed',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: isLandscape
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSectionTitle(
                                    context,
                                    '\u6536\u85cf\u72b6\u6001',
                                  ),
                                  const SizedBox(height: 8),
                                  _buildCollectionTypeSelector(context),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildSectionTitle(
                                          context,
                                          '\u79c1\u5bc6',
                                        ),
                                      ),
                                      Switch(
                                        value: _isPrivate,
                                        onChanged: _loading
                                            ? null
                                            : (value) {
                                                setState(
                                                  () => _isPrivate = value,
                                                );
                                              },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  _buildRatingSection(context, colorScheme),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSectionTitle(context, '\u8bc4\u8bba'),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _commentController,
                                    enabled: !_loading,
                                    expands: true,
                                    minLines: null,
                                    maxLines: null,
                                    maxLength: 380,
                                    textAlignVertical: TextAlignVertical.top,
                                    decoration: const InputDecoration(
                                      hintText:
                                          '\u5199\u70b9\u6536\u85cf\u611f\u60f3\uff0c\u53ef\u7559\u7a7a',
                                      border: OutlineInputBorder(),
                                      alignLabelWithHint: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle(
                            context,
                            '\u6536\u85cf\u72b6\u6001',
                          ),
                          const SizedBox(height: 8),
                          _buildCollectionTypeSelector(context),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _buildSectionTitle(
                                  context,
                                  '\u79c1\u5bc6',
                                ),
                              ),
                              Switch(
                                value: _isPrivate,
                                onChanged: _loading
                                    ? null
                                    : (value) {
                                        setState(() => _isPrivate = value);
                                      },
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _buildRatingSection(
                            context,
                            colorScheme,
                            compact: true,
                          ),
                          const SizedBox(height: 14),
                          _buildSectionTitle(context, '\u8bc4\u8bba'),
                          const SizedBox(height: 6),
                          Expanded(
                            child: TextField(
                              controller: _commentController,
                              enabled: !_loading,
                              expands: true,
                              minLines: null,
                              maxLines: null,
                              maxLength: 380,
                              textAlignVertical: TextAlignVertical.top,
                              decoration: const InputDecoration(
                                hintText:
                                    '\u5199\u70b9\u6536\u85cf\u611f\u60f3\uff0c\u53ef\u7559\u7a7a',
                                border: OutlineInputBorder(),
                                alignLabelWithHint: true,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _loading ? null : () => Navigator.pop(context),
                    child: const Text('\u53d6\u6d88'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _loading ? null : _saveChanges,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('\u4fdd\u5b58'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 用于显示半颗星的裁剪器
class _HalfClipper extends CustomClipper<Rect> {
  final bool isLeftHalf;

  _HalfClipper({this.isLeftHalf = true});

  @override
  Rect getClip(Size size) {
    if (isLeftHalf) {
      return Rect.fromLTWH(0, 0, size.width / 2, size.height);
    } else {
      return Rect.fromLTWH(size.width / 2, 0, size.width / 2, size.height);
    }
  }

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

class _MikanBangumiPicker extends StatelessWidget {
  final List<MikanBangumi> candidates;

  const _MikanBangumiPicker({required this.candidates});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Text(
                    '选择 Mikan 番组',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: candidates.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = candidates[index];
                  return ListTile(
                    leading: const Icon(Icons.movie_outlined),
                    title: Text(item.name),
                    subtitle: item.updateAt.isEmpty
                        ? null
                        : Text('更新：${item.updateAt}'),
                    trailing: item.subscribed
                        ? const Icon(Icons.notifications_active)
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).pop(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MikanSubgroupActionTile extends StatelessWidget {
  final MikanSubjectMapping mapping;
  final MikanSubgroupBangumi subgroup;
  final bool loggedIn;
  final bool loading;
  final VoidCallback onSubscribe;
  final VoidCallback onLogin;
  final VoidCallback onResources;

  const _MikanSubgroupActionTile({
    required this.mapping,
    required this.subgroup,
    required this.loggedIn,
    required this.loading,
    required this.onSubscribe,
    required this.onLogin,
    required this.onResources,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subscribed = subgroup.subscribed;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                subscribed
                    ? Icons.notifications_active
                    : Icons.subscriptions_outlined,
                color: subscribed
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subgroup.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        subscribed ? '已订阅' : '未订阅',
                        if (subgroup.sublang.isNotEmpty) subgroup.sublang,
                        '${subgroup.records.length} 个资源',
                      ].join(' · '),
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: loading
                    ? null
                    : loggedIn
                    ? onSubscribe
                    : onLogin,
                icon: Icon(
                  loggedIn
                      ? subscribed
                            ? Icons.notifications_off_outlined
                            : Icons.notifications_active_outlined
                      : Icons.login_rounded,
                ),
                label: Text(
                  loggedIn
                      ? subscribed
                            ? '取消订阅'
                            : '订阅'
                      : '登录后订阅',
                ),
              ),
              OutlinedButton.icon(
                onPressed: loading ? null : onResources,
                icon: const Icon(Icons.download_outlined),
                label: const Text('查看资源'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
