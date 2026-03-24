import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../constants.dart';
import '../models/calendar.dart';
import '../models/character.dart';
import '../models/collection.dart';
import '../models/comment.dart';
import '../models/episode.dart';
import '../models/bangumi_web_session.dart';
import '../models/rakuen_topic.dart';
import '../models/rakuen_topic_detail.dart';
import '../models/subject.dart';
import '../models/timeline.dart';
import '../models/user.dart';

/// Bangumi API 客户端
class ApiClient {
  late final Dio _dio;
  String? _accessToken;
  String? _webCookie;
  BangumiWebSession? _webSession;

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

    // 初始化网页 Dio 实例
    _webDio = Dio(
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
    _webDio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.headers['Cookie'] == null) {
            final cookieHeader = _buildCookieHeaderForUri(options.uri);
            if (cookieHeader != null && cookieHeader.isNotEmpty) {
              options.headers['Cookie'] = cookieHeader;
            }
          }
          handler.next(options);
        },
      ),
    );

    // 初始化 next API Dio 实例
    _nextDio = Dio(
      BaseOptions(
        baseUrl: BgmConst.nextBaseUrl,
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
      _webDio.interceptors.add(LoggingInterceptor());
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
  bool get hasWebSession => _webSession?.isValid == true;
  bool get hasWebCookie => hasWebSession;

  void setWebCookie(String? cookie) {
    final normalized = sanitizeWebCookie(cookie ?? '');
    _webCookie = normalized.isEmpty ? null : normalized;
    if (_webCookie == null) {
      _webDio.options.headers.remove('Cookie');
      if (kDebugMode) {
        print('[ApiClient] Cookie 已清除');
      }
    } else {
      _webDio.options.headers['Cookie'] = _webCookie;
      if (kDebugMode) {
        print('[ApiClient] Cookie 已设置');
        print('[ApiClient]   长度: ${_webCookie!.length} 字符');
        print(
          '[ApiClient]   包含 chii_auth: ${_webCookie!.contains('chii_auth')}',
        );
        print('[ApiClient]   包含 chii_sid: ${_webCookie!.contains('chii_sid')}');
        print(
          '[ApiClient]   包含 chii_sec_id: ${_webCookie!.contains('chii_sec_id')}',
        );
        print(
          '[ApiClient]   开头: ${_webCookie!.substring(0, _webCookie!.length > 100 ? 100 : _webCookie!.length)}',
        );

        // 验证 Cookie 是否真的在 HTTP 头中
        final cookieInHeaders = _webDio.options.headers['Cookie'];
        print(
          '[ApiClient] HTTP 头中的 Cookie: ${cookieInHeaders != null ? '已设置 (${(cookieInHeaders as String).length} 字符)' : '未设置'}',
        );
      }
    }
  }

  Future<WebSessionInfo?> getWebSessionInfo({String? cookie}) async {
    final normalized = cookie == null ? null : sanitizeWebCookie(cookie);
    final resp = await _webDio.get(
      '/',
      options: normalized == null
          ? null
          : Options(headers: {'Cookie': normalized}),
    );
    return _parseWebSessionInfo(resp.data as String);
  }

  void setWebSession(BangumiWebSession? session) {
    _webSession = session?.isValid == true ? session : null;
    if (_webSession == null) {
      _webCookie = null;
    }
    if (!kDebugMode) return;
    if (_webSession == null) {
      print('[ApiClient] Web session cleared');
      return;
    }
    print('[ApiClient] Web session set');
    print('[ApiClient]   user: @${_webSession!.username}');
    print('[ApiClient]   uid: ${_webSession!.uid}');
    print('[ApiClient]   cookies: ${_webSession!.cookies.length}');
  }

  Future<WebSessionInfo?> validateWebSession(BangumiWebSession session) async {
    final cookieHeader = session.buildCookieHeaderForUri(
      Uri.parse(BgmConst.webBaseUrl),
    );
    if (cookieHeader == null || cookieHeader.isEmpty) return null;
    final resp = await _webDio.get(
      '/',
      options: Options(headers: {'Cookie': cookieHeader}),
    );
    return _parseWebSessionInfo(resp.data as String);
  }

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

  /// 获取角色出演条目
  Future<List<CharacterSubject>> getCharacterSubjects(int characterId) async {
    final resp = await _dio.get('/v0/characters/$characterId/subjects');
    final list = resp.data as List<dynamic>;
    return list
        .whereType<Map<String, dynamic>>()
        .map(CharacterSubject.fromJson)
        .toList();
  }

  /// 获取角色吐槽列表
  Future<PagedResult<Comment>> getCharacterComments({
    required int characterId,
    int limit = 30,
    int offset = 0,
  }) async {
    try {
      final resp = await _nextDio.get(
        '/p1/characters/$characterId/comments',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final data = resp.data;
      if (data is List) {
        final all = data
            .whereType<Map>()
            .map((e) => _normalizeCommentPayload(Map<String, dynamic>.from(e)))
            .map(Comment.fromJson)
            .toList();
        final start = offset.clamp(0, all.length);
        final end = (offset + limit).clamp(0, all.length);
        return PagedResult<Comment>(
          total: all.length,
          limit: limit,
          offset: offset,
          data: all.sublist(start, end),
        );
      }
      if (data is Map<String, dynamic>) {
        final list =
            (data['data'] as List<dynamic>?) ??
            (data['list'] as List<dynamic>?) ??
            (data['comments'] as List<dynamic>?) ??
            const [];
        final comments = list
            .whereType<Map>()
            .map((e) => _normalizeCommentPayload(Map<String, dynamic>.from(e)))
            .map(Comment.fromJson)
            .toList();
        final total =
            (data['total'] as int?) ??
            (data['count'] as int?) ??
            comments.length;
        return PagedResult<Comment>(
          total: total,
          limit: limit,
          offset: offset,
          data: comments,
        );
      }
    } catch (_) {}

    try {
      final resp = await _webDio.get('/character/$characterId');
      final html = resp.data as String;
      final comments = _parseCommentsFromHtml(html);
      final start = offset;
      final end = (offset + limit).clamp(0, comments.length);
      final List<Comment> paged = start < comments.length
          ? comments.sublist(start, end)
          : const <Comment>[];
      return PagedResult<Comment>(
        total: comments.length,
        limit: limit,
        offset: offset,
        data: paged,
      );
    } catch (_) {
      return PagedResult<Comment>(
        total: 0,
        limit: limit,
        offset: offset,
        data: [],
      );
    }
  }

  // ========== 吐槽/评论 ==========
  // 通过网页爬取实现（API 不提供）

  static Map<String, dynamic> _normalizeCommentPayload(
    Map<String, dynamic> json,
  ) {
    final normalized = Map<String, dynamic>.from(json);
    final createdAt = normalized['created_at'] ?? normalized['createdAt'];
    final updatedAt = normalized['updated_at'] ?? normalized['updatedAt'];

    String normalizeTimestamp(dynamic value) {
      if (value == null) return '';
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000)
            .toIso8601String();
      }
      if (value is num) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000)
            .toIso8601String();
      }
      if (value is String) {
        final asInt = int.tryParse(value);
        if (asInt != null) {
          return DateTime.fromMillisecondsSinceEpoch(asInt * 1000)
              .toIso8601String();
        }
        return value;
      }
      return value.toString();
    }

    normalized['created_at'] = normalizeTimestamp(createdAt);
    normalized['updated_at'] = normalizeTimestamp(updatedAt);
    normalized['user'] = _normalizeCommentUser(normalized['user']);
    return normalized;
  }

  static Map<String, dynamic> _normalizeCommentUser(dynamic raw) {
    if (raw is! Map) {
      return const {};
    }
    final user = Map<String, dynamic>.from(raw);
    final avatar = user['avatar'];
    if (avatar is Map) {
      final avatarMap = Map<String, dynamic>.from(avatar);
      user['avatar'] =
          (avatarMap['medium'] as String?) ??
          (avatarMap['small'] as String?) ??
          (avatarMap['large'] as String?) ??
          '';
    } else if (avatar == null) {
      user['avatar'] = '';
    }
    return user;
  }

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
  /// 使用 POST 方法：不存在则创建，存在则修改
  /// 这是修改条目收藏的标准方法，无需异常处理
  Future<void> patchCollection({
    required int subjectId,
    int? type,
    int? rate,
    int? epStatus,
    int? volStatus,
    String? comment,
    bool? private_,
    List<String>? tags,
  }) async {
    final data = <String, dynamic>{};
    if (type != null) data['type'] = type;
    if (rate != null) data['rate'] = rate;
    if (epStatus != null) data['ep_status'] = epStatus;
    if (volStatus != null) data['vol_status'] = volStatus;
    if (comment != null) data['comment'] = comment;
    if (private_ != null) data['private'] = private_;
    if (tags != null) data['tags'] = tags;

    // 使用 POST 方法，自动处理不存在则创建、存在则修改的情况
    await _dio.post('/v0/users/-/collections/$subjectId', data: data);
  }

  // ========== 时间线 ==========

  /// 用于抓取 bgm.tv 网页的 Dio 实例（全站动态 HTML 解析）
  late final Dio _webDio;

  /// 用于调用 next.bgm.tv /p1/ 私有 JSON API 的 Dio 实例
  late final Dio _nextDio;

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

  Future<RakuenTopic> resolveRakuenTopic({required String input}) async {
    final normalized = input.trim();
    if (normalized.isEmpty) {
      throw Exception('请输入帖子 ID');
    }

    final candidates = _buildRakuenTopicCandidates(normalized);
    if (candidates.isEmpty) {
      throw Exception('无法识别帖子 ID');
    }

    for (final candidate in candidates) {
      try {
        final detail = await getRakuenTopicDetail(topicUrl: candidate);
        if (!_looksLikeRakuenTopicDetail(detail)) continue;

        final resolvedUrl = detail.canonicalUrl ?? candidate;
        final identity = _parseRakuenTopicIdentity(resolvedUrl);
        return RakuenTopic(
          id: identity == null
              ? 'manual_${DateTime.now().millisecondsSinceEpoch}'
              : '${identity.type}_${identity.id}',
          type: identity?.type ?? '',
          title: detail.title,
          topicUrl: resolvedUrl,
          avatarUrl: detail.coverUrl ?? '',
          replyCount: detail.replies.length,
          timeText: '帖子 ID 跳转',
          sourceTitle: detail.sourceTitle,
          sourceUrl: detail.sourceUrl,
          authorName: detail.originalPost?.username,
        );
      } catch (_) {
        continue;
      }
    }

    throw Exception('未找到对应帖子');
  }

  Future<String> createRakuenTopic({
    required String sourceUrl,
    required String title,
    required String content,
  }) async {
    if (kDebugMode) {
      print('[ApiClient] 开始发帖流程');
      print('[ApiClient] 来源URL: $sourceUrl');
      print('[ApiClient] 标题: $title');
      print('[ApiClient] 内容长度: ${content.length}');
      print('[ApiClient] Cookie已设置: ${_webCookie != null}');
    }

    // 先访问来源页面来建立会话
    if (kDebugMode) {
      print('[ApiClient] 先访问来源页面来建立会话');
    }
    try {
      await _fetchWebResponse(_normalizeWebUrl(sourceUrl));
    } catch (e) {
      if (kDebugMode) {
        print('[ApiClient] 访问来源页面失败，但继续: $e');
      }
    }

    final newTopicUrl = _buildRakuenNewTopicUrl(sourceUrl);
    if (newTopicUrl == null) {
      throw Exception('当前来源暂不支持发帖');
    }

    if (kDebugMode) {
      print('[ApiClient] 发帖页面URL: $newTopicUrl');
    }

    final uri = Uri.parse(newTopicUrl);
    final pageResp = await _webDio.get(
      uri.path,
      queryParameters: uri.queryParameters.isEmpty ? null : uri.queryParameters,
    );
    final html = pageResp.data as String;
    final form = _parseRakuenNewTopicForm(html);
    if (form == null) {
      if (kDebugMode) {
        print('[ApiClient] 未找到发帖表单');
      }
      throw Exception('当前页面没有可用的发帖表单');
    }

    if (kDebugMode) {
      print('[ApiClient] 找到发帖表单，准备提交');
      print('[ApiClient] formhash: ${form.formhash}');
      print('[ApiClient] actionUrl: ${form.actionUrl}');
      print('[ApiClient] 表单字段: ${form.hiddenFields.keys.toList()}');
    }

    final response = await _submitRakuenForm(
      actionUrl: form.actionUrl,
      data: {
        ...form.hiddenFields,
        'title': title.trim(),
        'content': content.trim(),
      },
      refererUrl: newTopicUrl,
    );

    if (kDebugMode) {
      print('[ApiClient] 发帖响应状态码: ${response.statusCode}');
    }

    final resultUrl = _normalizeWebUrl(
      response.realUri.toString().isNotEmpty
          ? response.realUri.toString()
          : (response.headers.value('location') ?? form.actionUrl),
    );

    if (kDebugMode) {
      print('[ApiClient] 发帖提交完成，结果URL: $resultUrl');
    }

    return resultUrl;
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

    final episodeDescMatch = RegExp(
      r'<div\s+class="[^"]*epDesc[^"]*"[^>]*>([\s\S]*?)</div>',
      caseSensitive: false,
    ).firstMatch(html);
    final episodeDescHtml = episodeDescMatch?.group(1) ?? '';
    final episodeTipMatch = RegExp(
      r'<span\s+class="[^"]*tip[^"]*"[^>]*>([\s\S]*?)</span>',
      caseSensitive: false,
    ).firstMatch(episodeDescHtml);
    final episodeTip = _decodeHtml(
      _stripTags(episodeTipMatch?.group(1) ?? ''),
    ).trim();
    final episodeBodyHtml = episodeDescHtml.replaceFirst(
      RegExp(
        r'<span\s+class="[^"]*tip[^"]*"[^>]*>[\s\S]*?</span>',
        caseSensitive: false,
      ),
      '',
    );
    final episodeDescription = _htmlBlockToText(episodeBodyHtml).trim();

    final session = _parseWebSessionInfo(html);
    final replyForm = _parseRakuenReplyForm(html);
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
      episodeTip: episodeTip.isEmpty ? null : episodeTip,
      episodeDescription: episodeDescription.isEmpty
          ? null
          : episodeDescription,
      replyAuthor: session?.username,
      canReply: session != null && replyForm != null,
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
    final subReplyActionMatch = RegExp(
      r'''onclick="(subReply\([^\"]+\))"''',
      caseSensitive: false,
    ).firstMatch(blockHtml);
    final subReplyAction = subReplyActionMatch?.group(1)?.trim();

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
      subReplyAction: subReplyAction?.isEmpty == true ? null : subReplyAction,
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

  static String sanitizeWebCookie(String value) {
    var normalized = value.trim();
    normalized = normalized.replaceFirst(
      RegExp(r'^Cookie:\s*', caseSensitive: false),
      '',
    );
    normalized = normalized.replaceAll('\r', ' ');
    normalized = normalized.replaceAll('\n', ' ');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ');
    normalized = normalized.replaceAll(RegExp(r';\s*'), '; ');
    return normalized.trim();
  }

  static WebSessionInfo? _parseWebSessionInfo(String html) {
    final uidFromChobits =
        int.tryParse(
          RegExp(r'CHOBITS_UID\s*=\s*(\d+)').firstMatch(html)?.group(1) ?? '0',
        ) ??
        0;
    final uidFromAlt =
        int.tryParse(
          RegExp(r'CHOBITS_USER_UID\s*=\s*(\d+)').firstMatch(html)?.group(1) ??
              '0',
        ) ??
        0;

    final usernameFromChobits =
        RegExp(
          r'''CHOBITS_USERNAME\s*=\s*['"]([^'"]*)['"]''',
        ).firstMatch(html)?.group(1)?.trim() ??
        '';

    final headerUserLinkMatch =
        RegExp(
          r'idBadgerNeue[\s\S]{0,1200}?href="/user/([^"/?#]+)"',
          caseSensitive: false,
        ).firstMatch(html) ??
        RegExp(
          r'id="dock"[\s\S]{0,1200}?href="/user/([^"/?#]+)"',
          caseSensitive: false,
        ).firstMatch(html) ??
        RegExp(
          r'id="badgeUserPanel"[\s\S]{0,1200}?href="/user/([^"/?#]+)"',
          caseSensitive: false,
        ).firstMatch(html);
    final usernameFromHeader = headerUserLinkMatch?.group(1)?.trim() ?? '';

    final hasHeaderLogout = RegExp(
      r'(idBadgerNeue|id="dock"|id="badgeUserPanel")[\s\S]{0,1200}?(?:/logout|/signout)',
      caseSensitive: false,
    ).hasMatch(html);

    final fallbackUsername = usernameFromChobits.isNotEmpty
        ? usernameFromChobits
        : usernameFromHeader;
    final fallbackUid = uidFromChobits > 0
        ? uidFromChobits
        : (uidFromAlt > 0 ? uidFromAlt : int.tryParse(usernameFromHeader) ?? 0);

    if (fallbackUsername.isEmpty || fallbackUid <= 0) {
      return null;
    }
    if (!hasHeaderLogout && uidFromChobits <= 0 && uidFromAlt <= 0) {
      return null;
    }

    return WebSessionInfo(uid: fallbackUid, username: fallbackUsername);
  }

  static _RakuenReplyForm? _parseRakuenReplyForm(String html) {
    final formRegex = RegExp(
      r'<form([^>]*)action="([^"]+)"[^>]*>([\s\S]*?)</form>',
      caseSensitive: false,
    );
    for (final formMatch in formRegex.allMatches(html)) {
      final attrs = formMatch.group(1) ?? '';
      final body = formMatch.group(3) ?? '';

      // 查找可能的回复表单
      final hasReplyId = attrs.contains('id="ReplyForm"');
      final hasContentField = RegExp(
        r'<textarea[^>]+name="content"',
        caseSensitive: false,
      ).hasMatch(body);
      final hasFormhash = body.contains('formhash');

      if (!hasReplyId && !hasContentField && !hasFormhash) {
        continue;
      }

      final actionUrl = _normalizeWebUrl(formMatch.group(2) ?? '');

      if (actionUrl.isEmpty) {
        continue;
      }

      // 排除明显不是回复表单的 action
      if (actionUrl.contains('/search') || actionUrl.contains('/browse')) {
        continue;
      }

      // 只在满足严格条件或宽松条件时才提取
      if (hasReplyId || hasContentField) {
        final hiddenFields = _extractFormFields(body);
        if (hiddenFields['formhash'] != null &&
            hiddenFields['formhash']!.isNotEmpty) {
          return _RakuenReplyForm(
            actionUrl: actionUrl,
            formhash: hiddenFields['formhash']!,
            lastview: hiddenFields['lastview'],
            hiddenFields: hiddenFields,
          );
        }
      }
    }

    // 宽松匹配：任何包含 formhash 的表单
    for (final formMatch in formRegex.allMatches(html)) {
      final body = formMatch.group(3) ?? '';
      if (!body.contains('formhash')) continue;

      final actionUrl = _normalizeWebUrl(formMatch.group(2) ?? '');
      if (actionUrl.isEmpty ||
          actionUrl.contains('/search') ||
          actionUrl.contains('/browse')) {
        continue;
      }

      final hiddenFields = _extractFormFields(body);
      if (hiddenFields['formhash'] != null &&
          hiddenFields['formhash']!.isNotEmpty) {
        return _RakuenReplyForm(
          actionUrl: actionUrl,
          formhash: hiddenFields['formhash']!,
          lastview: hiddenFields['lastview'],
          hiddenFields: hiddenFields,
        );
      }
    }

    return null;
  }

  /// 从表单 HTML 中提取所有 input 字段
  static Map<String, String> _extractFormFields(String formBody) {
    final fields = <String, String>{};

    // 方法1：匹配 name="..." value="..." 的顺序
    var inputRegex = RegExp(
      r'<input[^>]+name="([^"]+)"[^>]+value="([^"]*)"',
      caseSensitive: false,
    );
    for (final match in inputRegex.allMatches(formBody)) {
      final name = match.group(1);
      final value = match.group(2);
      if (name != null && value != null) {
        fields[name] = value;
      }
    }

    // 方法2：匹配 value="..." name="..." 的顺序（处理按钮等元素）
    inputRegex = RegExp(
      r'<input[^>]+value="([^"]*)"[^>]+name="([^"]+)"',
      caseSensitive: false,
    );
    for (final match in inputRegex.allMatches(formBody)) {
      final value = match.group(1);
      final name = match.group(2);
      if (name != null && value != null && !fields.containsKey(name)) {
        fields[name] = value;
      }
    }

    if (kDebugMode) {
      print('[ApiClient] 提取的表单字段: $fields');
    }

    return fields;
  }

  static _RakuenNewTopicForm? _parseRakuenNewTopicForm(String html) {
    final formMatch = RegExp(
      r'<form[^>]+id="ModifyTopicForm"[^>]+action="([^"]+)"[^>]*>([\s\S]*?)</form>',
      caseSensitive: false,
    ).firstMatch(html);
    if (formMatch == null) return null;
    final actionUrl = _normalizeWebUrl(formMatch.group(1) ?? '');
    final body = formMatch.group(2) ?? '';

    final hiddenFields = _extractFormFields(body);
    final formhash = hiddenFields['formhash'];

    if (actionUrl.isEmpty || formhash == null || formhash.isEmpty) {
      return null;
    }
    return _RakuenNewTopicForm(
      actionUrl: actionUrl,
      formhash: formhash,
      hiddenFields: hiddenFields,
    );
  }

  static String? _buildRakuenNewTopicUrl(String sourceUrl) {
    final normalized = _normalizeWebUrl(sourceUrl);
    final groupMatch = RegExp(r'/group/([^/?#]+)').firstMatch(normalized);
    if (groupMatch != null) {
      final groupName = groupMatch.group(1);
      if (groupName != null && groupName.isNotEmpty) {
        return '${BgmConst.webBaseUrl}/group/$groupName/new_topic';
      }
    }

    final subjectMatch = RegExp(r'/subject/(\d+)').firstMatch(normalized);
    if (subjectMatch != null) {
      final subjectId = subjectMatch.group(1);
      if (subjectId != null && subjectId.isNotEmpty) {
        return '${BgmConst.webBaseUrl}/subject/$subjectId/topic/new?type=subject';
      }
    }

    return null;
  }

  static List<String> _buildRakuenTopicCandidates(String input) {
    final candidates = <String>[];

    void addCandidate(String? value) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty || candidates.contains(trimmed)) return;
      candidates.add(trimmed);
    }

    final directUrl = _normalizeRakuenTopicUrl(input);
    if (directUrl != null) {
      addCandidate(directUrl);
    }

    final rakuenMatch = RegExp(
      r'(?:rakuen/topic/)?(group|subject|ep|crt|prsn)[/_: -]?(\d+)',
      caseSensitive: false,
    ).firstMatch(input);
    if (rakuenMatch != null) {
      final type = _normalizeRakuenTopicType(rakuenMatch.group(1));
      final id = rakuenMatch.group(2);
      if (type != null && id != null) {
        addCandidate('${BgmConst.webBaseUrl}/rakuen/topic/$type/$id');
      }
    }

    final aliasMatch = RegExp(
      r'(character|person|mono)[/_: -]?(\d+)',
      caseSensitive: false,
    ).firstMatch(input);
    if (aliasMatch != null) {
      final id = aliasMatch.group(2);
      if (id != null) {
        switch (aliasMatch.group(1)?.toLowerCase()) {
          case 'character':
            addCandidate('${BgmConst.webBaseUrl}/rakuen/topic/crt/$id');
            break;
          case 'person':
            addCandidate('${BgmConst.webBaseUrl}/rakuen/topic/prsn/$id');
            break;
          case 'mono':
            addCandidate('${BgmConst.webBaseUrl}/rakuen/topic/crt/$id');
            addCandidate('${BgmConst.webBaseUrl}/rakuen/topic/prsn/$id');
            break;
        }
      }
    }

    final digitsOnly = RegExp(r'^\d+$').hasMatch(input);
    if (digitsOnly) {
      for (final type in const ['group', 'subject', 'ep', 'crt', 'prsn']) {
        addCandidate('${BgmConst.webBaseUrl}/rakuen/topic/$type/$input');
      }
    }

    return candidates;
  }

  static String? _normalizeRakuenTopicUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    Uri? uri;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      uri = Uri.tryParse(trimmed);
    } else if (trimmed.startsWith('/')) {
      uri = Uri.tryParse('${BgmConst.webBaseUrl}$trimmed');
    } else if (trimmed.contains('/')) {
      uri = Uri.tryParse('${BgmConst.webBaseUrl}/$trimmed');
    }

    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (!{
      'bgm.tv',
      'www.bgm.tv',
      'bangumi.tv',
      'www.bangumi.tv',
      'chii.in',
      'www.chii.in',
    }.contains(host)) {
      return null;
    }

    final path = uri.path;
    if (RegExp(
      r'^/rakuen/topic/(group|subject|ep|crt|prsn)/\d+$',
    ).hasMatch(path)) {
      return Uri(
        scheme: 'https',
        host: BgmConst.webBaseUrl.replaceFirst(RegExp(r'^https?://'), ''),
        path: path,
      ).toString();
    }

    final directMatch = RegExp(
      r'^/(group/topic|subject/topic|ep|character/topic|person/topic)/(\d+)$',
    ).firstMatch(path);
    if (directMatch == null) return null;

    final segment = directMatch.group(1);
    final id = directMatch.group(2);
    final type = switch (segment) {
      'group/topic' => 'group',
      'subject/topic' => 'subject',
      'ep' => 'ep',
      'character/topic' => 'crt',
      'person/topic' => 'prsn',
      _ => null,
    };
    if (type == null || id == null) return null;
    return '${BgmConst.webBaseUrl}/rakuen/topic/$type/$id';
  }

  static String? _normalizeRakuenTopicType(String? type) {
    switch ((type ?? '').trim().toLowerCase()) {
      case 'group':
        return 'group';
      case 'subject':
        return 'subject';
      case 'ep':
        return 'ep';
      case 'crt':
      case 'character':
        return 'crt';
      case 'prsn':
      case 'person':
        return 'prsn';
      default:
        return null;
    }
  }

  static bool _looksLikeRakuenTopicDetail(RakuenTopicDetail detail) {
    return detail.originalPost != null ||
        detail.replies.isNotEmpty ||
        detail.canonicalUrl != null ||
        detail.sourceTitle != null ||
        detail.sectionTitle != null ||
        detail.coverUrl != null;
  }

  static _RakuenTopicIdentity? _parseRakuenTopicIdentity(String topicUrl) {
    final match = RegExp(
      r'/rakuen/topic/(group|subject|ep|crt|prsn)/(\d+)',
    ).firstMatch(topicUrl);
    if (match == null) return null;
    final type = match.group(1);
    final id = match.group(2);
    if (type == null || id == null) return null;
    return _RakuenTopicIdentity(type: type, id: id);
  }

  Future<Response<dynamic>> _submitRakuenForm({
    required String actionUrl,
    required Map<String, dynamic> data,
    required String refererUrl,
  }) {
    final uri = Uri.parse(actionUrl);

    if (kDebugMode) {
      print('[ApiClient] _submitRakuenForm 详情:');
      print('[ApiClient]   actionUrl: $actionUrl');
      print('[ApiClient]   uri.path: ${uri.path}');
      print('[ApiClient]   uri.host: ${uri.host}');
      print('[ApiClient]   uri.scheme: ${uri.scheme}');
      print('[ApiClient]   referer: $refererUrl');
      print('[ApiClient]   数据: $data');
    }

    return _webDio
        .post(
          uri.path,
          queryParameters: uri.queryParameters.isEmpty
              ? null
              : uri.queryParameters,
          data: data,
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            headers: {
              'Referer': refererUrl,
              'Origin': BgmConst.webBaseUrl,
              'X-Requested-With': 'XMLHttpRequest',
            },
            followRedirects: false, // 不自动跟随重定向，这样我们可以看到响应
            validateStatus: (status) =>
                status != null && status < 500, // 接受所有状态码
          ),
        )
        .then((response) {
          if (kDebugMode) {
            print('[ApiClient] _submitRakuenForm 响应:');
            print('[ApiClient]   状态码: ${response.statusCode}');
            print(
              '[ApiClient]   Location header: ${response.headers.value('location')}',
            );
          }
          return response;
        });
  }

  Future<Response<dynamic>> _fetchWebResponse(String url) {
    final uri = Uri.parse(url);
    return _webDio.get(
      uri.path,
      queryParameters: uri.queryParameters.isEmpty ? null : uri.queryParameters,
    );
  }

  String? _buildCookieHeaderForUri(Uri uri, {BangumiWebSession? session}) {
    final candidate = session ?? _webSession;
    if (candidate == null || !candidate.isValid) return null;
    return candidate.buildCookieHeaderForUri(uri);
  }

  /// 检测字符串是否包含中文字符
  static bool _hasChinese(String text) {
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
  }
}

