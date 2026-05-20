import 'package:flutter/foundation.dart';

import '../models/rakuen_topic.dart';
import '../models/rakuen_topic_favorite.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';

class RakuenFavoriteProvider extends ChangeNotifier {
  final ApiClient api;
  final StorageService storage;

  final Map<String, RakuenFavoriteTopic> _items = {};
  String? _activeUsername;
  bool? _cloudSyncEnabled;
  bool _loaded = false;
  bool _syncing = false;
  String? _syncError;

  RakuenFavoriteProvider({required this.api, required this.storage});

  List<RakuenFavoriteTopic> get favorites {
    final list = _items.values.toList();
    list.sort((a, b) => b.favoritedAt.compareTo(a.favoritedAt));
    return list;
  }

  bool get loaded => _loaded;
  bool get syncing => _syncing;
  String? get syncError => _syncError;
  String? get activeUsername => _activeUsername;
  bool get hasCloudSyncPreference => _cloudSyncEnabled != null;
  bool get cloudSyncEnabled => _cloudSyncEnabled == true;

  bool isFavoriteTopic(RakuenTopic topic) {
    return _items.containsKey(RakuenFavoriteTopic.keyForTopic(topic));
  }

  Future<void> initialize({
    String? username,
    bool syncCloud = false,
    bool createCloudIndex = false,
  }) async {
    final normalizedUsername = _normalizeUsername(username);
    if (_activeUsername != normalizedUsername || !_loaded) {
      _activeUsername = normalizedUsername;
      _cloudSyncEnabled = _loadCloudSyncPreference();
      _loadLocal();
    }
    if (syncCloud && cloudSyncEnabled) {
      await syncFromCloud(createIfMissing: createCloudIndex);
    }
  }

  Future<void> setCloudSyncEnabled(bool value) async {
    _cloudSyncEnabled = value;
    await storage.setCache(_cloudSyncPreferenceKey, value);
    notifyListeners();

    if (value && api.hasToken && _activeUsername != null) {
      await syncToCloud(createIfMissing: true);
    }
  }

  Future<void> toggleFavorite(
    RakuenTopic topic, {
    bool? enableCloudSync,
  }) async {
    await initialize(username: _activeUsername);
    if (enableCloudSync != null) {
      _cloudSyncEnabled = enableCloudSync;
      await storage.setCache(_cloudSyncPreferenceKey, enableCloudSync);
    }

    final key = RakuenFavoriteTopic.keyForTopic(topic);
    if (_items.containsKey(key)) {
      _items.remove(key);
    } else {
      _items[key] = RakuenFavoriteTopic.fromTopic(topic);
    }
    await _saveLocal();
    notifyListeners();

    if (cloudSyncEnabled && api.hasToken && _activeUsername != null) {
      await syncToCloud(createIfMissing: true);
    }
  }

