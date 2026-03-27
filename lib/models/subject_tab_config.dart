import 'package:flutter/material.dart';

class SubjectTabConfigItem {
  final String id;
  final String label;
  final IconData icon;

  const SubjectTabConfigItem({
    required this.id,
    required this.label,
    required this.icon,
  });
}

class SubjectTabConfig {
  static const String overviewId = 'overview';
  static const String charactersId = 'characters';
  static const String relatedId = 'related';
  static const String commentsId = 'comments';
  static const String moegirlId = 'moegirl';

  static const List<SubjectTabConfigItem> allTabs = [
    SubjectTabConfigItem(
      id: overviewId,
      label: '\u6982\u8ff0',
      icon: Icons.article_outlined,
    ),
    SubjectTabConfigItem(
      id: charactersId,
      label: '\u89d2\u8272',
      icon: Icons.groups_outlined,
    ),
    SubjectTabConfigItem(
      id: relatedId,
      label: '\u5173\u8054',
      icon: Icons.link_outlined,
    ),
    SubjectTabConfigItem(
      id: commentsId,
      label: '\u5410\u69fd',
      icon: Icons.chat_bubble_outline,
    ),
    SubjectTabConfigItem(
      id: moegirlId,
      label: '\u840c\u767e',
      icon: Icons.menu_book_outlined,
    ),
  ];

  static const List<String> allTabIds = [
    overviewId,
    charactersId,
    relatedId,
    commentsId,
    moegirlId,
  ];

  static const List<String> defaultOrder = allTabIds;

  static SubjectTabConfigItem? getById(String id) {
    for (final tab in allTabs) {
      if (tab.id == id) {
        return tab;
      }
    }
    return null;
  }
}
