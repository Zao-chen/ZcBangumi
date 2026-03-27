import 'package:flutter/foundation.dart';
import '../models/navigation_config.dart';
import '../models/subject_tab_config.dart';
import '../services/storage_service.dart';

/// 应用全局状态管理 Provider
/// 负责保存和恢复应用状态（导航索引、页面选择等）
class AppStateProvider extends ChangeNotifier {
  final StorageService storage;

  // ==================== 底部导航 ====================
  int _currentNavIndex = 0;
  List<String> _bottomNavOrder = List<String>.from(
    AppNavigationConfig.defaultOrder,
  );
  Set<String> _hiddenBottomNavTabIds = <String>{};
  List<String> _subjectTabOrder = List<String>.from(SubjectTabConfig.defaultOrder);
  Set<String> _hiddenSubjectTabIds = <String>{};

  // ==================== 动态页面 ====================
  int _timelineTabIndex = 0; // 0=全站, 1=好友, 2=我的

  // ==================== 超展开页面 ====================
  int _rakuenTabIndex = 0; // 0=全部, 1=小组, 2=条目, 3=章节, 4=角色, 5=人物

  // ==================== 我的页面 ====================
  int _profileSubjectType = 2; // BgmConst.subjectAnime
  int _profileCollectionType = 1; // BgmConst.collectionDoing
  int _profileSortMode = 0; // 最近操作

  // ==================== 设置页偏好 ====================
  bool _startupAutoRefresh = true;
  bool _pullToRefreshForceNetwork = true;
  int _listDensityMode = 1; // 0=紧凑, 1=标准, 2=舒适
  double _coverCornerRadius = 6.0;
  bool _showSecondaryInfo = true;
  bool _restoreLastTabSelection = true;
  int _defaultTimelineTabIndex = 0;
  int _defaultRakuenTabIndex = 0;
  int _updateCheckIntervalHours = 24; // 0=仅手动, 24=每天, 168=每周
  bool _updateStableOnly = true;

  AppStateProvider({required this.storage}) {
    _loadState();
  }

  // ==================== Getters ====================

  int get currentNavIndex => _currentNavIndex;
  List<String> get bottomNavOrder => List.unmodifiable(_bottomNavOrder);
  Set<String> get hiddenBottomNavTabIds =>
      Set.unmodifiable(_hiddenBottomNavTabIds);
  List<String> get enabledBottomNavTabIds => _bottomNavOrder
      .where((id) => !_hiddenBottomNavTabIds.contains(id))
      .toList(growable: false);
  List<String> get subjectTabOrder => List.unmodifiable(_subjectTabOrder);
  Set<String> get hiddenSubjectTabIds => Set.unmodifiable(_hiddenSubjectTabIds);
  List<String> get enabledSubjectTabIds => _subjectTabOrder
      .where((id) => !_hiddenSubjectTabIds.contains(id))
      .toList(growable: false);
  int get timelineTabIndex => _timelineTabIndex;
  int get rakuenTabIndex => _rakuenTabIndex;
  int get profileSubjectType => _profileSubjectType;
  int get profileCollectionType => _profileCollectionType;
  int get profileSortMode => _profileSortMode;
  bool get startupAutoRefresh => _startupAutoRefresh;
  bool get pullToRefreshForceNetwork => _pullToRefreshForceNetwork;
  int get listDensityMode => _listDensityMode;
  double get coverCornerRadius => _coverCornerRadius;
  bool get showSecondaryInfo => _showSecondaryInfo;
  bool get restoreLastTabSelection => _restoreLastTabSelection;
  int get defaultTimelineTabIndex => _defaultTimelineTabIndex;
  int get defaultRakuenTabIndex => _defaultRakuenTabIndex;
  int get updateCheckIntervalHours => _updateCheckIntervalHours;
  bool get updateStableOnly => _updateStableOnly;
  int get initialTimelineTabIndex =>
      _restoreLastTabSelection ? _timelineTabIndex : _defaultTimelineTabIndex;
  int get initialRakuenTabIndex =>
      _restoreLastTabSelection ? _rakuenTabIndex : _defaultRakuenTabIndex;

  // ==================== Setters ====================

  void setCurrentNavIndex(int index) {
    final maxIndex = enabledBottomNavTabIds.length - 1;
    final nextIndex = maxIndex >= 0 ? index.clamp(0, maxIndex) : 0;
    if (_currentNavIndex != nextIndex) {
      _currentNavIndex = nextIndex;
      notifyListeners();
      _saveState();
    }
  }

