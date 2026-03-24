import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 可复制的文本Widget
/// 在触屏设备上：短内容长按复制，长文本支持文本选取
/// 在鼠标设备上：都支持文本选取
class CopyableText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow overflow;
  final bool enableLongPressCopy;

  const CopyableText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.enableLongPressCopy = true,
  });

  @override
  State<CopyableText> createState() => _CopyableTextState();
}

class _CopyableTextState extends State<CopyableText> {
  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.text));

    if (mounted) {
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
    // 判断是否是短文本（长度 < 50 字符或不超过2行）
    final isShortText = widget.text.length < 50;

    // 使用SelectableText以支持鼠标选取和触屏选取
    return GestureDetector(
      onLongPress: widget.enableLongPressCopy && isShortText
          ? _copyToClipboard
          : null,
      child: SelectableText(
        widget.text,
        style: widget.style,
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        onSelectionChanged: (selection, cause) {
          // 处理文本选取，这里可以添加额外的逻辑
        },
      ),
    );
  }
}

/// short文本 - 支持长按复制和鼠标拖选
/// 用于非常短的内容如标题、标签等
/// 触屏：长按复制
/// 鼠标设备：鼠标拖选（SelectableText）
class ShortCopyableText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int maxLines;
  final TextOverflow overflow;

  const ShortCopyableText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  @override
  State<ShortCopyableText> createState() => _ShortCopyableTextState();
}

class _ShortCopyableTextState extends State<ShortCopyableText> {
  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.text));

    if (mounted) {
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
    // 短文本用普通 Text 保持原有高度，只支持长按复制
    return GestureDetector(
      onLongPress: _copyToClipboard,
      child: Text(
        widget.text,
        style: widget.style,
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      ),
    );
  }
}
