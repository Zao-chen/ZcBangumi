import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../constants.dart';
import '../models/calendar.dart';
import '../models/character.dart';
import '../models/collection.dart';
import '../models/comment.dart';
import '../models/episode.dart';
import '../models/rakuen_topic.dart';
import '../models/rakuen_topic_detail.dart';
import '../models/subject.dart';
import '../models/timeline.dart';
import '../models/user.dart';

/// Bangumi API 客户端
class ApiClient {
  late final Dio _dio;
  String? _accessToken;

  /// 公开 Dio 实例供其他服务使用
  Dio get dio => _dio;

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: BgmConst.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'User-Agent': BgmConst.userAgent,
          'Accept': 'application/json',
        },
      ),
    );

    // 添加日志拦截器（仅在调试模式）
    if (kDebugMode) {
      _dio.interceptors.add(LoggingInterceptor());
    }
  }

  /// 设置 Access Token
  void setToken(String? token) {
    _accessToken = token;
    if (token != null && token.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _dio.options.headers.remove('Authorization');
    }
  }

  bool get hasToken => _accessToken != null && _accessToken!.isNotEmpty;

  // ========== 用户 ==========

  /// 获取当前登录用户信息
  Future<BangumiUser> getMe() async {
    final resp = await _dio.get('/v0/me');
    return BangumiUser.fromJson(resp.data as Map<String, dynamic>);
  }

  /// 获取指定用户信息
  Future<BangumiUser> getUser(String username) async {
    final resp = await _dio.get('/v0/users/$username');
    return BangumiUser.fromJson(resp.data as Map<String, dynamic>);
  }

  // ========== 每日放送 ==========

  /// 获取每日放送列表
  Future<List<CalendarDay>> getCalendar() async {
    final resp = await _dio.get('/calendar');
    final list = resp.data as List<dynamic>;
    return list
        .map((e) => CalendarDay.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ========== 条目 ==========

  /// 搜索条目
  /// [keyword] 搜索关键词
  /// [type] 条目类型，不指定则返回所有类型
  /// [limit] 返回数量限制
  Future<List<SlimSubject>> searchSubjects({
    required String keyword,
    int? type,
    int limit = 25,
  }) async {
    try {
      // 使用 /search/subject/{keyword} 端点
      final params = <String, dynamic>{'max_results': limit};
      if (type != null) params['type'] = type;

      final resp = await _dio.get(
        '/search/subject/${Uri.encodeComponent(keyword)}',
        queryParameters: params,
      );

      final results = <SlimSubject>[];

      // 响应格式：{ results: n, list: [...] }
      if (resp.data is Map) {
        final data = resp.data as Map<String, dynamic>;
        if (data['list'] is List) {
          for (final item in data['list'] as List<dynamic>) {
            if (item is Map<String, dynamic>) {
              try {
                results.add(SlimSubject.fromJson(item));
              } catch (e) {
                if (kDebugMode) {
                  print('解析搜索结果失败: $e, 数据: $item');
                }
                continue;
              }
            }
          }
        }
      } else if (resp.data is List) {
        // 兼容直接返回列表的情况
        for (final item in resp.data as List<dynamic>) {
          if (item is Map<String, dynamic>) {
            try {
              results.add(SlimSubject.fromJson(item));
            } catch (e) {
              if (kDebugMode) {
                print('解析搜索结果失败: $e, 数据: $item');
              }
              continue;
            }
          }
        }
      }

      if (kDebugMode) {
        print('搜索结果数量: ${results.length}');
      }

      return results;
    } catch (e) {
      if (kDebugMode) {
        print('搜索条目失败: $e');
      }
      // 如果搜索失败，返回空列表而不是抛出异常
      return [];
    }
  }

  /// 获取条目详情
  Future<Subject> getSubject(int subjectId) async {
    final resp = await _dio.get('/v0/subjects/$subjectId');
    return Subject.fromJson(resp.data as Map<String, dynamic>);
  }

  /// 获取条目角色列表
  Future<List<Character>> getSubjectCharacters(int subjectId) async {
    final resp = await _dio.get('/v0/subjects/$subjectId/characters');
    final list = resp.data as List<dynamic>;
    return list
        .map((e) => Character.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取条目关联条目
  Future<List<RelatedSubject>> getSubjectRelations(int subjectId) async {
    final resp = await _dio.get('/v0/subjects/$subjectId/subjects');
    final list = resp.data as List<dynamic>;
    return list
        .map((e) => RelatedSubject.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取单个角色详情
  Future<Character> getCharacter(int characterId) async {
    final resp = await _dio.get('/v0/characters/$characterId');
    return Character.fromJson(resp.data as Map<String, dynamic>);
  }

  // ========== 吐槽/评论 ==========
  // 通过网页爬取实现（API 不提供）

  /// 获取条目吐槽列表（通过网页爬取）
  Future<PagedResult<Comment>> getSubjectComments({
    required int subjectId,
    int limit = 30,
    int offset = 0,
  }) async {
    try {
      // 从网页获取条目吐槽
      final resp = await _webDio.get('/subject/$subjectId');
      final html = resp.data as String;
      final comments = _parseCommentsFromHtml(html);

      // 分页处理
      final start = offset;
      final end = (offset + limit).clamp(0, comments.length);
      final List<Comment> paginatedComments = start < comments.length
          ? comments.sublist(start, end)
          : [];

      return PagedResult<Comment>(
        total: comments.length,
        limit: limit,
        offset: offset,
        data: paginatedComments,
      );
    } catch (e) {
      // 获取失败返回空列表
      return PagedResult<Comment>(
        total: 0,
        limit: limit,
        offset: offset,
        data: [],
      );
    }
  }

  /// 发布条目吐槽/评论（暂未实现）
  Future<Comment?> createSubjectComment({
    required int subjectId,
    required String content,
    int rating = 0,
    int spoiler = 0,
  }) async {
    // 暂时不支持发布吐槽
    return null;
  }

  /// 从 HTML 中解析吐槽/评论
  static List<Comment> _parseCommentsFromHtml(String html) {
    final comments = <Comment>[];

    try {
      // HTML 吐槽箱结构：<div id="comment_box">...</div>
      // 每条评论：<div class="item clearit" data-item-user="...">
      //   头像：<span style="background-image:url('avatar_url')"></span>
      //   用户名：<a href="/user/..." class="l">USERNAME</a>
      //   评分：<span class="starlight starsN"></span> (N = 1-10)
      //   状态：<small class="grey"> 看过/在看 </small>
      //   时间：<small class="grey">@ 时间</small>
      //   内容：<p class="comment">【评分】内容</p>

      // 找到吐槽箱区域
      final commentBoxStart = html.indexOf('id="comment_box"');
      if (commentBoxStart == -1) return [];

      // 找到下一个 subject_section 或页面结束
      final nextSectionStart = html.indexOf(
        'subject_section',
        commentBoxStart + 1,
      );
      final endIndex = nextSectionStart > 0 ? nextSectionStart : html.length;
      final commentBoxHtml = html.substring(commentBoxStart, endIndex);

      // 提取所有评论项
      // 每条评论以 <div class="item clearit" 开始
      final itemPattern = RegExp(
        r'<div class="item clearit".*?(?=<div class="item clearit"|$)',
        dotAll: true,
      );

      int commentId = 1;
      for (final itemMatch in itemPattern.allMatches(commentBoxHtml)) {
        try {
          final itemHtml = itemMatch.group(0) ?? '';

          // 提取头像URL：<span style="background-image:url('...')"></span>
          String avatarUrl = '';
          final avatarMatch = RegExp(
            r"background-image:url\('([^']+)'\)",
          ).firstMatch(itemHtml);
          if (avatarMatch != null) {
            avatarUrl = avatarMatch.group(1)?.trim() ?? '';
            // 补充协议，如果是相对路径
            if (avatarUrl.startsWith('//')) {
              avatarUrl = 'https:$avatarUrl';
            }
          }

          // 提取用户名：<a href="/user/..." class="l">USERNAME</a>
          final userNameMatch = RegExp(
            r'<a href="/user/[^"]*" class="l">([^<]+)</a>',
          ).firstMatch(itemHtml);
          final userName = userNameMatch?.group(1)?.trim() ?? '未知用户';

          // 提取评分：<span class="starlight starsN"></span>
          int rating = 0;
          final ratingMatch = RegExp(
            r'class="starlight stars(\d+)"',
          ).firstMatch(itemHtml);
          if (ratingMatch != null) {
            rating = int.tryParse(ratingMatch.group(1) ?? '0') ?? 0;
          }

          // 提取时间：<small class="grey">@ 时间</small>
          final timeMatch = RegExp(
            r'<small class="grey">\s*@\s*([^<]+)</small>',
          ).firstMatch(itemHtml);
          final timeStr = timeMatch?.group(1)?.trim() ?? '';

          // 提取内容：<p class="comment">【评分】内容</p>
          final contentMatch = RegExp(
            r'<p class="comment">([^<]*)</p>',
          ).firstMatch(itemHtml);
          var content = contentMatch?.group(1)?.trim() ?? '';

          // 从内容中提取评分（如果内容以【数字】开头）
          final contentRatingMatch = RegExp(
            r'【(\d+)[+-]*】',
          ).firstMatch(content);
          if (contentRatingMatch != null && rating == 0) {
            rating = int.tryParse(contentRatingMatch.group(1) ?? '0') ?? 0;
            content = content.replaceFirst(RegExp(r'【\d+[+-]*】'), '').trim();
          } else if (contentRatingMatch != null) {
            // 如果已经从星级提取了评分，还是要移除内容中的【】标记
            content = content.replaceFirst(RegExp(r'【\d+[+-]*】'), '').trim();
          }

          // 解析时间
          DateTime createdAt = DateTime.now();
          try {
            if (timeStr.isNotEmpty) {
              // 格式1：相对时间 "1d 17h ago" 或 "2小时前"
              if (timeStr.contains('ago') || timeStr.contains('前')) {
                createdAt = _parseRelativeTime(timeStr);
              }
              // 格式2：绝对时间 "2026-2-22 22:22"
              else if (timeStr.contains('-') && timeStr.contains(':')) {
                // 处理格式 "2026-2-22 22:22"
                final parts = timeStr.split(' ');
                if (parts.length >= 2) {
                  final dateStr = parts[0]; // "2026-2-22"
                  final timePartStr = parts[1]; // "22:22"
                  final dateParts = dateStr.split('-');
                  final timeParts = timePartStr.split(':');
                  if (dateParts.length == 3 && timeParts.length >= 2) {
                    try {
                      final year = int.parse(dateParts[0]);
                      final month = int.parse(dateParts[1]);
                      final day = int.parse(dateParts[2]);
                      final hour = int.parse(timeParts[0]);
                      final minute = int.parse(timeParts[1]);
                      createdAt = DateTime(year, month, day, hour, minute);
                    } catch (_) {
                      createdAt = DateTime.now();
                    }
                  }
                }
              }
              // 格式3：简单时间 "昨天 22:22" 等
              else {
                createdAt = DateTime.now();
              }
            }
          } catch (_) {
            createdAt = DateTime.now();
          }

          if (content.isNotEmpty && userName.isNotEmpty) {
            comments.add(
              Comment(
                id: commentId++,
                content: content,
                rating: rating,
                spoiler: 0,
                state: 0,
                createdAt: createdAt,
                updatedAt: createdAt,
                user: {
                  'username': userName,
                  'nickname': userName,
                  'avatar': avatarUrl,
                },
                usable: 1,
                replies: 0,
              ),
            );
          }
        } catch (e) {
          // 跳过解析失败的评论
          continue;
        }
      }
    } catch (e) {
      // HTML 解析失败，返回空列表
    }

    return comments;
  }

  /// 解析相对时间字符串，返回对应的 DateTime
  static DateTime _parseRelativeTime(String timeStr) {
    final now = DateTime.now();

    // 处理格式：1d 17h ago、2小时前等
    // 天数
    final dayMatch = RegExp(r'(\d+)\s*d').firstMatch(timeStr);
    final hourMatch = RegExp(r'(\d+)\s*h').firstMatch(timeStr);
    final minuteMatch = RegExp(r'(\d+)\s*m').firstMatch(timeStr);

    // 中文格式
    final dayChMatch = RegExp(r'(\d+)\s*天').firstMatch(timeStr);
    final hourChMatch = RegExp(r'(\d+)\s*小时').firstMatch(timeStr);
    final minuteChMatch = RegExp(r'(\d+)\s*分钟').firstMatch(timeStr);

    int days = 0;
    int hours = 0;
    int minutes = 0;

    if (dayMatch != null) {
      days = int.tryParse(dayMatch.group(1) ?? '0') ?? 0;
    }
    if (hourMatch != null) {
      hours = int.tryParse(hourMatch.group(1) ?? '0') ?? 0;
    }
    if (minuteMatch != null) {
      minutes = int.tryParse(minuteMatch.group(1) ?? '0') ?? 0;
    }

    if (dayChMatch != null) {
      days = int.tryParse(dayChMatch.group(1) ?? '0') ?? 0;
    }
    if (hourChMatch != null) {
      hours = int.tryParse(hourChMatch.group(1) ?? '0') ?? 0;
    }
    if (minuteChMatch != null) {
      minutes = int.tryParse(minuteChMatch.group(1) ?? '0') ?? 0;
    }

    return now.subtract(Duration(days: days, hours: hours, minutes: minutes));
  }

  // ========== 收藏 ==========

  /// 获取用户收藏列表
  /// [username] 用户名
  /// [subjectType] 条目类型 (1=书籍 2=动画 4=游戏)
  /// [collectionType] 收藏类型 (1=想看 2=看过 3=在看 4=搁置 5=抛弃)
  /// [limit] 每页数量 (默认30，最大50)
  /// [offset] 偏移量
  Future<PagedResult<UserCollection>> getUserCollections({
    required String username,
    int? subjectType,
    int? collectionType,
    int limit = 30,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (subjectType != null) params['subject_type'] = subjectType;
    if (collectionType != null) params['type'] = collectionType;

    final resp = await _dio.get(
      '/v0/users/$username/collections',
      queryParameters: params,
    );
    final data = resp.data as Map<String, dynamic>;
    return PagedResult<UserCollection>(
      total: data['total'] as int,
      limit: data['limit'] as int,
      offset: data['offset'] as int,
      data: (data['data'] as List<dynamic>)
          .map((e) => UserCollection.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  // ========== 章节进度 ==========

  /// 获取用户某条目的章节收藏信息
  Future<PagedResult<UserEpisodeCollection>> getUserEpisodeCollections({
    required int subjectId,
    int limit = 200,
    int offset = 0,
  }) async {
    final resp = await _dio.get(
      '/v0/users/-/collections/$subjectId/episodes',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    final data = resp.data as Map<String, dynamic>;
    return PagedResult<UserEpisodeCollection>(
      total: data['total'] as int,
      limit: data['limit'] as int,
      offset: data['offset'] as int,
      data: (data['data'] as List<dynamic>)
          .map((e) => UserEpisodeCollection.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 获取条目的章节列表（无需登录）
  Future<PagedResult<Episode>> getEpisodes({
    required int subjectId,
    int? type,
    int limit = 200,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{
      'subject_id': subjectId,
      'limit': limit,
      'offset': offset,
    };
    if (type != null) params['type'] = type;

    final resp = await _dio.get('/v0/episodes', queryParameters: params);
    final data = resp.data as Map<String, dynamic>;
    return PagedResult<Episode>(
      total: data['total'] as int,
      limit: data['limit'] as int,
      offset: data['offset'] as int,
      data: (data['data'] as List<dynamic>)
          .map((e) => Episode.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 批量更新章节收藏状态
  /// [subjectId] 条目 ID
  /// [episodeIds] 章节 ID 列表
  /// [type] 收藏类型 (1=想看 2=看过 3=抛弃)
  Future<void> patchEpisodeCollections({
    required int subjectId,
    required List<int> episodeIds,
    required int type,
  }) async {
    await _dio.patch(
      '/v0/users/-/collections/$subjectId/episodes',
      data: {'episode_id': episodeIds, 'type': type},
    );
  }

  /// 更新单个章节收藏状态
  Future<void> putEpisodeCollection({
    required int episodeId,
    required int type,
  }) async {
    await _dio.put(
      '/v0/users/-/collections/-/episodes/$episodeId',
      data: {'type': type},
    );
  }

  /// 修改条目收藏
  Future<void> patchCollection({
    required int subjectId,
    int? type,
    int? rate,
    int? epStatus,
    int? volStatus,
  }) async {
    final data = <String, dynamic>{};
    if (type != null) data['type'] = type;
    if (rate != null) data['rate'] = rate;
    if (epStatus != null) data['ep_status'] = epStatus;
    if (volStatus != null) data['vol_status'] = volStatus;

    await _dio.patch('/v0/users/-/collections/$subjectId', data: data);
  }

  // ========== 时间线 ==========

  /// 用于抓取 bgm.tv 网页的 Dio 实例（全站动态 HTML 解析）
  static final Dio _webDio = Dio(
    BaseOptions(
      baseUrl: BgmConst.webBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
      responseType: ResponseType.plain,
    ),
  );

  /// 用于调用 next.bgm.tv /p1/ 私有 JSON API 的 Dio 实例
  late final Dio _nextDio = Dio(
    BaseOptions(
      baseUrl: BgmConst.nextBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'User-Agent': BgmConst.userAgent, 'Accept': 'application/json'},
    ),
  );

  /// 获取全站时间线（通过解析 HTML，不带认证）
  Future<List<TimelineItem>> getTimeline({int page = 1}) async {
    final resp = await _webDio.get(
      '/timeline',
      queryParameters: {'type': 'all', 'page': page},
    );
    return _parseTimelineHtml(resp.data as String);
  }

  /// 获取好友时间线（通过 next.bgm.tv /p1/timeline JSON API）
  /// 使用 mode=friends 参数 + Bearer Token 认证区分好友/全站动态
  /// [limit] 每次获取条数，默认 20
  /// [until] 游标分页：传入上一页最后一条的 createdAt 时间戳
  Future<List<TimelineItem>> getFriendTimeline({
    int limit = 20,
    int? until,
  }) async {
    if (_accessToken == null || _accessToken!.isEmpty) {
      return [];
    }
    final params = <String, dynamic>{'mode': 'friends', 'limit': limit};
    if (until != null) params['until'] = until;

    final resp = await _nextDio.get(
      '/p1/timeline',
      queryParameters: params,
      options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
    );

    final list = resp.data as List<dynamic>;
    return TimelineItem.fromApiJsonList(list);
  }

  /// 获取指定用户的时间线（通过 next.bgm.tv /p1/users/{username}/timeline JSON API）
  /// [username] 用户名
  /// [limit] 每次获取条数，默认 20
  /// [until] 游标分页：传入上一页最后一条的 createdAt 时间戳
  /// [fallbackUser] 当 API 返回的 user 为 null 时使用的回退用户信息
  Future<List<TimelineItem>> getUserTimeline({
    required String username,
    int limit = 20,
    int? until,
    Map<String, dynamic>? fallbackUser,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (until != null) params['until'] = until;

    final options = _accessToken != null && _accessToken!.isNotEmpty
        ? Options(headers: {'Authorization': 'Bearer $_accessToken'})
        : null;

    final resp = await _nextDio.get(
      '/p1/users/$username/timeline',
      queryParameters: params,
      options: options,
    );

    final list = resp.data as List<dynamic>;
    return TimelineItem.fromApiJsonList(list, fallbackUser: fallbackUser);
  }

  /// 获取超展开主题列表（通过网页 HTML 解析）
  Future<List<RakuenTopic>> getRakuenTopics({
    String? type,
    String? filter,
    int page = 1,
  }) async {
    final params = <String, dynamic>{'page': page};
    if (type != null && type.isNotEmpty) params['type'] = type;
    if (filter != null && filter.isNotEmpty) params['filter'] = filter;

    final resp = await _webDio.get(
      '/rakuen/topiclist',
      queryParameters: params,
    );
    return _parseRakuenTopicsHtml(resp.data as String);
  }

  Future<RakuenTopicDetail> getRakuenTopicDetail({
    required String topicUrl,
  }) async {
    final uri = Uri.parse(topicUrl);
    final path = uri.path.isEmpty ? topicUrl : uri.path;
    final resp = await _webDio.get(
      path,
      queryParameters: uri.queryParameters.isEmpty ? null : uri.queryParameters,
    );
    return _parseRakuenTopicDetailHtml(
      html: resp.data as String,
      topicUrl: _normalizeWebUrl(topicUrl),
    );
  }

  /// 解析时间线 HTML
  static List<TimelineItem> _parseTimelineHtml(String html) {
    final items = <TimelineItem>[];

    // 匹配每个 tml_item
    final itemRegex = RegExp(
      r'<li\s+id="tml_\d+"[^>]*class="[^"]*tml_item[^"]*"[^>]*data-item-user="([^"]*)"[^>]*>([\s\S]*?)</li>',
    );

    for (final match in itemRegex.allMatches(html)) {
      try {
        final username = match.group(1) ?? '';
        final content = match.group(2) ?? '';
        final item = _parseSingleItem(username, content);
        if (item != null) items.add(item);
      } catch (_) {
        // 跳过解析失败的条目
      }
    }
    return items;
  }

  /// 解析单个时间线条目
  static TimelineItem? _parseSingleItem(String username, String html) {
    // 提取头像 URL
    final avatarMatch = RegExp(
      r"background-image:url\('([^']+)'\)",
    ).firstMatch(html);
    var avatarUrl = avatarMatch?.group(1) ?? '';
    if (avatarUrl.startsWith('//')) avatarUrl = 'https:$avatarUrl';

    // 提取昵称
    final nicknameMatch = RegExp(
      r'<a\s+href="[^"]*"\s+class="l">([^<]+)</a>',
    ).firstMatch(html);
    final nickname = nicknameMatch?.group(1) ?? username;

    // 提取 info 区域
    final infoMatch = RegExp(
      r'<span\s+class="info[^"]*">([\s\S]*?)</span>\s*$',
    ).firstMatch(html);
    if (infoMatch == null) return null;
    final infoHtml = infoMatch.group(1) ?? '';

    // 提取动作文本: 昵称链接之后、下一个链接或 <div 之前的纯文本
    final actionMatch = RegExp(
      r'class="l">[^<]*</a>\s*([^<]+?)\s*<',
    ).firstMatch(infoHtml);
    final actionText = actionMatch?.group(1)?.trim() ?? '';

    // 提取动作目标（第二个链接文本）
    final allLinks = RegExp(
      r'<a\s+href="([^"]*)"[^>]*class="l"[^>]*>([^<]+)</a>',
    ).allMatches(infoHtml).toList();
    String? targetText;
    if (allLinks.length >= 2) {
      targetText = allLinks[1].group(2);
    }

    // 提取条目卡片信息
    int? subjectId;
    String? subjectName;
    String? subjectNameCn;
    String? subjectCoverUrl;
    String? subjectInfo;
    double? score;
    String? rank;

    final cardMatch = RegExp(
      r'<div\s+class="card[^"]*">([\s\S]*?)</div>\s*</div>\s*</div>',
    ).firstMatch(infoHtml);

    if (cardMatch != null) {
      final cardHtml = cardMatch.group(1) ?? '';

      // subject ID
      final subjectIdMatch = RegExp(
        r'href="[^"]*?/subject/(\d+)"',
      ).firstMatch(cardHtml);
      if (subjectIdMatch != null) {
        subjectId = int.tryParse(subjectIdMatch.group(1) ?? '');
      }

      // cover
      final coverMatch = RegExp(r'<img\s+src="([^"]+)"').firstMatch(cardHtml);
      if (coverMatch != null) {
        var url = coverMatch.group(1) ?? '';
        if (url.startsWith('//')) url = 'https:$url';
        subjectCoverUrl = url;
      }

      // title (original) and subtitle (Chinese or vice versa)
      final titleMatch = RegExp(
        r'class="title">\s*<a[^>]*>([^<]+)',
      ).firstMatch(cardHtml);
      if (titleMatch != null) {
        subjectName = titleMatch.group(1)?.trim();
      }

      final subtitleMatch = RegExp(
        r'<small\s+class="subtitle[^"]*">([^<]+)</small>',
      ).firstMatch(cardHtml);
      if (subtitleMatch != null) {
        subjectNameCn = subtitleMatch.group(1)?.trim();
      }

      // 如果 title 里含中文且 subtitle 含日文，交换
      if (subjectName != null && _hasChinese(subjectName)) {
        final tmp = subjectName;
        subjectName = subjectNameCn;
        subjectNameCn = tmp;
      }

      // info line
      final infoLineMatch = RegExp(
        r'class="info tip">\s*([\s\S]*?)\s*</p>',
      ).firstMatch(cardHtml);
      if (infoLineMatch != null) {
        subjectInfo = infoLineMatch
            .group(1)
            ?.replaceAll(RegExp(r'<[^>]+>'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }

      // score
      final scoreMatch = RegExp(
        r'class="fade">\s*([\d.]+)\s*</small>',
      ).firstMatch(cardHtml);
      if (scoreMatch != null) {
        score = double.tryParse(scoreMatch.group(1) ?? '');
      }

      // rank
      final rankMatch = RegExp(
        r'class="rank">\s*([^<]+)\s*</span>',
      ).firstMatch(cardHtml);
      if (rankMatch != null) {
        rank = rankMatch.group(1)?.trim();
      }
    }

    // 如果没有卡片但有链接，从链接提取 subjectId
    if (subjectId == null && allLinks.length >= 2) {
      final href = allLinks[1].group(1) ?? '';
      final idMatch = RegExp(r'/subject/(\d+)').firstMatch(href);
      if (idMatch != null) {
        subjectId = int.tryParse(idMatch.group(1) ?? '');
      }
    }

    // 提取时间
    final timeMatch = RegExp(
      r'class="titleTip"[^>]*>([^<]+)</span>',
    ).firstMatch(infoHtml);
    final timeText = timeMatch?.group(1)?.trim() ?? '';

    if (nickname.isEmpty && actionText.isEmpty) return null;

    return TimelineItem(
      username: username,
      nickname: nickname,
      avatarUrl: avatarUrl,
      actionText: actionText,
      targetText: targetText,
      subjectId: subjectId,
      subjectName: subjectName,
      subjectNameCn: subjectNameCn,
      subjectCoverUrl: subjectCoverUrl,
      subjectInfo: subjectInfo,
      score: score,
      rank: rank,
      timeText: timeText,
    );
  }

  static List<RakuenTopic> _parseRakuenTopicsHtml(String html) {
    final topics = <RakuenTopic>[];
    final itemRegex = RegExp(
      r'<li\s+id="item_([^"]+)"[^>]*class="[^"]*item_list[^"]*"[^>]*>([\s\S]*?)</li>',
    );

    for (final match in itemRegex.allMatches(html)) {
      try {
        final rawId = match.group(1) ?? '';
        final content = match.group(2) ?? '';
        final firstUnderscore = rawId.indexOf('_');
        final type = firstUnderscore > 0
            ? rawId.substring(0, firstUnderscore)
            : rawId;

        final avatarLinkMatch = RegExp(
          r'<a\s+href="([^"]+)"[^>]*class="avatar [^"]*"([^>]*)>',
        ).firstMatch(content);
        final avatarAnchorAttrs = avatarLinkMatch?.group(2) ?? '';
        final topicUrl = _normalizeWebUrl(avatarLinkMatch?.group(1) ?? '');
        final authorName = _decodeHtml(
          RegExp(r'title="([^"]*)"').firstMatch(avatarAnchorAttrs)?.group(1) ??
              '',
        ).trim();

        var avatarUrl = '';
        final avatarUrlMatch = RegExp(
          r'''background-image:url\((['"]?)([^)'"]+)\1\)''',
        ).firstMatch(content);
        if (avatarUrlMatch != null) {
          avatarUrl = _normalizeWebUrl(avatarUrlMatch.group(2) ?? '');
        }

        final titleMatch = RegExp(
          r'<a\s+href="([^"]+)"\s+class="title avatar l"[^>]*>([\s\S]*?)</a>',
        ).firstMatch(content);
        final title = _decodeHtml(
          _stripTags(titleMatch?.group(2) ?? ''),
        ).trim();

        final replyText = RegExp(
          r'<small class="grey">\(\+(\d+)\)</small>',
        ).firstMatch(content)?.group(1);
        final replyCount = int.tryParse(replyText ?? '') ?? 0;

        final sourceMatch = RegExp(
          r'<span class="row">\s*(?:<a\s+href="([^"]+)"[^>]*>([\s\S]*?)</a>)?\s*<small class="time">([\s\S]*?)</small>',
        ).firstMatch(content);
        final sourceUrl = _normalizeWebUrl(sourceMatch?.group(1) ?? '');
        final sourceTitle = _decodeHtml(
          _stripTags(sourceMatch?.group(2) ?? ''),
        ).trim();
        final timeText = _decodeHtml(
          _stripTags(sourceMatch?.group(3) ?? ''),
        ).replaceAll(RegExp(r'\s+'), ' ').trim();

        if (topicUrl.isEmpty || title.isEmpty) continue;

        topics.add(
          RakuenTopic(
            id: rawId,
            type: type,
            title: title,
            topicUrl: topicUrl,
            avatarUrl: avatarUrl,
            replyCount: replyCount,
            timeText: timeText,
            sourceTitle: sourceTitle.isEmpty ? null : sourceTitle,
            sourceUrl: sourceUrl.isEmpty ? null : sourceUrl,
            authorName: authorName.isEmpty ? null : authorName,
          ),
        );
      } catch (_) {
        // Skip malformed topic blocks.
      }
    }

    return topics;
  }

  static RakuenTopicDetail _parseRakuenTopicDetailHtml({
    required String html,
    required String topicUrl,
  }) {
    final pageHeaderHtml = RegExp(
      r'<div id="pageHeader">([\s\S]*?)</div>\s*<hr class="board"',
    ).firstMatch(html)?.group(1);

    final sourceAnchorMatches = RegExp(
      r'<a\s+href="([^"]+)"[^>]*>([\s\S]*?)</a>',
    ).allMatches(pageHeaderHtml ?? '').toList();

    final sourceUrl = sourceAnchorMatches.isNotEmpty
        ? _normalizeWebUrl(sourceAnchorMatches.first.group(1) ?? '')
        : null;
    final sourceTitle = sourceAnchorMatches.isNotEmpty
        ? _decodeHtml(
            _stripTags(sourceAnchorMatches.first.group(2) ?? ''),
          ).trim()
        : null;
    final sectionTitle = sourceAnchorMatches.length >= 2
        ? _decodeHtml(_stripTags(sourceAnchorMatches[1].group(2) ?? '')).trim()
        : null;

    final coverUrlMatch = RegExp(
      r'<div id="pageHeader">[\s\S]*?<img src="([^"]+)"',
    ).firstMatch(html);
    final coverUrl = coverUrlMatch != null
        ? _normalizeWebUrl(coverUrlMatch.group(1) ?? '')
        : null;

    final title = _decodeHtml(
      _stripTags(
        RegExp(
              r'<h1>[\s\S]*?<br\s*/?>([\s\S]*?)</h1>',
            ).firstMatch(pageHeaderHtml ?? '')?.group(1) ??
            '',
      ),
    ).trim();

    final canonicalUrlMatch = RegExp(
      r'rakuen_redirect_url\s*=\s*"([^"]+)"',
    ).firstMatch(html);
    final canonicalUrl = canonicalUrlMatch != null
        ? _normalizeWebUrl(canonicalUrlMatch.group(1) ?? '')
        : null;

    final originalPost = _parseOriginalPost(html);
    final replies = _parseRakuenReplies(html);

    return RakuenTopicDetail(
      title: title.isEmpty ? '主题详情' : title,
      topicUrl: topicUrl,
      canonicalUrl: canonicalUrl?.isEmpty == true ? null : canonicalUrl,
      sourceTitle: sourceTitle?.isEmpty == true ? null : sourceTitle,
      sourceUrl: sourceUrl?.isEmpty == true ? null : sourceUrl,
      sectionTitle: sectionTitle?.isEmpty == true ? null : sectionTitle,
      coverUrl: coverUrl?.isEmpty == true ? null : coverUrl,
      originalPost: originalPost,
      replies: replies,
    );
  }

  static RakuenPost? _parseOriginalPost(String html) {
    final blockMatch = RegExp(
      r'<div id="post_(\d+)" class="postTopic[\s\S]*?</div>\s*</div>\s*</div>\s*</div>',
    ).firstMatch(html);
    if (blockMatch == null) return null;
    final content = blockMatch.group(0) ?? '';
    final id = blockMatch.group(1) ?? '';
    return _parseRakuenPostBlock(
      id: id,
      blockHtml: content,
      contentClassName: 'topic_content',
      avatarClassHint: 'avatarSize48',
    );
  }

  static List<RakuenPost> _parseRakuenReplies(String html) {
    final itemRegex = RegExp(
      r'<div id="post_(\d+)" class="[^"]*row row_reply[^"]*"[^>]*>[\s\S]*?(?=<div id="post_\d+" class="[^"]*row row_reply|<template|<script|</body>)',
    );
    final posts = <RakuenPost>[];

    for (final match in itemRegex.allMatches(html)) {
      final id = match.group(1) ?? '';
      final blockHtml = match.group(0) ?? '';
      final parsed = _parseRakuenPostBlock(
        id: id,
        blockHtml: blockHtml,
        contentClassName: 'message',
        avatarClassHint: 'avatarReSize40',
      );
      if (parsed != null) posts.add(parsed);
    }

    return posts;
  }

  static RakuenPost? _parseRakuenPostBlock({
    required String id,
    required String blockHtml,
    required String contentClassName,
    required String avatarClassHint,
  }) {
    final floorTimeMatch = RegExp(
      r'class="floor-anchor">([^<]+)</a>\s*-\s*([^<]+)</small>|<small>(#[^<]+)\s*-\s*([^<]+)</small>',
    ).firstMatch(blockHtml);

    final floor = _decodeHtml(
      (floorTimeMatch?.group(1) ?? floorTimeMatch?.group(3) ?? '').trim(),
    );
    final timeText = _decodeHtml(
      (floorTimeMatch?.group(2) ?? floorTimeMatch?.group(4) ?? '').trim(),
    );

    final avatarUrlMatch = RegExp(
      r'''background-image:url\((['"]?)([^)'"]+)\1\)''',
    ).firstMatch(blockHtml);
    final avatarUrl = avatarUrlMatch != null
        ? _normalizeWebUrl(avatarUrlMatch.group(2) ?? '')
        : '';

    final userLinkMatch = RegExp(
      r'<a(?: id="[^"]+")?\s+href="/user/([^"]+)"[^>]*class="[^"]*\bl\b[^"]*"[^>]*>([\s\S]*?)</a>',
    ).firstMatch(blockHtml);
    final username = userLinkMatch?.group(1) ?? '';
    final nickname = _decodeHtml(
      _stripTags(userLinkMatch?.group(2) ?? ''),
    ).trim();

    final signMatch = RegExp(
      r'<span class="sign tip_j">\(([\s\S]*?)\)</span>',
    ).firstMatch(blockHtml);
    final sign = _decodeHtml(_stripTags(signMatch?.group(1) ?? '')).trim();

    final contentMatch = RegExp(
      '<div class="$contentClassName[^"]*">([\\s\\S]*?)</div>',
    ).firstMatch(blockHtml);
    final content = _htmlBlockToText(contentMatch?.group(1) ?? '');

    final subReplies = <RakuenPost>[];
    final subReplyRegion = RegExp(
      r'<div class="topic_sub_reply"[^>]*>([\s\S]*?)</div>\s*</div>\s*</div>',
    ).firstMatch(blockHtml)?.group(1);
    if (subReplyRegion != null && subReplyRegion.isNotEmpty) {
      final subRegex = RegExp(
        r'<div id="post_(\d+)" class="sub_reply_bg[\s\S]*?(?=<div id="post_\d+" class="sub_reply_bg|$)',
      );
      for (final match in subRegex.allMatches(subReplyRegion)) {
        final subId = match.group(1) ?? '';
        final subBlock = match.group(0) ?? '';
        final parsed = _parseRakuenPostBlock(
          id: subId,
          blockHtml: subBlock,
          contentClassName: 'cmt_sub_content',
          avatarClassHint: 'avatarReSize32',
        );
        if (parsed != null) subReplies.add(parsed);
      }
    }

    if (nickname.isEmpty && content.isEmpty) return null;

    return RakuenPost(
      id: id,
      floor: floor.isEmpty ? '#?' : floor,
      timeText: timeText,
      username: username,
      nickname: nickname.isEmpty ? username : nickname,
      avatarUrl: avatarUrl,
      sign: sign.isEmpty ? null : sign,
      content: content,
      subReplies: subReplies,
    );
  }

  static String _htmlBlockToText(String html) {
    if (html.isEmpty) return '';
    var value = html;
    value = value.replaceAllMapped(
      RegExp(r'<img[^>]*alt="([^"]*)"[^>]*>'),
      (match) => match.group(1) ?? '',
    );
    value = value.replaceAllMapped(
      RegExp(
        r'<span class="text_mask"[\s\S]*?<span class="inner">([\s\S]*?)</span>[\s\S]*?</span>',
      ),
      (match) => _decodeHtml(_stripTags(match.group(1) ?? '')),
    );
    value = value.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    value = value.replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n');
    value = value.replaceAllMapped(
      RegExp(r'<a\s+href="([^"]+)"[^>]*>([\s\S]*?)</a>'),
      (match) => _decodeHtml(_stripTags(match.group(2) ?? '')),
    );
    value = _decodeHtml(_stripTags(value));
    value = value.replaceAll('\r', '');
    value = value.replaceAll(RegExp(r'[ \t]*\n[ \t]*'), '\n');
    value = value.replaceAll(RegExp(r'\n{2,}'), '\n');
    value = value.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    return value.trim();
  }

  static String _normalizeWebUrl(String value) {
    if (value.isEmpty) return '';
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) return '${BgmConst.webBaseUrl}$value';
    return value;
  }

  static String _stripTags(String value) {
    return value.replaceAll(RegExp(r'<[^>]+>'), '');
  }

  static String _decodeHtml(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#039;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
  }

  /// 检测字符串是否包含中文字符
  static bool _hasChinese(String text) {
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
  }
}

/// 分页结果
class PagedResult<T> {
  final int total;
  final int limit;
  final int offset;
  final List<T> data;

  PagedResult({
    required this.total,
    required this.limit,
    required this.offset,
    required this.data,
  });

  bool get hasMore => offset + data.length < total;
}

/// 网络请求日志拦截器（仅在调试模式）
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint('🌐 REQUEST: ${options.method} ${options.path}');
    debugPrint('   Headers: ${options.headers}');
    if (options.queryParameters.isNotEmpty) {
      debugPrint('   Query: ${options.queryParameters}');
    }
    if (options.data != null) {
      debugPrint('   Data: ${options.data}');
    }
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    debugPrint(
      '✅ RESPONSE: ${response.statusCode} ${response.requestOptions.path}',
    );
    debugPrint('   Data: ${response.data}');
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint('❌ ERROR: ${err.type} ${err.requestOptions.path}');
    debugPrint('   Message: ${err.message}');
    debugPrint('   Response: ${err.response?.data}');
    debugPrint('   StackTrace: ${err.stackTrace}');
    super.onError(err, handler);
  }
}