  Future<void> syncFromCloud({bool createIfMissing = false}) async {
    if (!cloudSyncEnabled) return;
    if (!api.hasToken || _activeUsername == null) return;
    if (_syncing) return;

    _syncing = true;
    _syncError = null;
    notifyListeners();

    try {
      final index = await _ensureCloudIndex(createIfMissing: createIfMissing);
      if (index == null) return;

      final cloudDocument =
          RakuenFavoriteCloudDocument.tryParseFromDescription(index.desc) ??
          RakuenFavoriteCloudDocument.empty();
      final changed = _mergeCloudItems(cloudDocument.items);
      if (changed) {
        await _saveLocal();
      }

      if (changed || cloudDocument.items.length != _items.length) {
        await _writeCloud(index);
      }
    } catch (e) {
      _syncError = e.toString();
      if (kDebugMode) {
        debugPrint('同步帖子收藏失败: $e');
      }
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> syncToCloud({bool createIfMissing = false}) async {
    if (!cloudSyncEnabled) return;
    if (!api.hasToken || _activeUsername == null) return;
    if (_syncing) return;

    _syncing = true;
    _syncError = null;
    notifyListeners();

    try {
      final index = await _ensureCloudIndex(createIfMissing: createIfMissing);
      if (index == null) return;
      await _writeCloud(index);
    } catch (e) {
      _syncError = e.toString();
      if (kDebugMode) {
        debugPrint('写入帖子收藏失败: $e');
      }
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  void _loadLocal() {
    _items.clear();
    final raw = storage.getCache(_favoritesCacheKey);
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        try {
          final favorite = RakuenFavoriteTopic.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (favorite.key.isNotEmpty && favorite.topicUrl.isNotEmpty) {
            _items[favorite.key] = favorite;
          }
        } catch (_) {
          // Ignore broken cache entries.
        }
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _saveLocal() async {
    await storage.setCache(
      _favoritesCacheKey,
      favorites.map((item) => item.toJson()).toList(),
    );
  }

  bool _mergeCloudItems(List<RakuenFavoriteTopic> cloudItems) {
    var changed = false;
    for (final cloudItem in cloudItems) {
      final localItem = _items[cloudItem.key];
      if (localItem == null ||
          cloudItem.updatedAt.isAfter(localItem.updatedAt)) {
        _items[cloudItem.key] = cloudItem;
        changed = true;
      }
    }
    return changed;
  }

  Future<RakuenFavoriteIndex?> _ensureCloudIndex({
    required bool createIfMissing,
  }) async {
    final cachedId = _cachedCloudIndexId;
    if (cachedId != null) {
      try {
        final index = await api.getRakuenFavoriteIndex(cachedId);
        if (_looksLikeSyncIndex(index)) return index;
      } catch (_) {
        await storage.removeCache(_cloudIndexCacheKey);
      }
    }

    final discovered = await _discoverCloudIndex();
    if (discovered != null) {
      await storage.setCache(_cloudIndexCacheKey, discovered.id);
      return discovered;
    }

    if (!createIfMissing) return null;
    final desc = RakuenFavoriteCloudDocument.buildDescription(
      existingDescription: '',
      document: RakuenFavoriteCloudDocument.empty(),
    );
    final id = await api.createRakuenFavoriteIndex(
      title: rakuenFavoriteIndexTitle,
      desc: desc,
      private: true,
    );
    await storage.setCache(_cloudIndexCacheKey, id);
    return api.getRakuenFavoriteIndex(id);
  }

  Future<RakuenFavoriteIndex?> _discoverCloudIndex() async {
    final username = _activeUsername;
    if (username == null) return null;

    var offset = 0;
    const limit = 100;
    while (offset < 500) {
      final page = await api.getUserRakuenFavoriteIndexes(
        username: username,
        limit: limit,
        offset: offset,
      );
      for (final slim in page.data) {
        if (slim.title != rakuenFavoriteIndexTitle &&
            !slim.desc.contains(rakuenFavoriteBlockStart)) {
          continue;
        }
        try {
          final detail = await api.getRakuenFavoriteIndex(slim.id);
          if (_looksLikeSyncIndex(detail)) return detail;
        } catch (_) {
          continue;
        }
      }
      if (page.data.length < limit) break;
      offset += limit;
    }
    return null;
  }

  Future<void> _writeCloud(RakuenFavoriteIndex index) async {
    final document = RakuenFavoriteCloudDocument(
      version: 1,
      updatedAt: DateTime.now(),
      items: favorites,
    );
    final desc = RakuenFavoriteCloudDocument.buildDescription(
      existingDescription: index.desc,
      document: document,
    );
    await api.updateRakuenFavoriteIndex(
      indexId: index.id,
      title: rakuenFavoriteIndexTitle,
      desc: desc,
      private: true,
    );
  }

  bool _looksLikeSyncIndex(RakuenFavoriteIndex index) {
    return index.title == rakuenFavoriteIndexTitle ||
        index.desc.contains(rakuenFavoriteBlockStart);
  }

  int? get _cachedCloudIndexId {
    final raw = storage.getCache(_cloudIndexCacheKey);
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  String get _favoritesCacheKey =>
      'rakuen_topic_favorites_${_activeUsername ?? 'local'}';

  String get _cloudIndexCacheKey =>
      'rakuen_topic_favorite_index_${_activeUsername ?? 'local'}';

  String get _cloudSyncPreferenceKey =>
      'rakuen_topic_favorite_cloud_enabled_${_activeUsername ?? 'local'}';

  bool? _loadCloudSyncPreference() {
    final raw = storage.getCache(_cloudSyncPreferenceKey);
    return raw is bool ? raw : null;
  }

  static String? _normalizeUsername(String? username) {
    final trimmed = username?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
