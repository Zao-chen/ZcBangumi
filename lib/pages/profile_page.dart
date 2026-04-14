import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants.dart';
import '../models/collection.dart';
import '../models/user.dart';
import '../pages/settings_page.dart';
import '../pages/subject_page.dart';
import '../providers/auth_provider.dart';
import '../providers/app_state_provider.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../widgets/copyable_text.dart';

enum _SortMode {
  updatedAt('最近操作'),
  rateDesc('评分从高到低'),
  rateAsc('评分从低到高'),
  nameAsc('名称排序');

  final String label;
  const _SortMode(this.label);
}

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
    final appState = context.watch<AppStateProvider>();
    final subject = collection.subject;
    final densityScale = switch (appState.listDensityMode) {
      0 => 0.88,
      2 => 1.12,
      _ => 1.0,
    };
    final cardPadding = 10.0 * densityScale;
    final coverWidth = 56.0 * densityScale;
    final coverHeight = 80.0 * densityScale;
    final coverRadius = appState.coverCornerRadius;
    final showSecondary = appState.showSecondaryInfo;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openSubjectPage(context, collection.subjectId),
        child: Padding(
          padding: EdgeInsets.all(cardPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(coverRadius),
                child: SizedBox(
                  width: coverWidth,
                  height: coverHeight,
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
              Expanded(
                child: SizedBox(
                  height: coverHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject?.displayName ?? 'ID: ${collection.subjectId}',
                        style: TextStyle(
                          fontSize: 14 * densityScale,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4 * densityScale),
                      if (collection.epStatus > 0)
                        Text(
                          'EP ${collection.epStatus}${subject != null && subject.eps > 0 ? ' / ${subject.eps}' : ''}',
                          style: TextStyle(
                            fontSize: 11 * densityScale,
                            color: Colors.grey[500],
                          ),
                        ),
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
    final subject = collection.subject;

    return Row(
      children: [
        if (subject != null && subject.score > 0) ...[
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
        if (collection.rate > 0) ...[
          Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.person, size: 12, color: Colors.blue[600]),
              Positioned(
                right: -2,
                bottom: 0,
                child: Icon(
                  Icons.star_rounded,
                  size: 8,
                  color: Colors.amber[700],
                ),
              ),
            ],
          ),
          const SizedBox(width: 2),
          Text(
            '${collection.rate}',
            style: TextStyle(
              fontSize: 11 * densityScale,
              color: Colors.blue[600],
            ),
          ),
          const SizedBox(width: 10),
        ],
        if (subject != null && subject.rank > 0) ...[
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
        Text(
          _formatDate(collection.updatedAt),
          style: TextStyle(
            fontSize: 11 * densityScale,
            color: Colors.grey[400],
          ),
        ),
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

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final appState = context.watch<AppStateProvider>();
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // 初始化中显示骨架屏
    final isInitializing = !auth.initialized;
    final bodyWidget = isInitializing
        ? _buildProfileInitializingContent(
            selectedSubjectType: appState.profileSubjectType,
            selectedCollectionType: appState.profileCollectionType,
            isLandscape: isLandscape,
          )
        : auth.isLoggedIn
        ? _ProfileContent(
            user: auth.user!,
            collectionTitle: '我的收藏',
            persistViewState: true,
          )
        : const _LoginView();

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
            },
          ),
        ],
      ),
      body: bodyWidget,
    );
  }

  /// 我的页面初始化布局：固定元素保持真实位置，仅列表内容骨架化
  Widget _buildProfileInitializingContent({
    required int selectedSubjectType,
    required int selectedCollectionType,
    required bool isLandscape,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!isLandscape) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildInitializingUserCard(colorScheme),
          const SizedBox(height: 20),
          Text(
            '我的收藏',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          _buildInitializingSubjectTypeBar(selectedSubjectType),
          _buildInitializingCollectionTypeBar(
            selectedSubjectType,
            selectedCollectionType,
          ),
          const SizedBox(height: 8),
          ..._buildSkeletonItems(colorScheme),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInitializingUserCard(colorScheme),
              const SizedBox(height: 20),
              Text(
                '我的收藏',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              SafeArea(
                top: false,
                right: false,
                child: NavigationRail(
                  selectedIndex: _initializingSelectedSubjectIndex(
                    selectedSubjectType,
                  ),
                  onDestinationSelected: (_) {},
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: colorScheme.surface,
                  indicatorColor: colorScheme.primaryContainer,
                  destinations: _initializingSubjectTypes
                      .map(
                        (t) => NavigationRailDestination(
                          icon: Icon(t.icon),
                          label: Text(t.label),
                        ),
                      )
                      .toList(),
                ),
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    _buildInitializingCollectionTypeBar(
                      selectedSubjectType,
                      selectedCollectionType,
                    ),
                    const SizedBox(height: 8),
                    ..._buildSkeletonItems(colorScheme),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static const _initializingSubjectTypes = [
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

  Widget _buildInitializingUserCard(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 120,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 80,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _initializingSelectedSubjectIndex(int selectedSubjectType) {
    final index = _initializingSubjectTypes.indexWhere(
      (t) => t.type == selectedSubjectType,
    );
    return index >= 0 ? index : 0;
  }

  Widget _buildInitializingSubjectTypeBar(int selectedSubjectType) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
        itemCount: _initializingSubjectTypes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final t = _initializingSubjectTypes[index];
          return ChoiceChip(
            label: Text(t.label),
            avatar: Icon(t.icon, size: 16),
            selected: t.type == selectedSubjectType,
            onSelected: (_) {},
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }

  Widget _buildInitializingCollectionTypeBar(
    int selectedSubjectType,
    int selectedCollectionType,
  ) {
    const collectionTypes = [
      BgmConst.collectionWish,
      BgmConst.collectionOnHold,
      BgmConst.collectionDoing,
      BgmConst.collectionDone,
      BgmConst.collectionDropped,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 0),
                itemCount: collectionTypes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final ct = collectionTypes[index];
                  return FilterChip(
                    label: Text(
                      BgmConst.collectionLabel(
                        ct,
                        subjectType: selectedSubjectType,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    selected: ct == selectedCollectionType,
                    onSelected: (_) {},
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.sort, size: 20),
        ],
      ),
    );
  }

  /// 生成骨架屏的条目列表
  List<Widget> _buildSkeletonItems(ColorScheme colorScheme) {
    return List.generate(3, (index) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 5),
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 图片骨架
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 56,
                  height: 80,
                  color: colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(width: 12),
              // 信息骨架
              Expanded(
                child: SizedBox(
                  height: 80,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 150,
                        height: 12,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 100,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 80,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class OtherUserProfilePage extends StatefulWidget {
  final String username;
  final String? displayName;

  const OtherUserProfilePage({
    super.key,
    required this.username,
    this.displayName,
  });

  @override
  State<OtherUserProfilePage> createState() => _OtherUserProfilePageState();
}

class _OtherUserProfilePageState extends State<OtherUserProfilePage> {
  BangumiUser? _user;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<ApiClient>();
      final user = await api.getUser(widget.username);
      if (!mounted) return;
      setState(() {
        _user = user;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载用户信息失败: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.displayName?.trim().isNotEmpty == true
        ? widget.displayName!.trim()
        : '@${widget.username}';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton.tonal(onPressed: _loadUser, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    final user = _user;
    if (user == null) {
      return const SizedBox.shrink();
    }
    final title = user.nickname.trim().isNotEmpty
        ? '${user.nickname}的收藏'
        : 'TA的收藏';
    return _ProfileContent(
      user: user,
      collectionTitle: title,
      persistViewState: false,
    );
  }
}

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
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/images/bangumi_icon.png',
                    fit: BoxFit.contain,
                  ),
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

              TextButton.icon(
                onPressed: () => _openTokenPage(),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('获取 Access Token'),
              ),

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

class _ProfileContent extends StatefulWidget {
  final BangumiUser user;
  final String collectionTitle;
  final bool persistViewState;

  const _ProfileContent({
    required this.user,
    this.collectionTitle = '我的收藏',
    this.persistViewState = true,
  });

  @override
  State<_ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends State<_ProfileContent> {
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
    BgmConst.collectionWish,
    BgmConst.collectionOnHold,
    BgmConst.collectionDoing,
    BgmConst.collectionDone,
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
    final appState = context.read<AppStateProvider>();
    _subjectType = appState.profileSubjectType;
    _collectionType = appState.profileCollectionType;
    _sortMode = _SortMode.values[appState.profileSortMode];
    _loadData();
  }

  String get _cacheKey =>
      'collection_list_${widget.user.username}_${_subjectType}_$_collectionType';

  Future<void> _loadData({bool refresh = true}) async {
    final storage = context.read<StorageService>();
    if (refresh) {
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
    if (widget.persistViewState) {
      context.read<AppStateProvider>().setProfileSubjectType(type);
    }
    _loadData();
  }

  void _switchCollectionType(int type) {
    if (_collectionType == type) return;
    setState(() {
      _collectionType = type;
      _items = [];
      _total = 0;
    });
    if (widget.persistViewState) {
      context.read<AppStateProvider>().setProfileCollectionType(type);
    }
    _loadData();
  }

  void _switchSort(_SortMode mode) {
    if (_sortMode == mode) return;
    setState(() => _sortMode = mode);
    if (widget.persistViewState) {
      context.read<AppStateProvider>().setProfileSortMode(mode.index);
    }

    if (mode != _SortMode.updatedAt && _items.length < _total) {
      _loadAllRemaining();
    }
  }

  Future<void> _loadAllRemaining() async {
    if (_loadingMore || _items.length >= _total) return;
    setState(() => _loadingMore = true);

    final api = context.read<ApiClient>();
    try {
      while (_items.length < _total) {
        final offset = _items.length;
        final result = await api.getUserCollections(
          username: widget.user.username,
          subjectType: _subjectType,
          collectionType: _collectionType,
          limit: _pageSize,
          offset: offset,
        );

        if (result.data.isEmpty) break;

        setState(() {
          _items = [..._items, ...result.data];
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
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
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    if (!isLandscape) {
      return _buildCollectionsContent(
        colorScheme,
        showSubjectTypeBar: true,
        includeHeader: true,
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildUserCard(colorScheme),
              const SizedBox(height: 20),
              Text(
                widget.collectionTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              SafeArea(
                top: false,
                right: false,
                child: NavigationRail(
                  selectedIndex: _selectedSubjectIndex,
                  onDestinationSelected: (index) {
                    _switchSubjectType(_subjectTypes[index].type);
                  },
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: colorScheme.surface,
                  indicatorColor: colorScheme.primaryContainer,
                  destinations: _subjectTypes
                      .map(
                        (t) => NavigationRailDestination(
                          icon: Icon(t.icon),
                          label: Text(t.label),
                        ),
                      )
                      .toList(),
                ),
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                child: _buildCollectionsContent(
                  colorScheme,
                  showSubjectTypeBar: false,
                  includeHeader: false,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  int get _selectedSubjectIndex {
    final index = _subjectTypes.indexWhere((t) => t.type == _subjectType);
    return index >= 0 ? index : 0;
  }

  Widget _buildCollectionsContent(
    ColorScheme colorScheme, {
    required bool showSubjectTypeBar,
    required bool includeHeader,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return RefreshIndicator(
      onRefresh: () => _loadData(),
      child: ListView(
        padding: padding,
        children: [
          if (includeHeader) ...[
            _buildUserCard(colorScheme),
            const SizedBox(height: 20),
            Text(
              widget.collectionTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (showSubjectTypeBar) _buildSubjectTypeBar(colorScheme),
          _buildCollectionTypeBar(colorScheme),
          const SizedBox(height: 8),
          _buildList(colorScheme),
        ],
      ),
    );
  }

  Widget _buildUserCard(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 48,
                height: 48,
                child: widget.user.avatar.large.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: widget.user.avatar.large,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.person, size: 24),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.person, size: 24),
                        ),
                      )
                    : Container(
                        color: colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.person, size: 24),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShortCopyableText(
                    widget.user.nickname,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  ShortCopyableText(
                    '@${widget.user.username}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 18),
              tooltip: '在浏览器中查看',
              onPressed: () async {
                final uri = Uri.parse(
                  '${BgmConst.webBaseUrl}/user/${widget.user.username}',
                );
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              padding: const EdgeInsets.all(8),
            ),
          ],
        ),
      ),
    );
  }

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

  Widget _buildCollectionTypeBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 0),
                itemCount: _collectionTypes.length,
                separatorBuilder: (context, index) => const SizedBox(width: 6),
                itemBuilder: (ctx, i) {
                  final ct = _collectionTypes[i];
                  final label = BgmConst.collectionLabel(
                    ct,
                    subjectType: _subjectType,
                  );
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
            ),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<_SortMode>(
            icon: const Icon(Icons.sort, size: 20),
            tooltip: '排序',
            onSelected: _switchSort,
            itemBuilder: (ctx) => _SortMode.values
                .map(
                  (m) => PopupMenuItem(
                    value: m,
                    child: Row(
                      children: [
                        if (_sortMode == m)
                          Icon(
                            Icons.check,
                            size: 18,
                            color: colorScheme.primary,
                          )
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
      ),
    );
  }

  Widget _buildList(ColorScheme colorScheme) {
    if (_loading && _items.isEmpty) {
      return _buildCollectionSkeletonList(colorScheme);
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
          if (!_loadingMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _loadMore();
            });
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
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

  Widget _buildCollectionSkeletonList(ColorScheme colorScheme) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 0),
      itemBuilder: (context, index) =>
          _buildCollectionSkeletonCard(colorScheme),
    );
  }

  Widget _buildCollectionSkeletonCard(ColorScheme colorScheme) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 80,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 150,
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
                    width: 180,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: List.generate(
                      3,
                      (_) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Container(
                          width: 46,
                          height: 18,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                      ),
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
}
