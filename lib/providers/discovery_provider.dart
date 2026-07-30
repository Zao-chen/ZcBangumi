import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/calendar.dart';
import '../models/recent_view_item.dart';
import '../models/subject.dart';
import '../models/subject_browse.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import 'connectivity_provider.dart';

class DiscoveryBrowseLoad {
  final PagedResult<SlimSubject> page;
  final bool fromCache;
  final Object? refreshError;

  const DiscoveryBrowseLoad({
    required this.page,
    this.fromCache = false,
    this.refreshError,
  });
}

class DiscoveryProvider extends ChangeNotifier {
  static const _calendarCacheKey = 'discovery_calendar_v1';
  static const _calendarMaxAge = Duration(hours: 6);
  static const _browseMaxAge = Duration(hours: 24);

  final ApiClient api;
  final StorageService storage;
  final ConnectivityProvider? connectivity;
  final DateTime Function() now;

  DiscoveryProvider({
    required this.api,
    required this.storage,
    this.connectivity,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  List<CalendarDay> _calendar = const [];
  List<RecentViewItem> _recentItems = const [];
  final Map<String, List<SlimSubject>> _previews = {};
  final Map<String, bool> _previewLoading = {};
  final Map<String, String?> _previewErrors = {};
  final Map<String, Future<void>> _previewRequests = {};
  final Map<String, Future<DiscoveryBrowseLoad>> _browseRequests = {};

  bool _calendarLoading = false;
  bool _initialized = false;
  String? _calendarError;
  Future<void>? _calendarRequest;

  List<CalendarDay> get calendar => List.unmodifiable(_calendar);
  List<RecentViewItem> get recentItems => List.unmodifiable(_recentItems);
  bool get calendarLoading => _calendarLoading;
  String? get calendarError => _calendarError;

  List<SlimSubject> previewFor(int type, SubjectBrowseSort sort) =>
      List.unmodifiable(_previews[_previewKey(type, sort)] ?? const []);
  bool previewLoading(int type, SubjectBrowseSort sort) =>
      _previewLoading[_previewKey(type, sort)] ?? false;
  String? previewError(int type, SubjectBrowseSort sort) =>
      _previewErrors[_previewKey(type, sort)];

  List<SlimSubject> rankingFor(int type) =>
      previewFor(type, SubjectBrowseSort.rank);
  bool rankingLoading(int type) => previewLoading(type, SubjectBrowseSort.rank);
  String? rankingError(int type) => previewError(type, SubjectBrowseSort.rank);

  Future<void> initialize({required int rankingType}) async {
    if (!_initialized) {
      _initialized = true;
      _restoreCalendarCache();
      refreshRecentItems();
    }
    _restorePreviewCache(rankingType, SubjectBrowseSort.rank);
    await Future.wait([
      loadCalendar(),
      loadPreview(rankingType, SubjectBrowseSort.rank),
    ]);
  }

  Future<void> refreshHome(
    int rankingType, {
    SubjectBrowseSort sort = SubjectBrowseSort.rank,
  }) {
    refreshRecentItems();
    return Future.wait([
      loadCalendar(forceNetwork: true),
      loadPreview(rankingType, sort, forceNetwork: true),
    ]);
  }

  void refreshRecentItems() {
    _recentItems = storage.getRecentViewItems(limit: 12);
    notifyListeners();
  }

  Future<void> clearRecentItems() async {
    await storage.clearRecentViewItems();
    _recentItems = const [];
    notifyListeners();
  }

  Future<void> loadCalendar({bool forceNetwork = false}) {
    final inFlight = _calendarRequest;
    if (inFlight != null) return inFlight;

    final cacheEntry = storage.getCacheEntry(_calendarCacheKey, touch: false);
    if (_calendar.isEmpty) {
      _restoreCalendarCache(entry: cacheEntry);
    }
    if (!forceNetwork && _calendar.isNotEmpty && _isCalendarFresh(cacheEntry)) {
      return Future.value();
    }

    final request = _loadCalendarFromNetwork();
    _calendarRequest = request;
    request.whenComplete(() {
      if (identical(_calendarRequest, request)) {
        _calendarRequest = null;
      }
    });
    return request;
  }

  Future<void> _loadCalendarFromNetwork() async {
    _calendarLoading = _calendar.isEmpty;
    _calendarError = null;
    notifyListeners();
    try {
      final result = await api.getCalendar();
      _calendar = result;
      _calendarError = null;
      connectivity?.reportNetworkSuccess();
      unawaited(
        storage.setCache(
          _calendarCacheKey,
          result.map((day) => day.toJson()).toList(),
        ),
      );
    } catch (error) {
      _calendarError = _calendar.isEmpty ? '每日放送加载失败，请重试' : '每日放送刷新失败';
      connectivity?.reportNetworkFailure(error);
    } finally {
      _calendarLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadRanking(int type, {bool forceNetwork = false}) {
    return loadPreview(
      type,
      SubjectBrowseSort.rank,
      forceNetwork: forceNetwork,
    );
  }

  Future<void> loadPreview(
    int type,
    SubjectBrowseSort sort, {
    bool forceNetwork = false,
  }) {
    final stateKey = _previewKey(type, sort);
    final inFlight = _previewRequests[stateKey];
    if (inFlight != null) return inFlight;

    final cacheKey = _previewCacheKey(type, sort);
    final cacheEntry = storage.getCacheEntry(cacheKey, touch: false);
    if ((_previews[stateKey] ?? const []).isEmpty) {
      _restorePreviewCache(type, sort, entry: cacheEntry);
    }
    if (!forceNetwork &&
        (_previews[stateKey] ?? const []).isNotEmpty &&
        _isFresh(cacheEntry, _browseMaxAge)) {
      return Future.value();
    }

    final request = _loadPreviewFromNetwork(type, sort);
    _previewRequests[stateKey] = request;
    request.whenComplete(() {
      if (identical(_previewRequests[stateKey], request)) {
        _previewRequests.remove(stateKey);
      }
    });
    return request;
  }

  Future<void> _loadPreviewFromNetwork(int type, SubjectBrowseSort sort) async {
    final stateKey = _previewKey(type, sort);
    _previewLoading[stateKey] = (_previews[stateKey] ?? const []).isEmpty;
    _previewErrors[stateKey] = null;
    notifyListeners();
    try {
      final result = await api.browseSubjects(
        filter: SubjectBrowseFilter(type: type, sort: sort),
        limit: 10,
      );
      _previews[stateKey] = result.data;
      _previewErrors[stateKey] = null;
      connectivity?.reportNetworkSuccess();
      unawaited(
        storage.setCache(_previewCacheKey(type, sort), _pageToJson(result)),
      );
    } catch (error) {
      _previewErrors[stateKey] = (_previews[stateKey] ?? const []).isEmpty
          ? '条目预览加载失败，请重试'
          : '条目预览刷新失败';
      connectivity?.reportNetworkFailure(error);
    } finally {
      _previewLoading[stateKey] = false;
      notifyListeners();
    }
  }

  Future<DiscoveryBrowseLoad> browseSubjects({
    required SubjectBrowseFilter filter,
    int limit = 30,
    int offset = 0,
    bool forceNetwork = false,
  }) {
    PagedResult<SlimSubject>? cachedPage;
    String? cacheKey;
    if (offset == 0) {
      cacheKey = _browseCacheKey(filter, limit);
      final entry = storage.getCacheEntry(cacheKey, touch: false);
      cachedPage = _pageFromCache(entry?.data);
      if (!forceNetwork &&
          cachedPage != null &&
          _isFresh(entry, _browseMaxAge)) {
        return Future.value(
          DiscoveryBrowseLoad(page: cachedPage, fromCache: true),
        );
      }
    }

    final requestKey = '${filter.cacheKey}_${limit}_$offset';
    final inFlight = _browseRequests[requestKey];
    if (inFlight != null) return inFlight;

    final request = _loadBrowsePage(
      filter: filter,
      limit: limit,
      offset: offset,
      cacheKey: cacheKey,
      cachedPage: cachedPage,
    );
    _browseRequests[requestKey] = request;
    request.then<void>(
      (_) => _clearBrowseRequest(requestKey, request),
      onError: (_, _) => _clearBrowseRequest(requestKey, request),
    );
    return request;
  }

  Future<DiscoveryBrowseLoad> _loadBrowsePage({
    required SubjectBrowseFilter filter,
    required int limit,
    required int offset,
    required String? cacheKey,
    required PagedResult<SlimSubject>? cachedPage,
  }) async {
    try {
      final page = await api.browseSubjects(
        filter: filter,
        limit: limit,
        offset: offset,
      );
      connectivity?.reportNetworkSuccess();
      if (cacheKey != null) {
        await storage.setCache(cacheKey, _pageToJson(page));
      }
      return DiscoveryBrowseLoad(page: page);
    } catch (error) {
      connectivity?.reportNetworkFailure(error);
      if (cachedPage != null) {
        return DiscoveryBrowseLoad(
          page: cachedPage,
          fromCache: true,
          refreshError: error,
        );
      }
      rethrow;
    }
  }

  void _clearBrowseRequest(
    String requestKey,
    Future<DiscoveryBrowseLoad> request,
  ) {
    if (identical(_browseRequests[requestKey], request)) {
      _browseRequests.remove(requestKey);
    }
  }

  void _restoreCalendarCache({CacheEntry? entry}) {
    final cacheEntry =
        entry ?? storage.getCacheEntry(_calendarCacheKey, touch: false);
    final data = cacheEntry?.data;
    if (data is! List) return;
    try {
      _calendar = data
          .whereType<Map>()
          .map((item) => CalendarDay.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } catch (_) {
      _calendar = const [];
    }
  }

  void _restorePreviewCache(
    int type,
    SubjectBrowseSort sort, {
    CacheEntry? entry,
  }) {
    final cacheEntry =
        entry ??
        storage.getCacheEntry(_previewCacheKey(type, sort), touch: false);
    final page = _pageFromCache(cacheEntry?.data);
    if (page != null) {
      _previews[_previewKey(type, sort)] = page.data;
    }
  }

  bool _isCalendarFresh(CacheEntry? entry) {
    if (!_isFresh(entry, _calendarMaxAge)) return false;
    final updated = entry!.updatedAt.toLocal();
    final current = now().toLocal();
    return updated.year == current.year &&
        updated.month == current.month &&
        updated.day == current.day;
  }

  bool _isFresh(CacheEntry? entry, Duration maxAge) {
    if (entry == null) return false;
    return now().difference(entry.updatedAt) <= maxAge;
  }

  String _previewKey(int type, SubjectBrowseSort sort) =>
      '${type}_${sort.apiValue}';

  String _previewCacheKey(int type, SubjectBrowseSort sort) =>
      sort == SubjectBrowseSort.rank
      ? 'discovery_ranking_${type}_v1'
      : 'discovery_preview_${type}_${sort.apiValue}_v1';

  String _browseCacheKey(SubjectBrowseFilter filter, int limit) =>
      'discovery_browse_${filter.cacheKey}_${limit}_v1';

  Map<String, dynamic> _pageToJson(PagedResult<SlimSubject> page) => {
    'total': page.total,
    'limit': page.limit,
    'offset': page.offset,
    'data': page.data.map((subject) => subject.toJson()).toList(),
  };

  PagedResult<SlimSubject>? _pageFromCache(dynamic raw) {
    if (raw is! Map) return null;
    try {
      final map = Map<String, dynamic>.from(raw);
      final data = (map['data'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => SlimSubject.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
      return PagedResult<SlimSubject>(
        total: (map['total'] as num?)?.toInt() ?? data.length,
        limit: (map['limit'] as num?)?.toInt() ?? data.length,
        offset: (map['offset'] as num?)?.toInt() ?? 0,
        data: data,
      );
    } catch (_) {
      return null;
    }
  }
}
