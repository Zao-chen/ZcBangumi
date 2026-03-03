import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/subject.dart';
import '../pages/subject_page.dart';
import '../providers/auth_provider.dart';

/// 条目搜索页面
class SearchPage extends StatefulWidget {
  final int? initialSubjectType;
  const SearchPage({super.key, this.initialSubjectType});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late TextEditingController _searchController;
  List<SlimSubject> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;
  late int _selectedSubjectType;

  // 0 表示全部类型
  static const int _allTypes = 0;

  static const _subjectTypes = [
    (type: _allTypes, label: '全部', icon: Icons.apps_outlined),
    (type: BgmConst.subjectAnime, label: '动画', icon: Icons.movie_outlined),
    (
      type: BgmConst.subjectGame,
      label: '游戏',
      icon: Icons.sports_esports_outlined,
    ),
    (type: BgmConst.subjectBook, label: '书籍', icon: Icons.menu_book_outlined),
    (type: BgmConst.subjectMusic, label: '音乐', icon: Icons.music_note_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _selectedSubjectType = widget.initialSubjectType ?? _allTypes;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String keyword) async {
    if (keyword.isEmpty) {
      setState(() {
        _searchResults = [];
        _searchError = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      final client = auth.api;

      final results = await client.searchSubjects(
        keyword: keyword,
        type: _selectedSubjectType == _allTypes ? null : _selectedSubjectType,
        limit: 50,
      );

      setState(() {
        _searchResults = results;
        _isSearching = false;

        // 如果没有结果，设置一个用户提示信息
        if (results.isEmpty) {
          _searchError = null; // 不是真正的错误，只是没有找到
        }
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _searchError = '网络错误，请稍后重试';
        _searchResults = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索条目'), centerTitle: false),
      body: Column(
        children: [
          // 搜索框
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '搜索条目...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchResults = [];
                            _searchError = null;
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: (value) {
                setState(() {});
                if (value.isNotEmpty) {
                  _search(value);
                }
              },
            ),
          ),

          // 类型筛选
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _subjectTypes.map((config) {
                  final isSelected = _selectedSubjectType == config.type;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      selected: isSelected,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(config.icon, size: 16),
                          const SizedBox(width: 4),
                          Text(config.label),
                        ],
                      ),
                      onSelected: (selected) {
                        setState(() {
                          _selectedSubjectType = config.type;
                          if (_searchController.text.isNotEmpty) {
                            _search(_searchController.text);
                          }
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 搜索结果
          Expanded(child: _buildResultContent()),
        ],
      ),
    );
  }

  Widget _buildResultContent() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              _searchError!,
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty && _searchController.text.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('没有找到相关条目', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('输入条目名称进行搜索', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final subject = _searchResults[index];
        return _SearchResultCard(subject: subject);
      },
    );
  }
}

/// 搜索结果卡片
class _SearchResultCard extends StatelessWidget {
  final SlimSubject subject;
  const _SearchResultCard({required this.subject});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SubjectPage(subjectId: subject.id),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 60,
                  height: 84,
                  child: subject.images?.grid.isNotEmpty == true
                      ? CachedNetworkImage(
                          imageUrl: subject.images!.grid,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: colorScheme.surfaceContainerHighest,
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.image, size: 24),
                          ),
                        )
                      : Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.image, size: 24),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // 条目信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    Text(
                      subject.displayName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // 英文名
                    if (subject.name.isNotEmpty &&
                        subject.name != subject.nameCn)
                      Text(
                        subject.name,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 6),
                    // 评分和收藏
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (subject.score > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star,
                                size: 14,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                subject.score.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.favorite_border,
                              size: 14,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${subject.collectionTotal}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    // 简介
                    if (subject.shortSummary.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        subject.shortSummary,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
