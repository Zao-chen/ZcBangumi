import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants.dart';
import '../models/collection.dart';
import '../models/user.dart';
import '../pages/subject_page.dart';
import '../providers/auth_provider.dart';
import '../providers/collection_provider.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';

/// 排序方式
enum _SortMode {
  updatedAt('最近操作'),
  rateDesc('评分从高到低'),
  rateAsc('评分从低到高'),
  nameAsc('名称排序');

  final String label;
  const _SortMode(this.label);
}

/// 收藏条目卡片（从 collection_list_page.dart 移植）
class _CollectionItemCard extends StatelessWidget {
  final UserCollection collection;
  final int subjectType;

  const _CollectionItemCard({
    required this.collection,
    required this.subjectType,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subject = collection.subject;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openSubjectPage(context, collection.subjectId),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 56,
                  height: 80,
                  child: subject?.images?.common.isNotEmpty == true
                      ? CachedNetworkImage(
                          imageUrl: subject!.images!.common,
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
              // 信息
              Expanded(
                child: SizedBox(
                  height: 80,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题
                      Text(
                        subject?.displayName ?? 'ID: ${collection.subjectId}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      // 底部信息行
                      _buildBottomRow(context, colorScheme),
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

  Widget _buildBottomRow(BuildContext context, ColorScheme colorScheme) {
    final subject = collection.subject;

    return Row(
      children: [
        // 用户评分
        if (collection.rate > 0) ...[
          Icon(Icons.star_rounded, size: 14, color: Colors.amber[700]),
          const SizedBox(width: 2),
          Text(
            '${collection.rate}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.amber[800],
            ),
          ),
          const SizedBox(width: 10),
        ],
        // Bangumi 评分
        if (subject != null && subject.score > 0) ...[
          Icon(Icons.people_outline, size: 13, color: Colors.grey[500]),
          const SizedBox(width: 2),
          Text(
            subject.score.toStringAsFixed(1),
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          const SizedBox(width: 10),
        ],
        // 排名
        if (subject != null && subject.rank > 0) ...[
          Text(
            '#${subject.rank}',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
        ],
        const Spacer(),
        // 进度 (动画/书籍)
        if (collection.epStatus > 0) ...[
          Text(
            'EP ${collection.epStatus}',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          if (subject != null && subject.eps > 0)
            Text(
              ' / ${subject.eps}',
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
        ],
        // 更新日期
        if (collection.epStatus == 0) ...[
          Text(
            _formatDate(collection.updatedAt),
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  void _openSubjectPage(BuildContext context, int subjectId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SubjectPage(subjectId: subjectId)),
    );
  }
}

/// 我的页面 - 登录/用户信息/收藏
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        centerTitle: false,
        actions: [
          if (auth.isLoggedIn)
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: '退出登录',
              onPressed: () => _confirmLogout(context, auth),
            ),
        ],
      ),
      body: auth.isLoggedIn
          ? _ProfileContent(user: auth.user!)
          : const _LoginView(),
    );
  }

  Future<void> _confirmLogout(BuildContext context, AuthProvider auth) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<CollectionProvider>().clearAll();
      await auth.logout();
    }
  }
}

// ==================== 登录视图 ====================

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final _tokenController = TextEditingController();
  bool _obscureToken = true;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.movie_filter_rounded,
                  size: 40,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '登录到 Bangumi',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '请使用 Access Token 登录',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
              const SizedBox(height: 32),

              // Token 输入框
              TextField(
                controller: _tokenController,
                obscureText: _obscureToken,
                decoration: InputDecoration(
                  labelText: 'Access Token',
                  hintText: '粘贴你的 Access Token',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.key),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureToken
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscureToken = !_obscureToken),
                  ),
                ),
                onSubmitted: (_) => _login(auth),
              ),
              const SizedBox(height: 16),

              // 登录按钮
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: auth.loading ? null : () => _login(auth),
                  child: auth.loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('登录', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),

              // 获取 Token 链接
              TextButton.icon(
                onPressed: () => _openTokenPage(),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('获取 Access Token'),
              ),

              // 错误信息
              if (auth.error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 20,
                        color: colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          auth.error!,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _login(AuthProvider auth) async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入 Access Token')));
      return;
    }
    final success = await auth.loginWithToken(token);
    if (success && mounted) {
      _tokenController.clear();
    }
  }

