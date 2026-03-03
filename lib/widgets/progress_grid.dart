import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/episode.dart';

/// 章节进度网格 - "点格子"
/// 每个格子点击弹出菜单，可选 看过/看到/想看/抛弃/撤销
class ProgressGrid extends StatelessWidget {
  final List<UserEpisodeCollection> episodes;
  final bool loading;

  /// 设置单集状态：(episodeId, newType)
  final void Function(int episodeId, int newType)? onSetStatus;

  /// 批量看到第N集
  final void Function(int episodeSort)? onWatchUpTo;

  const ProgressGrid({
    super.key,
    required this.episodes,
    this.loading = false,
    this.onSetStatus,
    this.onWatchUpTo,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (episodes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('暂无章节信息', style: TextStyle(color: Colors.grey)),
      );
    }

    // 只显示本篇（type=0）
    final mainEps = episodes.where((e) => e.episode.type == 0).toList();
    if (mainEps.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('暂无本篇章节', style: TextStyle(color: Colors.grey)),
      );
    }

    // 排序
    mainEps.sort((a, b) => a.episode.sort.compareTo(b.episode.sort));

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: mainEps.map((ep) {
          return _EpisodeCell(
            episode: ep,
            onSetStatus: onSetStatus,
            onWatchUpTo: onWatchUpTo,
          );
        }).toList(),
      ),
    );
  }
}

/// 单个章节格子
class _EpisodeCell extends StatelessWidget {
  final UserEpisodeCollection episode;
  final void Function(int episodeId, int newType)? onSetStatus;
  final void Function(int episodeSort)? onWatchUpTo;

  const _EpisodeCell({
    required this.episode,
    this.onSetStatus,
    this.onWatchUpTo,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Color bgColor;
    Color textColor;
    switch (episode.type) {
      case BgmConst.episodeDone:
        bgColor = colorScheme.primary;
        textColor = colorScheme.onPrimary;
        break;
      case BgmConst.episodeWish:
        bgColor = colorScheme.primaryContainer;
        textColor = colorScheme.onPrimaryContainer;
        break;
      case BgmConst.episodeDropped:
        bgColor = colorScheme.errorContainer;
        textColor = colorScheme.onErrorContainer;
        break;
      default:
        bgColor = colorScheme.surfaceContainerHighest;
        textColor = colorScheme.onSurfaceVariant;
    }

    return Tooltip(
      message: _tooltipText(),
      child: GestureDetector(
        onTapUp: (details) => _showMenu(context, details.globalPosition),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(5),
          ),
          alignment: Alignment.center,
          child: Text(
            episode.episode.sortLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  void _showMenu(BuildContext context, Offset position) {
    final ep = episode;
    final currentType = ep.type;

    final items = <PopupMenuEntry<int>>[];

    if (currentType != BgmConst.episodeDone) {
      items.add(
        const PopupMenuItem(
          value: BgmConst.episodeDone,
          height: 40,
          child: _MenuRow(
            icon: Icons.check_circle,
            label: '看过',
            color: Colors.blue,
          ),
        ),
      );
    }

    // "看到" — 批量标记到此集
    items.add(
      PopupMenuItem(
        value: -1,
        height: 40,
        child: _MenuRow(
          icon: Icons.fast_forward,
          label: '看到 EP.${ep.episode.sortLabel}',
          color: Colors.teal,
        ),
      ),
    );

    if (currentType != BgmConst.episodeWish) {
      items.add(
        const PopupMenuItem(
          value: BgmConst.episodeWish,
          height: 40,
          child: _MenuRow(
            icon: Icons.bookmark_outline,
            label: '想看',
            color: Colors.orange,
          ),
        ),
      );
    }

    if (currentType != BgmConst.episodeDropped) {
      items.add(
        const PopupMenuItem(
          value: BgmConst.episodeDropped,
          height: 40,
          child: _MenuRow(icon: Icons.block, label: '抛弃', color: Colors.red),
        ),
      );
    }

    if (currentType != BgmConst.episodeNotCollected) {
      items.add(const PopupMenuDivider(height: 8));
      items.add(
        const PopupMenuItem(
          value: BgmConst.episodeNotCollected,
          height: 40,
          child: _MenuRow(icon: Icons.undo, label: '撤销', color: Colors.grey),
        ),
      );
    }

    showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: items,
    ).then((value) {
      if (value == null) return;
      if (value == -1) {
        onWatchUpTo?.call(ep.episode.sort.toInt());
      } else {
        onSetStatus?.call(ep.episode.id, value);
      }
    });
  }

  String _tooltipText() {
    final ep = episode.episode;
    final name = ep.displayName;
    final status = switch (episode.type) {
      BgmConst.episodeDone => '看过',
      BgmConst.episodeWish => '想看',
      BgmConst.episodeDropped => '抛弃',
      _ => '未收藏',
    };
    return 'EP.${ep.sortLabel} $name [$status]';
  }
}

/// 菜单项的图标+文字行
class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MenuRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 14)),
      ],
    );
  }
}
