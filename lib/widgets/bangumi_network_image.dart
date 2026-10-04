import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/bangumi_endpoint_service.dart';
import '../services/bangumi_image_cache.dart';

class BangumiNetworkImage extends StatelessWidget {
  const BangumiNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.placeholder,
    this.errorWidget,
    this.imageBuilder,
    this.memCacheWidth,
    this.memCacheHeight,
    this.fadeInDuration = const Duration(milliseconds: 500),
    this.fadeOutDuration = const Duration(milliseconds: 1000),
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final PlaceholderWidgetBuilder? placeholder;
  final LoadingErrorWidgetBuilder? errorWidget;
  final ImageWidgetBuilder? imageBuilder;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;

  @override
  Widget build(BuildContext context) {
    final endpoints = context.watch<BangumiEndpointService?>();
    final cache = context.read<BangumiImageCache?>();
    final resolved = endpoints?.resolveUrl(imageUrl) ?? imageUrl;
    final uri = Uri.tryParse(resolved);
    if (kIsWeb) {
      final provider = NetworkImage(
        resolved,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      );
      return Image(
        key: ValueKey('${endpoints?.generation}:$resolved'),
        image: provider,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (frame == null && !wasSynchronouslyLoaded) {
            return placeholder?.call(context, resolved) ??
                SizedBox(width: width, height: height);
          }
          return imageBuilder?.call(context, provider) ?? child;
        },
        errorBuilder: (context, error, stackTrace) =>
            errorWidget?.call(context, resolved, error) ??
            SizedBox(width: width, height: height),
      );
    }
    return CachedNetworkImage(
      key: ValueKey(
        '${endpoints?.generation}:${endpoints?.sessionRevision}:$resolved',
      ),
      imageUrl: resolved,
      cacheKey: uri == null
          ? imageUrl
          : endpoints?.canonicalUri(uri).toString() ?? imageUrl,
      cacheManager: cache?.manager,
      httpHeaders: uri == null ? null : endpoints?.imageHeaders(uri),
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      placeholder: placeholder,
      errorWidget: errorWidget,
      imageBuilder: imageBuilder,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      fadeInDuration: fadeInDuration,
      fadeOutDuration: fadeOutDuration,
    );
  }
}

ImageProvider bangumiImageProvider(BuildContext context, String imageUrl) {
  final endpoints = context.watch<BangumiEndpointService?>();
  final cache = context.read<BangumiImageCache?>();
  final resolved = endpoints?.resolveUrl(imageUrl) ?? imageUrl;
  final uri = Uri.tryParse(resolved);
  if (kIsWeb) {
    return NetworkImage(
      resolved,
      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
    );
  }
  return CachedNetworkImageProvider(
    resolved,
    cacheManager: cache?.manager,
    cacheKey: uri == null
        ? imageUrl
        : endpoints?.canonicalUri(uri).toString() ?? imageUrl,
    headers: uri == null ? null : endpoints?.imageHeaders(uri),
  );
}