  Future<void> _openTokenPage() async {
    final uri = Uri.parse(BgmConst.tokenUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ==================== 用户资料内容 ====================

class _ProfileContent extends StatefulWidget {
  final BangumiUser user;
  const _ProfileContent({required this.user});

  @override
  State<_ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends State<_ProfileContent> {
  // 收藏列表筛选与数据
  static const _subjectTypes = [
    (type: BgmConst.subjectAnime, label: '动画', icon: Icons.movie_outlined),
    (
      type: BgmConst.subjectGame,
      label: '游戏',
      icon: Icons.sports_esports_outlined,
    ),
    (type: BgmConst.subjectBook, label: '书籍', icon: Icons.menu_book_outlined),
    (type: BgmConst.subjectMusic, label: '音乐', icon: Icons.music_note_outlined),
    (type: BgmConst.subjectReal, label: '三次元', icon: Icons.live_tv_outlined),
  ];
  static const _collectionTypes = [
    BgmConst.collectionDoing,
    BgmConst.collectionWish,
    BgmConst.collectionDone,
    BgmConst.collectionOnHold,
    BgmConst.collectionDropped,
  ];
  int _subjectType = BgmConst.subjectAnime;
  int _collectionType = BgmConst.collectionDoing;
  _SortMode _sortMode = _SortMode.updatedAt;
  List<UserCollection> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _total = 0;
  int _offset = 0;
  static const _pageSize = 30;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String get _cacheKey =>
      'collection_list_${widget.user.username}_${_subjectType}_$_collectionType';

  Future<void> _loadData({bool refresh = true}) async {
    final storage = context.read<StorageService>();
    if (refresh) {
      // 先从缓存恢复
      if (_items.isEmpty) {
        final cached = storage.getCache(_cacheKey);
        if (cached is List && cached.isNotEmpty) {
          try {
            _items = cached
                .map((e) => UserCollection.fromJson(e as Map<String, dynamic>))
                .toList();
          } catch (_) {}
        }
      }
      setState(() {
        _loading = _items.isEmpty;
        _error = null;
        _offset = 0;
      });
    }

    final api = context.read<ApiClient>();
    try {
      final result = await api.getUserCollections(
        username: widget.user.username,
        subjectType: _subjectType,
        collectionType: _collectionType,
        limit: _pageSize,
        offset: _offset,
      );
      setState(() {
        if (refresh) {
          _items = result.data;
        } else {
          _items = [..._items, ...result.data];
        }
        _total = result.total;
        _error = null;
      });
      if (refresh) {
        storage.setCache(_cacheKey, _items.map((e) => e.toJson()).toList());
      }
    } catch (e) {
      if (_items.isEmpty) {
        setState(() => _error = '加载失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _items.length >= _total) return;
    setState(() => _loadingMore = true);
    _offset = _items.length;
    await _loadData(refresh: false);
  }

  void _switchSubjectType(int type) {
    if (_subjectType == type) return;
    setState(() {
      _subjectType = type;
      _items = [];
      _total = 0;
    });
    _loadData();
  }

  void _switchCollectionType(int type) {
    if (_collectionType == type) return;
    setState(() {
      _collectionType = type;
      _items = [];
      _total = 0;
    });
    _loadData();
  }

  void _switchSort(_SortMode mode) {
    if (_sortMode == mode) return;
    setState(() => _sortMode = mode);
  }

  List<UserCollection> get _sortedItems {
    final list = List<UserCollection>.from(_items);
    switch (_sortMode) {
      case _SortMode.updatedAt:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      case _SortMode.rateDesc:
        list.sort((a, b) {
          final cmp = b.rate.compareTo(a.rate);
          return cmp != 0 ? cmp : b.updatedAt.compareTo(a.updatedAt);
        });
        break;
      case _SortMode.rateAsc:
        list.sort((a, b) {
          final cmp = a.rate.compareTo(b.rate);
          return cmp != 0 ? cmp : b.updatedAt.compareTo(a.updatedAt);
        });
        break;
      case _SortMode.nameAsc:
        list.sort((a, b) {
          final nameA = a.subject?.displayName ?? '';
          final nameB = b.subject?.displayName ?? '';
          return nameA.compareTo(nameB);
        });
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () => _loadData(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 用户卡片
          _buildUserCard(colorScheme),
          const SizedBox(height: 20),
          // 收藏列表筛选栏
          Text(
            '我的收藏',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          _buildSubjectTypeBar(colorScheme),
          _buildCollectionTypeBar(colorScheme),
          _buildSortBar(colorScheme),
          const SizedBox(height: 8),
          _buildList(colorScheme),
        ],
      ),
    );
  }

  /// 用户信息卡片
  Widget _buildUserCard(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // 头像
            ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: SizedBox(
                width: 72,
                height: 72,
                child: widget.user.avatar.large.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: widget.user.avatar.large,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.person, size: 36),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.person, size: 36),
                        ),
                      )
                    : Container(
                        color: colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.person, size: 36),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            // 用户信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.user.nickname,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${widget.user.username}',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                  if (widget.user.sign.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.user.sign,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // 打开网页版
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 20),
              tooltip: '在浏览器中查看',
              onPressed: () async {
                final uri = Uri.parse(
                  '${BgmConst.webBaseUrl}/user/${widget.user.username}',
                );
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 条目类型横向切换栏
  Widget _buildSubjectTypeBar(ColorScheme colorScheme) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
        itemCount: _subjectTypes.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final t = _subjectTypes[i];
          final selected = _subjectType == t.type;
          return ChoiceChip(
            label: Text(t.label),
            avatar: Icon(t.icon, size: 16),
            selected: selected,
            onSelected: (_) => _switchSubjectType(t.type),
            visualDensity: VisualDensity.compact,
            showCheckmark: false,
          );
        },
      ),
    );
  }

  /// 收藏类型横向切换栏
  Widget _buildCollectionTypeBar(ColorScheme colorScheme) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        itemCount: _collectionTypes.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final ct = _collectionTypes[i];
          final label = BgmConst.collectionLabel(ct, subjectType: _subjectType);
          final selected = _collectionType == ct;
          return FilterChip(
            label: Text(label, style: const TextStyle(fontSize: 13)),
            selected: selected,
            onSelected: (_) => _switchCollectionType(ct),
            visualDensity: VisualDensity.compact,
            showCheckmark: false,
          );
        },
      ),
    );
  }

  /// 排序栏
  Widget _buildSortBar(ColorScheme colorScheme) {
    return Row(
      children: [
        const Spacer(),
        PopupMenuButton<_SortMode>(
          icon: const Icon(Icons.sort),
          tooltip: '排序',
          onSelected: _switchSort,
          itemBuilder: (ctx) => _SortMode.values
              .map(
                (m) => PopupMenuItem(
                  value: m,
                  child: Row(
                    children: [
                      if (_sortMode == m)
                        Icon(Icons.check, size: 18, color: colorScheme.primary)
                      else
                        const SizedBox(width: 18),
                      const SizedBox(width: 8),
                      Text(m.label),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  /// 收藏列表
  Widget _buildList(ColorScheme colorScheme) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => _loadData(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              '暂无收藏',
              style: TextStyle(fontSize: 15, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    final sorted = _sortedItems;
    final hasMore = _items.length < _total;

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: sorted.length + (hasMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == sorted.length) {
          // 加载更多
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: _loadingMore
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(onPressed: _loadMore, child: const Text('加载更多')),
            ),
          );
        }
        return _CollectionItemCard(
          collection: sorted[i],
          subjectType: _subjectType,
        );
      },
    );
  }
}
