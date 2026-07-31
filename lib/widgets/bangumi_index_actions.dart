import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bangumi_index.dart';
import '../models/rakuen_topic_favorite.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';

Future<void> invalidateBangumiIndexCaches(
  StorageService storage, {
  int? indexId,
  String? username,
  IndexRelatedCategory? category,
  int? contentId,
}) async {
  final normalizedUsername = username?.trim();
  final keys = <String>{
    if (normalizedUsername?.isNotEmpty == true)
      bangumiUserIndexesCacheKey(
        targetUsername: normalizedUsername!,
        viewerUsername: normalizedUsername,
        collected: false,
      ),
    if (normalizedUsername?.isNotEmpty == true)
      bangumiUserIndexesCacheKey(
        targetUsername: normalizedUsername!,
        viewerUsername: null,
        collected: false,
      ),
    if (normalizedUsername?.isNotEmpty == true)
      bangumiUserIndexesCacheKey(
        targetUsername: normalizedUsername!,
        viewerUsername: normalizedUsername,
        collected: true,
      ),
    if (normalizedUsername?.isNotEmpty == true)
      bangumiUserIndexesCacheKey(
        targetUsername: normalizedUsername!,
        viewerUsername: null,
        collected: true,
      ),
    if (indexId != null)
      bangumiIndexDetailCacheKey(indexId, normalizedUsername),
    if (indexId != null) bangumiIndexDetailCacheKey(indexId, null),
    if (indexId != null)
      bangumiIndexRelatedCacheKey(indexId, null, null, normalizedUsername),
    if (indexId != null) bangumiIndexRelatedCacheKey(indexId, null, null, null),
    // 清理本功能早期版本留下的不分账号缓存，之后不再读取这些键。
    if (normalizedUsername?.isNotEmpty == true)
      'user_created_indexes_$normalizedUsername',
    if (normalizedUsername?.isNotEmpty == true)
      'user_collected_indexes_$normalizedUsername',
    if (indexId != null) 'bangumi_index_$indexId',
    if (indexId != null) 'bangumi_index_related_${indexId}_-1_-1',
  };
  if (indexId != null) {
    for (final item in IndexRelatedCategory.values) {
      keys.add(
        bangumiIndexRelatedCacheKey(indexId, item, null, normalizedUsername),
      );
      keys.add(bangumiIndexRelatedCacheKey(indexId, item, null, null));
      keys.add('bangumi_index_related_${indexId}_${item.value}_-1');
    }
    for (final type in const [1, 2, 3, 4, 6]) {
      keys.add(
        bangumiIndexRelatedCacheKey(
          indexId,
          IndexRelatedCategory.subject,
          type,
          normalizedUsername,
        ),
      );
      keys.add(
        bangumiIndexRelatedCacheKey(
          indexId,
          IndexRelatedCategory.subject,
          type,
          null,
        ),
      );
      keys.add(
        'bangumi_index_related_${indexId}_${IndexRelatedCategory.subject.value}_$type',
      );
    }
  }
  if (category != null && contentId != null) {
    final reverseKey = switch (category) {
      IndexRelatedCategory.subject => 'subject_indexes_$contentId',
      IndexRelatedCategory.character => 'character_indexes_$contentId',
      IndexRelatedCategory.person => 'person_indexes_$contentId',
      _ => null,
    };
    if (reverseKey != null) {
      keys
        ..add(reverseKey)
        ..add(
          bangumiEntityIndexesCacheKey(category, contentId, normalizedUsername),
        )
        ..add(bangumiEntityIndexesCacheKey(category, contentId, null));
    }
  }
  await Future.wait(keys.map(storage.removeCache));
}

Future<int?> showBangumiIndexEditor(
  BuildContext context, {
  BangumiIndex? existing,
}) async {
  final titleController = TextEditingController(text: existing?.title ?? '');
  final descController = TextEditingController(
    text: existing?.description ?? '',
  );
  var isPrivate = existing?.isPrivate ?? false;
  var saving = false;
  String? error;

  final result = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> save() async {
          final title = titleController.text.trim();
          if (title.isEmpty || title.runes.length > 80) {
            setState(() => error = '标题必须为 1–80 个字符');
            return;
          }
          setState(() {
            saving = true;
            error = null;
          });
          try {
            final api = context.read<ApiClient>();
            final storage = context.read<StorageService>();
            final username = context.read<AuthProvider>().username;
            final id = existing == null
                ? await api.createBangumiIndex(
                    title: title,
                    description: descController.text,
                    private: isPrivate,
                  )
                : existing.id;
            if (existing != null) {
              await api.updateBangumiIndex(
                indexId: existing.id,
                title: title,
                description: descController.text,
                private: isPrivate,
              );
            }
            await invalidateBangumiIndexCaches(
              storage,
              indexId: id,
              username: username,
            );
            if (dialogContext.mounted) Navigator.pop(dialogContext, id);
          } catch (e) {
            if (dialogContext.mounted) {
              setState(() {
                saving = false;
                error = '$e';
              });
            }
          }
        }

        return PopScope(
          canPop: !saving,
          child: AlertDialog(
            title: Text(existing == null ? '新建目录' : '编辑目录'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      autofocus: true,
                      maxLength: 80,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: '标题',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      minLines: 4,
                      maxLines: 10,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: '介绍',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('仅自己可见'),
                      subtitle: const Text('私密目录不会出现在其他用户的页面中'),
                      value: isPrivate,
                      onChanged: saving
                          ? null
                          : (value) => setState(() => isPrivate = value),
                    ),
                    if (error != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: saving ? null : save,
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(existing == null ? '创建' : '保存'),
              ),
            ],
          ),
        );
      },
    ),
  );
  titleController.dispose();
  descController.dispose();
  return result;
}