  bool isBottomNavTabVisible(String tabId) {
    return !_hiddenBottomNavTabIds.contains(tabId);
  }

  bool isSubjectTabVisible(String tabId) {
    return !_hiddenSubjectTabIds.contains(tabId);
  }

  void setBottomNavOrder(List<String> order) {
    final normalizedOrder = _normalizeBottomNavOrder(order);
    if (listEquals(_bottomNavOrder, normalizedOrder)) {
      return;
    }

    _bottomNavOrder = normalizedOrder;
    _hiddenBottomNavTabIds.removeWhere((id) => !_bottomNavOrder.contains(id));
    if (enabledBottomNavTabIds.isEmpty) {
      _hiddenBottomNavTabIds.clear();
    }
    _normalizeCurrentNavIndex();
    notifyListeners();
    _saveState();
  }

  void setBottomNavTabVisible(String tabId, bool visible) {
    if (!AppNavigationConfig.allTabIds.contains(tabId)) {
      return;
    }

    final nextHidden = Set<String>.from(_hiddenBottomNavTabIds);
    if (visible) {
      nextHidden.remove(tabId);
    } else {
      final enabledCount = _bottomNavOrder
          .where((id) => !nextHidden.contains(id))
          .length;
      if (enabledCount <= 1) {
        return;
      }
      nextHidden.add(tabId);
    }

    if (setEquals(_hiddenBottomNavTabIds, nextHidden)) {
      return;
    }

    _hiddenBottomNavTabIds = nextHidden;
    _normalizeCurrentNavIndex();
    notifyListeners();
    _saveState();
  }

  void resetBottomNavConfig() {
    final defaultOrder = List<String>.from(AppNavigationConfig.defaultOrder);
    if (listEquals(_bottomNavOrder, defaultOrder) &&
        _hiddenBottomNavTabIds.isEmpty) {
      return;
    }

    _bottomNavOrder = defaultOrder;
    _hiddenBottomNavTabIds.clear();
    _normalizeCurrentNavIndex();
    notifyListeners();
    _saveState();
  }

  void setSubjectTabOrder(List<String> order) {
    final normalizedOrder = _normalizeSubjectTabOrder(order);
    if (listEquals(_subjectTabOrder, normalizedOrder)) {
      return;
    }

    _subjectTabOrder = normalizedOrder;
    _hiddenSubjectTabIds.removeWhere((id) => !_subjectTabOrder.contains(id));
    if (enabledSubjectTabIds.isEmpty) {
      _hiddenSubjectTabIds.clear();
    }
    notifyListeners();
    _saveState();
  }

  void setSubjectTabVisible(String tabId, bool visible) {
    if (!SubjectTabConfig.allTabIds.contains(tabId)) {
      return;
    }

    final nextHidden = Set<String>.from(_hiddenSubjectTabIds);
    if (visible) {
      nextHidden.remove(tabId);
    } else {
      final enabledCount = _subjectTabOrder
          .where((id) => !nextHidden.contains(id))
          .length;
      if (enabledCount <= 1) {
        return;
      }
      nextHidden.add(tabId);
    }

    if (setEquals(_hiddenSubjectTabIds, nextHidden)) {
      return;
    }

    _hiddenSubjectTabIds = nextHidden;
    notifyListeners();
    _saveState();
  }

  void resetSubjectTabConfig() {
    final defaultOrder = List<String>.from(SubjectTabConfig.defaultOrder);
    if (listEquals(_subjectTabOrder, defaultOrder) &&
        _hiddenSubjectTabIds.isEmpty) {
      return;
    }

    _subjectTabOrder = defaultOrder;
    _hiddenSubjectTabIds.clear();
    notifyListeners();
    _saveState();
  }

  void setTimelineTabIndex(int index) {
    if (_timelineTabIndex != index) {
      _timelineTabIndex = index;
      notifyListeners();
      _saveState();
    }
  }

  void setRakuenTabIndex(int index) {
    if (_rakuenTabIndex != index) {
      _rakuenTabIndex = index;
      notifyListeners();
      _saveState();
    }
  }

  void setProfileSubjectType(int type) {
    if (_profileSubjectType != type) {
      _profileSubjectType = type;
      notifyListeners();
      _saveState();
    }
  }

  void setProfileCollectionType(int type) {
    if (_profileCollectionType != type) {
      _profileCollectionType = type;
      notifyListeners();
      _saveState();
    }
  }

  void setProfileSortMode(int mode) {
    if (_profileSortMode != mode) {
      _profileSortMode = mode;
      notifyListeners();
      _saveState();
    }
  }

