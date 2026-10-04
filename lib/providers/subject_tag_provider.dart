import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/subject.dart';
import '../models/subject_tag_query.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';

class SubjectTagProvider extends ChangeNotifier {
  final ApiClient api;
  final StorageService storage;
  final int pageSize;

  SubjectTagQuery _query;
  List<SlimSubject> _subjects = const [];
  bool _hasSearched = false;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _disposed = false;
  int _total = 0;
  int _nextOffset = 0;
  int _generation = 0;
  String? _error;
  String? _loadMoreError;
  String? _storageError;

  SubjectTagProvider({
    required this.api,
    required this.storage,
    SubjectTagQuery initialQuery = const SubjectTagQuery(),
    this.pageSize = 30,
  }) : _query = initialQuery;

  SubjectTagQuery get query => _query;
  List<SlimSubject> get subjects => UnmodifiableListView(_subjects);
  bool get hasSearched => _hasSearched;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  int get total => _total;
  String? get error => _error;
  String? get loadMoreError => _loadMoreError;
  String? get storageError => _storageError;
  List<SubjectTagQuery> get recentSearches => storage.recentTagSearches;
  List<SubjectTagQuery> get favorites => storage.favoriteTagSearches;
  bool get isFavorite =>
      favorites.any((entry) => entry.identity == _query.identity);

  List<RelatedSubjectTag> get relatedTags {
    final counts = <String, int>{};
    final selected = _query.options.tags.toSet();
    for (final subject in _subjects) {
      for (final tag in normalizeSubjectTags(subject.tags)) {
        if (!selected.contains(tag)) {
          counts.update(tag, (count) => count + 1, ifAbsent: () => 1);
        }
      }
    }
    final tags = counts.entries
        .map(
          (entry) =>
              RelatedSubjectTag(name: entry.key, subjectCount: entry.value),
        )
        .toList();
    tags.sort((first, second) {
      final countOrder = second.subjectCount.compareTo(first.subjectCount);
      return countOrder == 0 ? first.name.compareTo(second.name) : countOrder;
    });
    return tags.take(12).toList(growable: false);
  }

  void showHome({SubjectTagQuery? query}) {
    _generation++;
    _query = query ?? SubjectTagQuery(subjectType: _query.subjectType);
    _subjects = const [];
    _hasSearched = false;
    _loading = false;
    _loadingMore = false;
    _hasMore = false;
    _total = 0;
    _nextOffset = 0;
    _error = null;
    _loadMoreError = null;
    notifyListeners();
  }

  Future<void> search(SubjectTagQuery query) async {
    _query = query
        .copyWith(keyword: query.keyword.trim())
        .withTags(query.options.tags);
    _hasSearched = true;
    _loading = true;
    _loadingMore = false;
    _hasMore = false;
    _subjects = const [];
    _total = 0;
    _nextOffset = 0;
    _error = null;
    _loadMoreError = null;
    final generation = ++_generation;
    notifyListeners();
    await _loadPage(generation: generation, offset: 0, refresh: true);
  }

  Future<void> refresh() => search(_query);

  Future<void> loadMore() async {
    if (_disposed || !_hasMore || _loading || _loadingMore) return;
    _loadingMore = true;
    _loadMoreError = null;
    notifyListeners();
    await _loadPage(
      generation: _generation,
      offset: _nextOffset,
      refresh: false,
    );
  }

  Future<void> _loadPage({
    required int generation,
    required int offset,
    required bool refresh,
  }) async {
    final query = _query;
    try {
      final page = await api.searchSubjects(
        keyword: query.keyword,
        sort: query.sort,
        filter: query.filter,
        limit: pageSize,
        offset: offset,
      );
      if (_disposed || generation != _generation) return;
      final knownIds = <int>{};
      _subjects = [
        if (!refresh) ..._subjects,
        ...page.data,
      ].where((subject) => knownIds.add(subject.id)).toList(growable: false);
      _total = page.total;
      _nextOffset = page.offset + page.data.length;
      _hasMore = page.data.isNotEmpty && _nextOffset < page.total;
      _loading = false;
      _loadingMore = false;
      notifyListeners();
      if (refresh) {
        await _saveLocal(() => storage.recordTagSearch(query));
      }
    } catch (_) {
      if (_disposed || generation != _generation) return;
      if (refresh) {
        _error = '标签搜索失败，请检查网络后重试';
      } else {
        _loadMoreError = '加载更多失败，已保留当前条目';
      }
      _loading = false;
      _loadingMore = false;
      notifyListeners();
    }
  }

  Future<void> toggleFavorite([SubjectTagQuery? query]) =>
      _saveLocal(() => storage.toggleFavoriteTagSearch(query ?? _query));

  Future<void> clearRecentSearches() =>
      _saveLocal(storage.clearRecentTagSearches);

  Future<void> _saveLocal(Future<void> Function() action) async {
    try {
      await action();
      _storageError = null;
    } catch (_) {
      _storageError = '本地标签记录保存失败，不影响 API 搜索';
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
