import 'package:flutter/foundation.dart';
import '../services/storage_service.dart';

/// 应用全局状态管理 Provider
/// 负责保存和恢复应用状态（导航索引、页面选择等）
class AppStateProvider extends ChangeNotifier {
  final StorageService storage;

  // ==================== 底部导航 ====================
  int _currentNavIndex = 0;

  // ==================== 动态页面 ====================
  int _timelineTabIndex = 0; // 0=全站, 1=好友, 2=我的

  // ==================== 我的页面 ====================
  int _profileSubjectType = 2; // BgmConst.subjectAnime
  int _profileCollectionType = 1; // BgmConst.collectionDoing
  int _profileSortMode = 0; // 最近操作

  AppStateProvider({required this.storage}) {
    _loadState();
  }

  // ==================== Getters ====================

  int get currentNavIndex => _currentNavIndex;
  int get timelineTabIndex => _timelineTabIndex;
  int get profileSubjectType => _profileSubjectType;
  int get profileCollectionType => _profileCollectionType;
  int get profileSortMode => _profileSortMode;

  // ==================== Setters ====================

  void setCurrentNavIndex(int index) {
    if (_currentNavIndex != index) {
      _currentNavIndex = index;
      notifyListeners();
      _saveState();
    }
  }

  void setTimelineTabIndex(int index) {
    if (_timelineTabIndex != index) {
      _timelineTabIndex = index;
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

  // ==================== 持久化 ====================

  /// 加载保存的状态
  Future<void> _loadState() async {
    try {
      final data = storage.getCache('app_state') as Map<String, dynamic>?;
      if (data != null) {
        _currentNavIndex = data['currentNavIndex'] ?? 0;
        _timelineTabIndex = data['timelineTabIndex'] ?? 0;
        _profileSubjectType = data['profileSubjectType'] ?? 2;
        _profileCollectionType = data['profileCollectionType'] ?? 1;
        _profileSortMode = data['profileSortMode'] ?? 0;
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
        'timelineTabIndex': _timelineTabIndex,
        'profileSubjectType': _profileSubjectType,
        'profileCollectionType': _profileCollectionType,
        'profileSortMode': _profileSortMode,
      };
      await storage.setCache('app_state', data);
    } catch (_) {
      // 保存失败，忽略
    }
  }

  /// 清除所有保存的状态（用户退出登录时）
  Future<void> clearState() async {
    _currentNavIndex = 0;
    _timelineTabIndex = 0;
    _profileSubjectType = 2;
    _profileCollectionType = 1;
    _profileSortMode = 0;
    notifyListeners();
    try {
      await storage.setCache('app_state', null);
    } catch (_) {}
  }
}