  void setStartupAutoRefresh(bool value) {
    if (_startupAutoRefresh != value) {
      _startupAutoRefresh = value;
      notifyListeners();
      _saveState();
    }
  }

  void setPullToRefreshForceNetwork(bool value) {
    if (_pullToRefreshForceNetwork != value) {
      _pullToRefreshForceNetwork = value;
      notifyListeners();
      _saveState();
    }
  }

  void setListDensityMode(int mode) {
    final nextMode = mode.clamp(0, 2);
    if (_listDensityMode != nextMode) {
      _listDensityMode = nextMode;
      notifyListeners();
      _saveState();
    }
  }

  void setCoverCornerRadius(double radius) {
    final next = radius.clamp(0, 20).toDouble();
    if (_coverCornerRadius != next) {
      _coverCornerRadius = next;
      notifyListeners();
      _saveState();
    }
  }

  void setShowSecondaryInfo(bool value) {
    if (_showSecondaryInfo != value) {
      _showSecondaryInfo = value;
      notifyListeners();
      _saveState();
    }
  }

  void setRestoreLastTabSelection(bool value) {
    if (_restoreLastTabSelection != value) {
      _restoreLastTabSelection = value;
      notifyListeners();
      _saveState();
    }
  }

  void setDefaultTimelineTabIndex(int index) {
    final next = index.clamp(0, 2);
    if (_defaultTimelineTabIndex != next) {
      _defaultTimelineTabIndex = next;
      notifyListeners();
      _saveState();
    }
  }

  void setDefaultRakuenTabIndex(int index) {
    final next = index.clamp(0, 5);
    if (_defaultRakuenTabIndex != next) {
      _defaultRakuenTabIndex = next;
      notifyListeners();
      _saveState();
    }
  }

  void setUpdateCheckIntervalHours(int hours) {
    final next = <int>{0, 24, 168}.contains(hours) ? hours : 24;
    if (_updateCheckIntervalHours != next) {
      _updateCheckIntervalHours = next;
      notifyListeners();
      _saveState();
    }
  }

  void setUpdateStableOnly(bool value) {
    if (_updateStableOnly != value) {
      _updateStableOnly = value;
      notifyListeners();
      _saveState();
    }
  }

  // ==================== 持久化 ====================

  /// 加载保存的状态
  Future<void> _loadState() async {
    try {
      final data = storage.getCache('app_state') as Map<String, dynamic>?;
      if (data != null) {
        _bottomNavOrder = _normalizeBottomNavOrder(
          ((data['bottomNavOrder'] as List?) ??
                  AppNavigationConfig.defaultOrder)
              .map((id) => '$id')
              .toList(growable: false),
        );

        _hiddenBottomNavTabIds =
            ((data['hiddenBottomNavTabIds'] as List?) ?? const <dynamic>[])
                .map((id) => '$id')
                .where((id) => _bottomNavOrder.contains(id))
                .toSet();
        if (enabledBottomNavTabIds.isEmpty) {
          _hiddenBottomNavTabIds.clear();
        }

        _subjectTabOrder = _normalizeSubjectTabOrder(
          ((data['subjectTabOrder'] as List?) ?? SubjectTabConfig.defaultOrder)
              .map((id) => '$id')
              .toList(growable: false),
        );
        _hiddenSubjectTabIds =
            ((data['hiddenSubjectTabIds'] as List?) ?? const <dynamic>[])
                .map((id) => '$id')
                .where((id) => _subjectTabOrder.contains(id))
                .toSet();
        if (enabledSubjectTabIds.isEmpty) {
          _hiddenSubjectTabIds.clear();
        }

        final cachedNavIndex = data['currentNavIndex'] as int? ?? 0;
        _currentNavIndex = cachedNavIndex;
        _normalizeCurrentNavIndex();
        _timelineTabIndex = data['timelineTabIndex'] ?? 0;
        _rakuenTabIndex = (data['rakuenTabIndex'] as int? ?? 0).clamp(0, 5);
        _profileSubjectType = data['profileSubjectType'] ?? 2;
        _profileCollectionType = data['profileCollectionType'] ?? 1;
        _profileSortMode = data['profileSortMode'] ?? 0;
        _startupAutoRefresh = data['startupAutoRefresh'] ?? true;
        _pullToRefreshForceNetwork = data['pullToRefreshForceNetwork'] ?? true;
        _listDensityMode = (data['listDensityMode'] as int? ?? 1).clamp(0, 2);
        _coverCornerRadius = ((data['coverCornerRadius'] as num?) ?? 6.0)
            .toDouble()
            .clamp(0, 20);
        _showSecondaryInfo = data['showSecondaryInfo'] ?? true;
        _restoreLastTabSelection = data['restoreLastTabSelection'] ?? true;
        _defaultTimelineTabIndex =
            (data['defaultTimelineTabIndex'] as int? ?? 0).clamp(0, 2);
        _defaultRakuenTabIndex = (data['defaultRakuenTabIndex'] as int? ?? 0)
            .clamp(0, 5);
        final loadedUpdateHours = data['updateCheckIntervalHours'] as int?;
        _updateCheckIntervalHours =
            <int>{0, 24, 168}.contains(loadedUpdateHours)
            ? loadedUpdateHours!
            : 24;
        _updateStableOnly = data['updateStableOnly'] ?? true;
        notifyListeners();
      }
    } catch (_) {
      // 加载失败，使用默认值
    }
  }

