import 'package:flutter/foundation.dart';

import '../models/mikan.dart';
import '../models/subject.dart';
import '../services/mikan_service.dart';
import '../services/storage_service.dart';

class MikanProvider extends ChangeNotifier {
  final MikanService service;
  final StorageService storage;

  MikanSession? _session;
  MikanUser? _user;
  bool _loading = false;
  bool _initialized = false;
  String? _error;
  Map<int, MikanSubjectMapping> _mappings = const {};
  List<MikanBangumi>? _subscribedCache;

  MikanProvider({required this.service, required this.storage}) {
    _session = storage.mikanSession;
    _mappings = storage.getMikanSubjectMappings();
    service
      ..setBaseUrl(storage.mikanBaseUrl)
      ..setSession(_session);
  }

  MikanSession? get session => _session;
  MikanUser? get user => _user;
  bool get isLoggedIn => _session?.isValid == true;
  bool get loading => _loading;
  bool get initialized => _initialized;
  String? get error => _error;
  String get baseUrl => service.baseUrl;

  MikanSubjectMapping? mappingForSubject(int subjectId) {
    return _mappings[subjectId];
  }

  Future<void> tryRestoreSession() async {
    final saved = storage.mikanSession;
    _session = saved;
    service.setSession(saved);
    _initialized = true;
    if (saved == null || !saved.isValid) {
      _user = null;
      notifyListeners();
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _user = await service.getUser();
      if (_user == null || _user!.name.isEmpty) {
        await logout();
        _error = 'Mikan 登录已过期，请重新登录';
      }
    } catch (e) {
      _error = 'Mikan 会话验证失败: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> login(String username, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final session = await service.login(username, password);
      _session = session;
      _user = MikanUser(name: session.username);
      await storage.setMikanSession(session);
      _subscribedCache = null;
      _error = null;
      return true;
    } catch (e) {
      _error = '$e';
      return false;
    } finally {
      _initialized = true;
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _session = null;
    _user = null;
    _subscribedCache = null;
    service.setSession(null);
    await storage.setMikanSession(null);
    notifyListeners();
  }

  Future<void> setBaseUrl(String baseUrl) async {
    if (baseUrl == service.baseUrl) return;
    service.setBaseUrl(baseUrl);
    _subscribedCache = null;
    await storage.setMikanBaseUrl(service.baseUrl);
    notifyListeners();
  }

  Future<void> clearLocalMikanData() async {
    _session = null;
    _user = null;
    _subscribedCache = null;
    _mappings = const {};
    service.setSession(null);
    await storage.clearMikanData();
    notifyListeners();
  }

  Future<List<MikanBangumi>> getSubscribed({bool refresh = false}) async {
    if (!refresh && _subscribedCache != null) return _subscribedCache!;
    final data = await service.getMySubscribed();
    _subscribedCache = data;
    return data;
  }

  Future<List<MikanBangumi>> searchBangumiCandidates(Subject subject) async {
    final keyword = subject.nameCn.trim().isNotEmpty
        ? subject.nameCn.trim()
        : subject.name.trim();
    if (keyword.isEmpty) return const [];
    final result = await service.search(keyword);
    return result.bangumis;
  }

  Future<MikanBangumiDetail> getBangumiDetail(String bangumiId) {
    return service.getBangumi(bangumiId);
  }

  Future<MikanSubjectMapping?> findExactMapping(Subject subject) async {
    final saved = mappingForSubject(subject.id);
    if (saved != null && saved.bangumiId.isNotEmpty) {
      return refreshMapping(saved);
    }

    final candidates = await searchBangumiCandidates(subject);
    for (final candidate in candidates.take(5)) {
      try {
        final detail = await service.getBangumi(candidate.id);
        if (detail.bangumiSubjectId == subject.id) {
          final mapping = MikanSubjectMapping.fromSelection(
            subjectId: subject.id,
            bangumi: candidate,
            subgroup: _defaultSubgroup(detail),
          );
          await saveMapping(mapping);
          return mapping;
        }
      } catch (_) {
        // 单个候选解析失败时继续尝试后面的候选
      }
    }
    return null;
  }

  Future<void> saveMapping(MikanSubjectMapping mapping) async {
    final next = Map<int, MikanSubjectMapping>.from(_mappings);
    next[mapping.subjectId] = mapping;
    _mappings = Map.unmodifiable(next);
    await storage.setMikanSubjectMapping(mapping);
    notifyListeners();
  }

  Future<MikanSubjectMapping> refreshMapping(
    MikanSubjectMapping mapping,
  ) async {
    final detail = await service.getBangumi(mapping.bangumiId);
    final currentSubgroup =
        _subscribedSubgroup(detail) ??
        _subgroupById(detail, mapping.subgroupId) ??
        _defaultSubgroup(detail);
    final refreshed = mapping.copyWith(
      bangumiName: detail.name.isNotEmpty ? detail.name : mapping.bangumiName,
      bangumiCover: detail.cover.isNotEmpty
          ? detail.cover
          : mapping.bangumiCover,
      subgroupId: currentSubgroup?.dataId ?? mapping.subgroupId,
      subgroupName: currentSubgroup?.name ?? mapping.subgroupName,
      rss: currentSubgroup?.rss ?? mapping.rss,
      subscribed: currentSubgroup?.subscribed ?? detail.subscribed,
      updatedAt: DateTime.now(),
    );
    await saveMapping(refreshed);
    return refreshed;
  }

  Future<void> syncSubscription({
    required MikanSubjectMapping mapping,
    required bool subscribe,
  }) async {
    if (!isLoggedIn) {
      throw Exception('请先登录 Mikan');
    }
    if (subscribe) {
      await service.subscribeBangumi(
        mapping.bangumiId,
        subtitleGroupId: mapping.subgroupId,
      );
    } else {
      await service.unsubscribeBangumi(
        mapping.bangumiId,
        subtitleGroupId: mapping.subgroupId,
      );
    }
    _subscribedCache = null;
    await saveMapping(
      mapping.copyWith(subscribed: subscribe, updatedAt: DateTime.now()),
    );
  }

  MikanSubgroupBangumi? _defaultSubgroup(MikanBangumiDetail detail) {
    if (detail.subgroupBangumis.isEmpty) return null;
    return _subscribedSubgroup(detail) ?? detail.subgroupBangumis.first;
  }

  MikanSubgroupBangumi? _subscribedSubgroup(MikanBangumiDetail detail) {
    for (final item in detail.subgroupBangumis) {
      if (item.subscribed) return item;
    }
    return null;
  }

  MikanSubgroupBangumi? _subgroupById(
    MikanBangumiDetail detail,
    String subgroupId,
  ) {
    if (subgroupId.isEmpty) return null;
    for (final item in detail.subgroupBangumis) {
      if (item.dataId == subgroupId) return item;
    }
    return null;
  }
}
