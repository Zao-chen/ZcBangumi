import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/collection.dart';
import '../models/subject.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';

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
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('\u5df2\u4fdd\u5b58')));
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
                                const SizedBox(height: 24),
                                _buildRatingSection(context, colorScheme),
                              ],
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