/// 分页结果
class WebSessionInfo {
  final int uid;
  final String username;

  const WebSessionInfo({required this.uid, required this.username});
}

class _RakuenReplyForm {
  final String actionUrl;
  final String formhash;
  final String? lastview;
  final Map<String, String> hiddenFields; // 所有隐藏字段

  const _RakuenReplyForm({
    required this.actionUrl,
    required this.formhash,
    this.lastview,
    this.hiddenFields = const {},
  });
}

class _RakuenTopicIdentity {
  final String type;
  final String id;

  const _RakuenTopicIdentity({required this.type, required this.id});
}

class _RakuenNewTopicForm {
  final String actionUrl;
  final String formhash;
  final Map<String, String> hiddenFields;

  const _RakuenNewTopicForm({
    required this.actionUrl,
    required this.formhash,
    this.hiddenFields = const {},
  });
}

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
    // 只记录关键的请求信息
    final logPrefix =
        options.path.contains('rakuen') ||
            options.path.contains('timeline') ||
            options.path.contains('/group/topic') ||
            options.path.contains('/subject/topic')
        ? '🔵'
        : '🌐';
    debugPrint('$logPrefix ${options.method} ${options.path}');

    // 记录 Cookie 信息
    if (options.headers['Cookie'] != null) {
      final cookie = options.headers['Cookie'] as String;
      debugPrint(
        '   [Cookie] ${cookie.substring(0, cookie.length > 60 ? 60 : cookie.length)}...',
      );
    } else {
      debugPrint('   [Cookie] 未设置');
    }

    // 只对特定路径显示详细信息
    if (options.path.contains('rakuen') || options.path.contains('cookie')) {
      if (options.queryParameters.isNotEmpty) {
        debugPrint('   Query: ${options.queryParameters}');
      }
    }
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final path = response.requestOptions.path;
    final statusCode = response.statusCode;

    // 简化日志输出
    if (path.contains('rakuen') ||
        path.contains('timeline') ||
        path.contains('/group/topic') ||
        path.contains('/subject/topic')) {
      debugPrint('✅ $statusCode $path');

      // 只显示数据大小，不显示完整内容
      if (response.data != null) {
        if (response.data is String) {
          final length = (response.data as String).length;
          debugPrint('   HTML/Text: $length bytes');
        } else if (response.data is Map || response.data is List) {
          debugPrint('   JSON: ${response.data.toString().length} bytes');
        }
      }
    } else {
      // 其他请求只显示简要状态
      debugPrint('✓ $statusCode $path');
    }
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint('❌ ${err.type} ${err.requestOptions.path}');
    debugPrint('   ${err.message}');
    // 不显示完整的响应数据和堆栈，避免刷屏
    if (err.response != null) {
      debugPrint('   Status: ${err.response?.statusCode}');
    }
    super.onError(err, handler);
  }
}
