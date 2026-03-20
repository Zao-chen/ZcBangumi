import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 可复制的Chip - 用于标签等
/// 触屏：长按复制
/// 鼠标设备：鼠标拖选标签内容，或长按复制
class CopyableChip extends StatelessWidget {
  final String label;
  final TextStyle? labelStyle;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  const CopyableChip({
    super.key,
    required this.label,
    this.labelStyle,
    this.backgroundColor,
    this.padding,
    this.onTap,
  });

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: label));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已复制'),
          duration: const Duration(milliseconds: 800),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _copyToClipboard(context),
      onTap: onTap,
      child: Tooltip(
        message: '长按复制',
        child: Chip(
          label: Text(label, style: labelStyle),
          backgroundColor: backgroundColor,
          padding: padding,
        ),
      ),
    );
  }
}
