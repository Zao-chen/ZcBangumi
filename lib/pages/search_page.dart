import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/subject.dart';
import '../pages/subject_page.dart';
import '../providers/app_state_provider.dart';
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
  String _submittedQuery = '';
  int _searchGeneration = 0;

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
    final query = keyword.trim();
    final generation = ++_searchGeneration;

    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _searchError = null;
        _submittedQuery = '';
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
      _submittedQuery = query;
    });

    try {
      final auth = context.read<AuthProvider>();
      final client = auth.api;

      final results = await client.searchSubjects(
        keyword: query,
        type: _selectedSubjectType == _allTypes ? null : _selectedSubjectType,
        limit: 50,
        enrichDetails: true,
      );

      if (!mounted || generation != _searchGeneration) return;

      setState(() {
        _searchResults = results;
        _isSearching = false;

        // 如果没有结果，设置一个用户提示信息
        if (results.isEmpty) {
          _searchError = null; // 不是真正的错误，只是没有找到
        }
      });
    } catch (e) {
      if (!mounted || generation != _searchGeneration) return;

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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTypeRail(),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                        child: _buildSearchField(),
                      ),
                      Expanded(child: _buildResultContent(24, true)),
                    ],
                  ),
                ),
              ],
            );
          }

          return Column(
            children: [
              // 搜索框
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: _buildSearchField(),
              ),

              // 类型筛选
              _buildTypeChips(),

              const SizedBox(height: 16),

              // 搜索结果
              Expanded(child: _buildResultContent(12, false)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      autofocus: true,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: '搜索条目...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear), onPressed: _clearSearch)
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      onChanged: (value) {
        setState(() {});
      },
      onSubmitted: _search,
    );
  }

  Widget _buildTypeChips() {
    return Padding(
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
                onSelected: (_) => _selectSubjectType(config.type),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTypeRail() {
    return NavigationRail(
      minWidth: 112,
      labelType: NavigationRailLabelType.all,
      selectedIndex: _selectedSubjectIndex,
      onDestinationSelected: (index) {
        _selectSubjectType(_subjectTypes[index].type);
      },
      destinations: _subjectTypes
          .map(
            (config) => NavigationRailDestination(
              icon: Icon(config.icon),
              selectedIcon: Icon(config.icon),
              label: Text(config.label),
            ),
          )
          .toList(),
    );
  }

  int get _selectedSubjectIndex {
    final index = _subjectTypes.indexWhere(
      (config) => config.type == _selectedSubjectType,
    );
    return index >= 0 ? index : 0;
  }

  void _selectSubjectType(int type) {
    if (_selectedSubjectType == type) return;
    setState(() {
      _selectedSubjectType = type;
    });
    if (_submittedQuery.isNotEmpty) {
      _search(_submittedQuery);
    }
  }

  void _clearSearch() {
    _searchGeneration++;
    _searchController.clear();
    setState(() {
      _searchResults = [];
      _searchError = null;
      _submittedQuery = '';
      _isSearching = false;
    });
  }

  Widget _buildResultContent(double horizontalPadding, bool isWide) {
    if (_isSearching) {
      return _buildSearchSkeletonList(horizontalPadding, isWide);
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

    if (_searchResults.isEmpty && _submittedQuery.isNotEmpty) {
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

    final listPadding = EdgeInsets.symmetric(
      horizontal: horizontalPadding,
      vertical: isWide ? 4 : 0,
    );

    if (isWide) {
      return GridView.builder(
        padding: listPadding,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisExtent: 112,
          crossAxisSpacing: 12,
          mainAxisSpacing: 4,
        ),
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final subject = _searchResults[index];
          return _SearchResultCard(subject: subject);
        },
      );
    }

    return ListView.builder(
      padding: listPadding,
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final subject = _searchResults[index];
        return _SearchResultCard(subject: subject);
      },
    );
  }

  Widget _buildSearchSkeletonList(double horizontalPadding, bool isWide) {
    final colorScheme = Theme.of(context).colorScheme;
    final listPadding = EdgeInsets.symmetric(
      horizontal: horizontalPadding,
      vertical: isWide ? 4 : 0,
    );

    Widget skeletonCard(int index) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                height: 84,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 160,
                      height: 14,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 190,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (isWide) {
      return GridView.builder(
        padding: listPadding,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisExtent: 112,
          crossAxisSpacing: 12,
          mainAxisSpacing: 4,
        ),
        itemCount: 8,
        itemBuilder: (context, index) => skeletonCard(index),
      );
    }

    return ListView.builder(
      padding: listPadding,
      itemCount: 6,
      itemBuilder: (context, index) => skeletonCard(index),
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
    final appState = context.watch<AppStateProvider>();
    final densityScale = switch (appState.listDensityMode) {
      0 => 0.88,
      2 => 1.12,
      _ => 1.0,
    };
    final cardPadding = 10.0 * densityScale;
    final coverWidth = 56.0 * densityScale;
    final coverHeight = 80.0 * densityScale;
    final coverRadius = appState.coverCornerRadius;
    final showSecondary = _hasSecondaryInfo;

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
          padding: EdgeInsets.all(cardPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面
              ClipRRect(
                borderRadius: BorderRadius.circular(coverRadius),
                child: SizedBox(
                  width: coverWidth,
                  height: coverHeight,
                  child: subject.images?.common.isNotEmpty == true
                      ? CachedNetworkImage(
                          imageUrl: subject.images!.common,
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
                child: SizedBox(
                  height: coverHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题
                      Text(
                        subject.displayName,
                        style: TextStyle(
                          fontSize: 14 * densityScale,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4 * densityScale),
                      // 英文名
                      if (subject.name.isNotEmpty &&
                          subject.name != subject.nameCn)
                        Text(
                          subject.name,
                          style: TextStyle(
                            fontSize: 11 * densityScale,
                            color: Colors.grey[500],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (subject.shortSummary.isNotEmpty) ...[
                        SizedBox(height: 4 * densityScale),
                        Text(
                          subject.shortSummary,
                          style: TextStyle(
                            fontSize: 11 * densityScale,
                            color: Colors.grey[500],
                            height: 1.2,
                          ),
                          maxLines:
                              subject.name.isNotEmpty &&
                                  subject.name != subject.nameCn
                              ? 1
                              : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (showSecondary) ...[
                        const Spacer(),
                        _buildBottomRow(context, colorScheme, densityScale),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomRow(
    BuildContext context,
    ColorScheme colorScheme,
    double densityScale,
  ) {
    return Row(
      children: [
        if (subject.score > 0) ...[
          Icon(Icons.star_rounded, size: 14, color: Colors.amber[700]),
          const SizedBox(width: 2),
          Text(
            subject.score.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 12 * densityScale,
              fontWeight: FontWeight.w600,
              color: Colors.amber[800],
            ),
          ),
          const SizedBox(width: 10),
        ],
        if (subject.rank > 0) ...[
          Text(
            '#${subject.rank}',
            style: TextStyle(
              fontSize: 11 * densityScale,
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
        ],
        const Spacer(),
        if (subject.collectionTotal > 0) ...[
          Icon(Icons.people_outline, size: 13, color: Colors.grey[500]),
          const SizedBox(width: 2),
          Text(
            '${subject.collectionTotal}',
            style: TextStyle(
              fontSize: 11 * densityScale,
              color: Colors.grey[500],
            ),
          ),
        ],
      ],
    );
  }

  bool get _hasSecondaryInfo =>
      subject.score > 0 || subject.rank > 0 || subject.collectionTotal > 0;
}