  /// 保存状态
  Future<void> _saveState() async {
    try {
      final data = {
        'currentNavIndex': _currentNavIndex,
        'bottomNavOrder': _bottomNavOrder,
        'hiddenBottomNavTabIds': _hiddenBottomNavTabIds.toList(),
        'subjectTabOrder': _subjectTabOrder,
        'hiddenSubjectTabIds': _hiddenSubjectTabIds.toList(),
        'timelineTabIndex': _timelineTabIndex,
        'rakuenTabIndex': _rakuenTabIndex,
        'profileSubjectType': _profileSubjectType,
        'profileCollectionType': _profileCollectionType,
        'profileSortMode': _profileSortMode,
        'startupAutoRefresh': _startupAutoRefresh,
        'pullToRefreshForceNetwork': _pullToRefreshForceNetwork,
        'listDensityMode': _listDensityMode,
        'coverCornerRadius': _coverCornerRadius,
        'showSecondaryInfo': _showSecondaryInfo,
        'restoreLastTabSelection': _restoreLastTabSelection,
        'defaultTimelineTabIndex': _defaultTimelineTabIndex,
        'defaultRakuenTabIndex': _defaultRakuenTabIndex,
        'updateCheckIntervalHours': _updateCheckIntervalHours,
        'updateStableOnly': _updateStableOnly,
      };
      await storage.setCache('app_state', data);
    } catch (_) {
      // 保存失败，忽略
    }
  }

  /// 清除所有保存的状态（用户退出登录时）
  Future<void> clearState() async {
    _currentNavIndex = 0;
    _bottomNavOrder = List<String>.from(AppNavigationConfig.defaultOrder);
    _hiddenBottomNavTabIds.clear();
    _subjectTabOrder = List<String>.from(SubjectTabConfig.defaultOrder);
    _hiddenSubjectTabIds.clear();
    _timelineTabIndex = 0;
    _rakuenTabIndex = 0;
    _profileSubjectType = 2;
    _profileCollectionType = 1;
    _profileSortMode = 0;
    _startupAutoRefresh = true;
    _pullToRefreshForceNetwork = true;
    _listDensityMode = 1;
    _coverCornerRadius = 6.0;
    _showSecondaryInfo = true;
    _restoreLastTabSelection = true;
    _defaultTimelineTabIndex = 0;
    _defaultRakuenTabIndex = 0;
    _updateCheckIntervalHours = 24;
    _updateStableOnly = true;
    notifyListeners();
    try {
      await storage.setCache('app_state', null);
    } catch (_) {}
  }

  List<String> _normalizeBottomNavOrder(List<String> order) {
    final seen = <String>{};
    final normalized = <String>[];

    for (final id in order) {
      if (AppNavigationConfig.allTabIds.contains(id) && seen.add(id)) {
        normalized.add(id);
      }
    }

    for (final id in AppNavigationConfig.allTabIds) {
      if (seen.add(id)) {
        normalized.add(id);
      }
    }

    return normalized;
  }

  List<String> _normalizeSubjectTabOrder(List<String> order) {
    final seen = <String>{};
    final normalized = <String>[];

    for (final id in order) {
      if (SubjectTabConfig.allTabIds.contains(id) && seen.add(id)) {
        normalized.add(id);
      }
    }

    for (final id in SubjectTabConfig.allTabIds) {
      if (seen.add(id)) {
        normalized.add(id);
      }
    }

    return normalized;
  }

  void _normalizeCurrentNavIndex() {
    final maxIndex = enabledBottomNavTabIds.length - 1;
    _currentNavIndex = maxIndex >= 0 ? _currentNavIndex.clamp(0, maxIndex) : 0;
  }
}
