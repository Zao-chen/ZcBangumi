import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bangumi_index.dart';
import '../pages/index_page.dart';
import '../models/rakuen_topic_favorite.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import 'bangumi_index_actions.dart';
import 'bangumi_index_list_view.dart';

enum UserIndexListMode { created, collected }

class UserIndexCollectionsView extends StatefulWidget {
  final String username;

  const UserIndexCollectionsView({super.key, required this.username});

  @override
  State<UserIndexCollectionsView> createState() =>
      UserIndexCollectionsViewState();
}

class UserIndexCollectionsViewState extends State<UserIndexCollectionsView> {
  UserIndexListMode _mode = UserIndexListMode.created;
  final GlobalKey<BangumiIndexListViewState> _createdKey = GlobalKey();
  final GlobalKey<BangumiIndexListViewState> _collectedKey = GlobalKey();

  bool get _isSelf {
    final current = context.read<AuthProvider>().username?.trim().toLowerCase();
    return current != null &&
        current.isNotEmpty &&
        current == widget.username.trim().toLowerCase();
  }

  Future<void> refresh() {
    return (_mode == UserIndexListMode.created
                ? _createdKey.currentState
                : _collectedKey.currentState)
            ?.refresh() ??
        Future<void>.value();
  }

  Future<void> loadMore() {
    return (_mode == UserIndexListMode.created
                ? _createdKey.currentState
                : _collectedKey.currentState)
            ?.loadMore() ??
        Future<void>.value();
  }

  Future<void> _create() async {
    final id = await showBangumiIndexEditor(context);
    if (id == null || !mounted) return;
    await _createdKey.currentState?.refresh();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => BangumiIndexPage(indexId: id)));
    await _createdKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final viewerUsername = context.watch<AuthProvider>().username;
    final username = widget.username.trim();
    final cachedSyncId = context.read<StorageService>().getCache(
      rakuenFavoriteIndexCacheKey(username),
    );
    final parsedSyncId = cachedSyncId is int
        ? cachedSyncId
        : int.tryParse('$cachedSyncId');
    final hiddenIds = <int>{?parsedSyncId};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<UserIndexListMode>(
              segments: const [
                ButtonSegment(
                  value: UserIndexListMode.created,
                  label: Text('创建的'),
                  icon: Icon(Icons.edit_note_rounded),
                ),
                ButtonSegment(
                  value: UserIndexListMode.collected,
                  label: Text('收藏的'),
                  icon: Icon(Icons.favorite_outline_rounded),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) =>
                setState(() => _mode = selection.single),
            ),
            if (_isSelf && _mode == UserIndexListMode.created)
              FilledButton.tonalIcon(
                onPressed: _create,
                icon: const Icon(Icons.add_rounded),
                label: const Text('新建'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_mode == UserIndexListMode.created)
          BangumiIndexListView(
            key: _createdKey,
            cacheKey: bangumiUserIndexesCacheKey(
              targetUsername: username,
              viewerUsername: viewerUsername,
              collected: false,
            ),
            viewerUsername: viewerUsername,
            fallbackAuthorUsername: username,
            loadPage: (limit, offset) => api.getUserCreatedIndexes(
              username: username,
              limit: limit,
              offset: offset,
            ),
            emptyText: _isSelf ? '还没有创建目录' : '该用户还没有公开目录',
            hiddenIndexIds: hiddenIds,
            padding: const EdgeInsets.symmetric(vertical: 4),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
          )
        else
          BangumiIndexListView(
            key: _collectedKey,
            cacheKey: bangumiUserIndexesCacheKey(
              targetUsername: username,
              viewerUsername: viewerUsername,
              collected: true,
            ),
            viewerUsername: viewerUsername,
            loadPage: (limit, offset) => api.getUserCollectedIndexes(
              username: username,
              limit: limit,
              offset: offset,
            ),
            emptyText: '还没有收藏目录',
            padding: const EdgeInsets.symmetric(vertical: 4),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
          ),
      ],
    );
  }
}