Future<bool> showAddToBangumiIndex(
  BuildContext context, {
  required IndexRelatedCategory category,
  required int contentId,
  String? contentTitle,
}) async {
  final auth = context.read<AuthProvider>();
  final username = auth.username?.trim() ?? '';
  if (!auth.isLoggedIn || username.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('请先登录后再加入目录')));
    return false;
  }
  final api = context.read<ApiClient>();
  final storage = context.read<StorageService>();
  final cachedSyncId = storage.getCache(rakuenFavoriteIndexCacheKey(username));
  final syncIndexId = cachedSyncId is int
      ? cachedSyncId
      : int.tryParse('$cachedSyncId');
  final commentController = TextEditingController();
  var selectedId = 0;
  var loading = true;
  var loadScheduled = false;
  var submitting = false;
  var dialogOpen = true;
  String? error;
  List<BangumiIndexSummary> indexes = [];

  Future<void> loadIndexes(void Function(void Function()) setState) async {
    if (!dialogOpen) return;
    try {
      final loaded = <BangumiIndexSummary>[];
      var offset = 0;
      while (true) {
        final page = await api.getUserCreatedIndexes(
          username: username,
          limit: 100,
          offset: offset,
        );
        loaded.addAll(
          page.data.where(
            (index) =>
                !index.isSystemSyncIndex &&
                index.id != syncIndexId &&
                index.type == BangumiIndexType.user,
          ),
        );
        offset += 100;
        if (offset >= page.total) break;
      }
      if (!dialogOpen) return;
      setState(() {
        indexes = loaded;
        selectedId = loaded.any((item) => item.id == selectedId)
            ? selectedId
            : (loaded.isEmpty ? 0 : loaded.first.id);
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!dialogOpen) return;
      setState(() {
        loading = false;
        error = '$e';
      });
    } finally {
      loadScheduled = false;
    }
  }

  final added = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        if (loading && indexes.isEmpty && error == null && !loadScheduled) {
          loadScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => loadIndexes(setState),
          );
        }

        Future<void> addContentToIndex(int indexId) async {
          var offset = 0;
          var maxOrder = 0;
          while (true) {
            final page = await api.getIndexRelated(
              indexId: indexId,
              category: category,
              limit: 100,
              offset: offset,
            );
            for (final item in page.data) {
              if (item.order > maxOrder) maxOrder = item.order;
            }
            offset += 100;
            if (offset >= page.total) break;
          }
          await api.addBangumiIndexRelated(
            indexId: indexId,
            category: category,
            subjectId: contentId,
            order: maxOrder + 10,
            comment: commentController.text,
          );
          await invalidateBangumiIndexCaches(
            storage,
            indexId: indexId,
            username: username,
            category: category,
            contentId: contentId,
          );
        }

        Future<void> createIndex() async {
          final id = await showBangumiIndexEditor(dialogContext);
          if (id == null || !dialogContext.mounted) return;
          selectedId = id;
          setState(() {
            submitting = true;
            error = null;
          });
          try {
            await addContentToIndex(id);
            if (dialogContext.mounted) Navigator.pop(dialogContext, true);
          } catch (e) {
            if (!dialogContext.mounted) return;
            setState(() => loading = true);
            await loadIndexes(setState);
            if (!dialogContext.mounted) return;
            setState(() {
              selectedId = id;
              submitting = false;
              error = '目录已创建，但加入内容失败：$e';
            });
          }
        }

        Future<void> submit() async {
          if (selectedId <= 0) return;
          setState(() {
            submitting = true;
            error = null;
          });
          try {
            await addContentToIndex(selectedId);
            if (dialogContext.mounted) Navigator.pop(dialogContext, true);
          } catch (e) {
            if (!dialogContext.mounted) return;
            setState(() {
              submitting = false;
              error = '$e';
            });
          }
        }

        return PopScope(
          canPop: !submitting,
          child: AlertDialog(
            title: Text(
              contentTitle?.trim().isNotEmpty == true
                  ? '加入目录：$contentTitle'
                  : '加入目录',
            ),
            content: SizedBox(
              width: 460,
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (indexes.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('还没有可编辑的目录，请先新建一个'),
                            )
                          else
                            DropdownButtonFormField<int>(
                              initialValue: selectedId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: '选择目录',
                                border: OutlineInputBorder(),
                              ),
                              items: indexes
                                  .map(
                                    (index) => DropdownMenuItem(
                                      value: index.id,
                                      child: Text(
                                        index.isPrivate
                                            ? '${index.title}（私密）'
                                            : index.title,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: submitting
                                  ? null
                                  : (value) =>
                                        setState(() => selectedId = value ?? 0),
                            ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: commentController,
                            enabled: !submitting,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: '备注（可选）',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          if (error != null) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
            actions: [
              if (!loading && error != null && indexes.isEmpty)
                TextButton.icon(
                  onPressed: submitting
                      ? null
                      : () {
                          setState(() {
                            loading = true;
                            error = null;
                          });
                        },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试'),
                ),
              TextButton.icon(
                onPressed: submitting ? null : createIndex,
                icon: const Icon(Icons.add_rounded),
                label: const Text('新建目录'),
              ),
              TextButton(
                onPressed: submitting
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: submitting || selectedId <= 0 ? null : submit,
                child: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('加入'),
              ),
            ],
          ),
        );
      },
    ),
  );
  dialogOpen = false;
  commentController.dispose();
  return added ?? false;
}
