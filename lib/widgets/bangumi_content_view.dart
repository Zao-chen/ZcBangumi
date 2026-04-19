import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import '../constants.dart';
import '../services/link_navigator.dart';

class BangumiContentView extends StatelessWidget {
  final String text;
  final String? html;
  final TextStyle? style;
  final double? smileSize;

  const BangumiContentView({
    super.key,
    required this.text,
    this.html,
    this.style,
    this.smileSize,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? DefaultTextStyle.of(context).style;
    final fontSize = effectiveStyle.fontSize ?? 14;
    final lineHeight = effectiveStyle.height ?? 1.4;
    final resolvedSmileSize = smileSize ?? (fontSize * 1.35);
    final colorScheme = Theme.of(context).colorScheme;
    final trimmedHtml = html?.trim();

    if (trimmedHtml != null && trimmedHtml.isNotEmpty) {
      return Html(
        data: _wrapHtml(trimmedHtml),
        style: {
          'html': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
          'body': Style(
            margin: Margins.zero,
            padding: HtmlPaddings.zero,
            fontSize: FontSize(fontSize),
            lineHeight: LineHeight(lineHeight),
            color: effectiveStyle.color,
          ),
          'p': Style(margin: Margins.only(bottom: 6)),
          'a': Style(
            color: colorScheme.primary,
            textDecoration: TextDecoration.underline,
          ),
          '.text_mask': Style(
            color: colorScheme.onSurfaceVariant,
            backgroundColor: colorScheme.surfaceContainerHighest,
          ),
          '.inner': Style(
            color: colorScheme.onSurfaceVariant,
            backgroundColor: colorScheme.surfaceContainerHighest,
          ),
        },
        onLinkTap: (url, attributes, element) {
          if (url == null || url.trim().isEmpty) return;
          _openLink(context, url.trim());
        },
      );
    }

    final spans = _buildTextSpans(
      text: text,
      style: effectiveStyle,
      smileSize: resolvedSmileSize,
    );
    return SelectionArea(
      child: Text.rich(TextSpan(style: effectiveStyle, children: spans)),
    );
  }

  static List<InlineSpan> _buildTextSpans({
    required String text,
    required TextStyle style,
    required double smileSize,
  }) {
    if (text.isEmpty) {
      return const [TextSpan(text: ' ')];
    }

    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\((bgm\d+|musume_\d+)\)');
    var start = 0;

    for (final match in pattern.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }

      final token = match.group(1);
      final raw = match.group(0) ?? '';
      final url = token == null ? null : _smileUrlForToken(token);
      if (url == null) {
        spans.add(TextSpan(text: raw));
      } else {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Tooltip(
              message: raw,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Image.network(
                  url,
                  width: smileSize,
                  height: smileSize,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Text(raw, style: style);
                  },
                ),
              ),
            ),
          ),
        );
      }
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return spans.isEmpty ? const [TextSpan(text: ' ')] : spans;
  }

  static String _wrapHtml(String value) {
    return '<div>${value.trim()}</div>';
  }

  static String? _smileUrlForToken(String token) {
    if (token.startsWith('musume_')) {
      return '${BgmConst.webBaseUrl}/img/smiles/musume/$token.gif';
    }

    if (!token.startsWith('bgm')) return null;
    final id = int.tryParse(token.substring(3));
    if (id == null || id <= 0) return null;

    if (id <= 23) {
      return '${BgmConst.webBaseUrl}/img/smiles/bgm/$id.png';
    }
    if (id <= 200) {
      final fileName = (id - 23).toString().padLeft(2, '0');
      return '${BgmConst.webBaseUrl}/img/smiles/tv/$fileName.gif';
    }
    if (id <= 500) {
      return '${BgmConst.webBaseUrl}/img/smiles/tv_vs/bgm_$id.png';
    }
    return '${BgmConst.webBaseUrl}/img/smiles/tv_500/bgm_$id.gif';
  }

  static Future<void> _openLink(BuildContext context, String url) async {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return;

    final uri = parsed.hasScheme
        ? parsed
        : Uri.parse(BgmConst.webBaseUrl).resolveUri(parsed);

    await LinkNavigator.open(context, uri);
  }
}
