import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../services/link_navigator.dart';
import '../services/bangumi_endpoint_service.dart';
import 'bangumi_network_image.dart';

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
    final endpoints = context.watch<BangumiEndpointService?>();

    if (trimmedHtml != null && trimmedHtml.isNotEmpty) {
      return Html(
        data: _wrapHtml(endpoints?.rewriteHtml(trimmedHtml) ?? trimmedHtml),
        extensions: [
          _BangumiSmileImageExtension(smileSize: resolvedSmileSize),
          if (endpoints != null)
            ImageExtension(
              networkDomains: endpoints.knownHosts,
              handleAssetImages: false,
              handleDataImages: false,
              builder: (imageContext) => BangumiNetworkImage(
                imageUrl: imageContext.attributes['src'] ?? '',
                width: imageContext.style?.width?.unit == Unit.px
                    ? imageContext.style?.width?.value
                    : null,
                height: imageContext.style?.height?.unit == Unit.px
                    ? imageContext.style?.height?.value
                    : null,
                fit: BoxFit.contain,
                errorWidget: (_, _, _) =>
                    Text(imageContext.attributes['alt'] ?? '图片加载失败'),
              ),
            ),
        ],
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
        final imageSize = _smileSizeForUrl(url, smileSize);
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Tooltip(
              message: raw,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: BangumiNetworkImage(
                  imageUrl: url,
                  width: imageSize,
                  height: imageSize,
                  fit: BoxFit.contain,
                  errorWidget: (context, url, error) {
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

  static double _smileSizeForUrl(String url, double standardSize) {
    final imagePath = Uri.tryParse(url)?.path ?? '';
    return imagePath.startsWith('/img/smiles/musume/')
        ? standardSize * 2
        : standardSize;
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

class _BangumiSmileImageExtension extends ImageExtension {
  _BangumiSmileImageExtension({required double smileSize})
    : super.inline(
        builder: (imageContext) {
          final imageUrl = Uri.parse(
            BgmConst.webBaseUrl,
          ).resolve(imageContext.attributes['src'] ?? '').toString();
          final imageSize = BangumiContentView._smileSizeForUrl(
            imageUrl,
            smileSize,
          );
          return WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: BangumiNetworkImage(
              imageUrl: imageUrl,
              width: imageSize,
              height: imageSize,
              fit: BoxFit.contain,
              errorWidget: (_, _, _) =>
                  Text(imageContext.attributes['alt'] ?? '表情加载失败'),
            ),
          );
        },
      );

  @override
  bool matches(ExtensionContext context) {
    final imagePath = Uri.tryParse(context.attributes['src'] ?? '')?.path ?? '';
    return context.elementName == 'img' && imagePath.startsWith('/img/smiles/');
  }
}
