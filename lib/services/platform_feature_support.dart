import 'package:flutter/foundation.dart';

import '../models/navigation_config.dart';
import '../models/subject_tab_config.dart';

class PlatformFeatureSupport {
  PlatformFeatureSupport._();

  static bool get timeline => !kIsWeb;
  static bool get rakuen => !kIsWeb;
  static bool get mikan => !kIsWeb;
  static bool get appUpdate => !kIsWeb;
  static bool get networkProxy => !kIsWeb;
  static bool get nextApi => !kIsWeb;
  static bool get webSession => !kIsWeb;
  static bool get indexes => nextApi;
  static bool get comments => nextApi;

  static bool supportsNavigationTab(String tabId) {
    return switch (tabId) {
      AppNavTabId.timeline => timeline,
      AppNavTabId.rakuen => rakuen,
      _ => true,
    };
  }

  static bool supportsSubjectTab(String tabId) {
    return switch (tabId) {
      SubjectTabConfig.indexesId => indexes,
      SubjectTabConfig.commentsId => comments,
      _ => true,
    };
  }

  static List<String> subjectTabs(Iterable<String> tabIds) {
    final supported = tabIds.where(supportsSubjectTab).toList(growable: false);
    return supported.isEmpty ? [SubjectTabConfig.overviewId] : supported;
  }
}
