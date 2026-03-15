import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/collection.dart';
import '../models/subject.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';

/// 条目操作按钮组件
/// 包含：编辑按钮，打开统一对话框修改收藏、评分、吐槽
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

  /// 打开统一编辑对话框
  void _showEditDialog() {
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isLoggedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }

    showDialog(
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
        return '想看';
      case 2:
        return '看过';
      case 3:
        return '在看';
      case 4:
        return '搁置';
      case 5:
        return '抛弃';
      default:
        return '编辑';
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
        backgroundColor: isCollected ? colorScheme.primary : colorScheme.surface,
        foregroundColor: isCollected ? colorScheme.onPrimary : colorScheme.onSurface,
      ),
    );
  }
}

/// 统一编辑对话框
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
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.collection?.type ?? 0;
    _selectedRating = widget.collection?.rate ?? 0;
  }

  Future<void> _saveChanges() async {
    // 必须选择收藏状态
    if (_selectedType == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择收藏状态')));
      return;
    }

    setState(() => _loading = true);
    try {
      final api = context.read<ApiClient>();

      // 更新收藏信息
      await api.patchCollection(
        subjectId: widget.subject.id,
        type: _selectedType,
        rate: _selectedRating > 0 ? _selectedRating : null,
      );

      if (mounted) {
        widget.onChanged();
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已保存')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('编辑 ${widget.subject.displayName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 收藏状态
            Text(
              '收藏状态',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                onSelectionChanged: _loading ? null : (Set<int> newSelection) {
                  setState(() => _selectedType = newSelection.first);
                },
                selected: <int>{_selectedType},
                segments: const <ButtonSegment<int>>[
                  ButtonSegment<int>(value: 1, label: Text('想看')),
                  ButtonSegment<int>(value: 2, label: Text('看过')),
                  ButtonSegment<int>(value: 3, label: Text('在看')),
                  ButtonSegment<int>(value: 4, label: Text('搁置')),
                  ButtonSegment<int>(value: 5, label: Text('抛弃')),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 评分
            Text(
              '评分',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 2,
                runSpacing: 2,
                children: List.generate(10, (index) {
                  final rating = index + 1;
                  return GestureDetector(
                    onTap: _loading
                        ? null
                        : () {
                            setState(() => _selectedRating = rating);
                          },
                    child: Icon(
                      Icons.star,
                      color: rating <= _selectedRating
                          ? Colors.amber
                          : Colors.grey[300],
                      size: 22,
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _loading ? null : _saveChanges,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}
