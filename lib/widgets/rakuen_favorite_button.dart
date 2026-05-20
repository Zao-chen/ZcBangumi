import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/rakuen_topic.dart';
import '../providers/auth_provider.dart';
import '../providers/rakuen_favorite_provider.dart';

class RakuenFavoriteButton extends StatelessWidget {
  final RakuenTopic topic;
  final Color? selectedColor;
  final Color? unselectedColor;
  final VisualDensity? visualDensity;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;

  const RakuenFavoriteButton({
    super.key,
    required this.topic,
    this.selectedColor,
    this.unselectedColor,
    this.visualDensity,
    this.padding,
    this.constraints,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<RakuenFavoriteProvider>(
      builder: (context, favorites, _) {
        final selected = favorites.isFavoriteTopic(topic);
        return IconButton(
          tooltip: selected ? '取消收藏' : '收藏帖子',
          onPressed: favorites.syncing
              ? null
              : () => _handlePressed(context, favorites, selected),
          icon: Icon(
            selected ? Icons.star_rounded : Icons.star_border_rounded,
            color: selected ? selectedColor : unselectedColor,
          ),
          visualDensity: visualDensity,
          padding: padding,
          constraints: constraints,
        );
      },
    );
  }

  Future<void> _handlePressed(
    BuildContext context,
    RakuenFavoriteProvider favorites,
    bool selected,
  ) async {
    if (selected || favorites.hasCloudSyncPreference) {
      await favorites.toggleFavorite(topic);
      return;
    }

    final auth = context.read<AuthProvider>();
    final enableCloud = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('收藏帖子'),
        content: Text(
          auth.isLoggedIn
              ? '帖子会先保存在本机。开启云端同步后，ZCBangumi 会创建一个 Bangumi 私有目录，把收藏数据写进目录介绍，用来在设备间同步。'
              : '帖子会保存在本机。登录 Bangumi 后，可以开启云端同步，ZCBangumi 会用一个私有目录保存收藏数据。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('仅本地收藏'),
          ),
          FilledButton(
            onPressed: auth.isLoggedIn
                ? () => Navigator.of(dialogContext).pop(true)
                : null,
            child: const Text('开启云端同步'),
          ),
        ],
      ),
    );

    if (enableCloud == null) return;
    await favorites.toggleFavorite(topic, enableCloudSync: enableCloud);
  }
}
