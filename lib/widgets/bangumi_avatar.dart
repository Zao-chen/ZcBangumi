import 'package:flutter/material.dart';

import 'bangumi_network_image.dart';

class BangumiAvatar extends StatelessWidget {
  static const cornerRadiusFactor = 0.24;

  final String url;
  final double size;
  final IconData? placeholderIcon;

  const BangumiAvatar({
    super.key,
    required this.url,
    required this.size,
    this.placeholderIcon = Icons.person_outline,
  }) : assert(size > 0);

  const BangumiAvatar.skeleton({super.key, required this.size})
    : url = '',
      placeholderIcon = null,
      assert(size > 0);

  @override
  Widget build(BuildContext context) {
    Widget placeholder({bool showIcon = true}) => Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: showIcon && placeholderIcon != null
          ? Icon(placeholderIcon, size: size * 0.45)
          : null,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * cornerRadiusFactor),
      child: SizedBox.square(
        dimension: size,
        child: url.trim().isEmpty
            ? placeholder()
            : BangumiNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) => placeholder(showIcon: false),
                errorWidget: (_, _, _) => placeholder(),
              ),
      ),
    );
  }
}
