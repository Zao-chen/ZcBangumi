import 'package:flutter/foundation.dart';
import '../constants.dart';
import '../models/collection.dart';
import '../models/episode.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';

/// 收藏数据管理
class CollectionProvider extends ChangeNotifier {
  final ApiClient api;
  final StorageService storage;

  // 按条目类型缓存收藏列表
  final Map<int, List<UserCollection>> _collections = {};
  final Map<int, bool> _loadingMap = {};
  final Map<int, String?> _errorMap = {};
  final Map<int, int> _totalMap = {};

  // 按条目ID缓存章节进度
  final Map<int, List<UserEpisodeCollection>> _episodeProgress = {};
  final Map<int, bool> _episodeLoadingMap = {};

  CollectionProvider({required this.api, required this.storage});

  /// 预加载缓存数据（应用启动时调用）
  void preloadCachesIfAvailable() {
    // 从缓存读取所有已保存的收藏数据
    const types = [
      BgmConst.subjectAnime,
      BgmConst.subjectGame,
      BgmConst.subjectBook,
    ];

    // 获取上次保存的用户名
    final savedUsername = storage.username;
    if (savedUsername == null || savedUsername.isEmpty) return;

    for (final type in types) {
      final cacheKey = 'collections_${type}_$savedUsername';
      final cached = storage.getCache(cacheKey);
      if (cached is List && cached.isNotEmpty) {
        try {
          _collections[type] = cached
              .map((e) => UserCollection.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (_) {}
      }
    }

    // 预加载完成后需要通知 UI 更新
    notifyListeners();
  }

  /// 获取某类型的收藏列表
  List<UserCollection> getCollections(int subjectType) =>
      _collections[subjectType] ?? [];

  bool isLoading(int subjectType) => _loadingMap[subjectType] ?? false;
  String? getError(int subjectType) => _errorMap[subjectType];
  int getTotal(int subjectType) => _totalMap[subjectType] ?? 0;

  /// 获取某条目的章节进度
  List<UserEpisodeCollection> getEpisodeProgress(int subjectId) =>
      _episodeProgress[subjectId] ?? [];

  bool isEpisodeLoading(int subjectId) =>
      _episodeLoadingMap[subjectId] ?? false;

  /// 加载用户的"在看/在玩/在读"收藏
  Future<void> loadDoingCollections({
    required String username,
    required int subjectType,
    bool refresh = false,
    bool forceNetwork = true,
  }) async {
    if (_loadingMap[subjectType] == true && !refresh) return;

    // 无感加载：先从缓存恢复
    final cacheKey = 'collections_${subjectType}_$username';
    if ((_collections[subjectType] ?? []).isEmpty) {
      final cached = storage.getCache(cacheKey);
      if (cached is List && cached.isNotEmpty) {
        try {
          _collections[subjectType] = cached
              .map((e) => UserCollection.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (_) {}
      }
    }

    _loadingMap[subjectType] = (_collections[subjectType] ?? []).isEmpty;
    _errorMap[subjectType] = null;
    notifyListeners();

    if (!forceNetwork && (_collections[subjectType] ?? []).isNotEmpty) {
      _loadingMap[subjectType] = false;
      notifyListeners();
      return;
    }

    try {
      final result = await api.getUserCollections(
        username: username,
        subjectType: subjectType,
        collectionType: BgmConst.collectionDoing,
        limit: 50,
        offset: 0,
      );
      _collections[subjectType] = result.data;
      _totalMap[subjectType] = result.total;
      _errorMap[subjectType] = null;
      // 写入缓存
      storage.setCache(cacheKey, result.data.map((e) => e.toJson()).toList());
    } catch (e) {
      // 有缓存时静默失败
      if ((_collections[subjectType] ?? []).isEmpty) {
        _errorMap[subjectType] = '加载失败: $e';
      }
    } finally {
      _loadingMap[subjectType] = false;
      notifyListeners();
    }
  }

  /// 加载某条目的章节进度
  Future<void> loadEpisodeProgress(int subjectId) async {
    if (_episodeLoadingMap[subjectId] == true) return;

    // 无感加载：先从缓存恢复
    final cacheKey = 'episodes_$subjectId';
    if ((_episodeProgress[subjectId] ?? []).isEmpty) {
      final cached = storage.getCache(cacheKey);
      if (cached is List && cached.isNotEmpty) {
        try {
          _episodeProgress[subjectId] = cached
              .map(
                (e) =>
                    UserEpisodeCollection.fromJson(e as Map<String, dynamic>),
              )
              .toList();
        } catch (_) {}
      }
    }

    _episodeLoadingMap[subjectId] = (_episodeProgress[subjectId] ?? []).isEmpty;
    notifyListeners();

    try {
      final result = await api.getUserEpisodeCollections(subjectId: subjectId);
      _episodeProgress[subjectId] = result.data;
      // 写入缓存
      storage.setCache(cacheKey, result.data.map((e) => e.toJson()).toList());
    } catch (e) {
      debugPrint('加载章节进度失败: $e');
    } finally {
      _episodeLoadingMap[subjectId] = false;
      notifyListeners();
    }
  }

  /// 设置章节状态（看过/想看/抛弃/撤销）
  Future<void> setEpisodeStatus({
    required int subjectId,
    required int episodeId,
    required int newType,
  }) async {
    final episodes = _episodeProgress[subjectId];
    if (episodes == null) return;

    final idx = episodes.indexWhere((e) => e.episode.id == episodeId);
    if (idx == -1) return;
    final oldType = episodes[idx].type;
    if (oldType == newType) return;

    // 乐观更新 UI
    episodes[idx] = UserEpisodeCollection(
      episode: episodes[idx].episode,
      type: newType,
    );
    notifyListeners();

    try {
      if (newType == BgmConst.episodeNotCollected) {
        await api.putEpisodeCollection(
          episodeId: episodeId,
          type: BgmConst.episodeNotCollected,
        );
      } else {
        await api.putEpisodeCollection(episodeId: episodeId, type: newType);
      }
      // 更新缓存
      _saveEpisodeCache(subjectId);
    } catch (e) {
      // 回滚
      if (idx < episodes.length && episodes[idx].episode.id == episodeId) {
        episodes[idx] = UserEpisodeCollection(
          episode: episodes[idx].episode,
          type: oldType,
        );
      }
      notifyListeners();
      debugPrint('更新章节状态失败: $e');
    }
  }

  /// 批量标记章节（看到第N集）
  Future<void> watchUpTo({
    required int subjectId,
    required int episodeSort,
  }) async {
    final episodes = _episodeProgress[subjectId];
    if (episodes == null) return;

    final toWatch = episodes
        .where(
          (e) =>
              e.episode.type == 0 && // 只处理本篇
              e.episode.sort <= episodeSort &&
              e.type != BgmConst.episodeDone,
        )
        .map((e) => e.episode.id)
        .toList();

    if (toWatch.isEmpty) return;

    // 乐观更新
    for (var i = 0; i < episodes.length; i++) {
      if (toWatch.contains(episodes[i].episode.id)) {
        episodes[i] = UserEpisodeCollection(
          episode: episodes[i].episode,
          type: BgmConst.episodeDone,
        );
      }
    }
    notifyListeners();

    try {
      await api.patchEpisodeCollections(
        subjectId: subjectId,
        episodeIds: toWatch,
        type: BgmConst.episodeDone,
      );
      // 更新缓存
      _saveEpisodeCache(subjectId);
    } catch (e) {
      // 失败后重新加载
      debugPrint('批量更新失败: $e');
      await loadEpisodeProgress(subjectId);
    }
  }

  Future<void> setCollectionEpStatus({
    required int subjectId,
    required int epStatus,
  }) async {
    if (epStatus <= 0) return;

    _updateCollectionEpStatusLocal(subjectId, epStatus);
    notifyListeners();

    try {
      await api.patchCollection(subjectId: subjectId, epStatus: epStatus);
    } catch (e) {
      debugPrint('更新条目进度失败: $e');
    }
  }

  Future<void> setCollectionType({
    required int subjectId,
    required int subjectType,
    required int newType,
  }) async {
    final list = _collections[subjectType];
    if (list == null || list.isEmpty) return;
    final oldList = List<UserCollection>.from(list);
    final idx = list.indexWhere((c) => c.subjectId == subjectId);
    if (idx == -1) return;

    final current = list[idx];
    if (current.type == newType) return;

    if (newType == BgmConst.collectionDoing) {
      list[idx] = UserCollection(
        subjectId: current.subjectId,
        subjectType: current.subjectType,
        rate: current.rate,
        type: newType,
        comment: current.comment,
        tags: current.tags,
        epStatus: current.epStatus,
        volStatus: current.volStatus,
        updatedAt: current.updatedAt,
        private_: current.private_,
        subject: current.subject,
      );
    } else {
      list.removeAt(idx);
    }
    notifyListeners();

    try {
      await api.patchCollection(subjectId: subjectId, type: newType);
    } catch (e) {
      _collections[subjectType] = oldList;
      notifyListeners();
      debugPrint('更新收藏状态失败: $e');
    }
  }

  void _updateCollectionEpStatusLocal(int subjectId, int epStatus) {
    for (final type in _collections.keys) {
      final list = _collections[type];
      if (list == null || list.isEmpty) continue;
      final idx = list.indexWhere((c) => c.subjectId == subjectId);
      if (idx == -1) continue;
      final c = list[idx];
      list[idx] = UserCollection(
        subjectId: c.subjectId,
        subjectType: c.subjectType,
        rate: c.rate,
        type: c.type,
        comment: c.comment,
        tags: c.tags,
        epStatus: epStatus,
        volStatus: c.volStatus,
        updatedAt: c.updatedAt,
        private_: c.private_,
        subject: c.subject,
      );
    }
  }

  /// 将章节进度写入本地缓存
  void _saveEpisodeCache(int subjectId) {
    final eps = _episodeProgress[subjectId];
    if (eps != null) {
      storage.setCache(
        'episodes_$subjectId',
        eps.map((e) => e.toJson()).toList(),
      );
    }
  }

  /// 清除缓存（退出登录时调用）
  void clearAll() {
    _collections.clear();
    _loadingMap.clear();
    _errorMap.clear();
    _totalMap.clear();
    _episodeProgress.clear();
    _episodeLoadingMap.clear();
    storage.clearDataCache();
    notifyListeners();
  }
}
