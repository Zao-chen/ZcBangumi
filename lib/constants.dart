/// Bangumi API 常量定义
class BgmConst {
  BgmConst._();

  /// API 基础地址
  static const String apiBaseUrl = 'https://api.bgm.tv';

  /// 网页地址
  static const String webBaseUrl = 'https://bgm.tv';

  /// next.bgm.tv 私有 API 地址（提供 /p1/ 前缀的 JSON API）
  static const String nextBaseUrl = 'https://next.bgm.tv';

  /// User-Agent
  static const String userAgent = 'ZCBangumi/0.1.0 (Flutter App)';

  /// Access Token 获取地址
  static const String tokenUrl = 'https://next.bgm.tv/demo/access-token';

  // ---- 条目类型 ----
  static const int subjectBook = 1;
  static const int subjectAnime = 2;
  static const int subjectMusic = 3;
  static const int subjectGame = 4;
  static const int subjectReal = 6;

  // ---- 收藏类型 ----
  static const int collectionWish = 1;
  static const int collectionDone = 2;
  static const int collectionDoing = 3;
  static const int collectionOnHold = 4;
  static const int collectionDropped = 5;

  // ---- 章节收藏类型 ----
  static const int episodeNotCollected = 0;
  static const int episodeWish = 1;
  static const int episodeDone = 2;
  static const int episodeDropped = 3;

  /// 收藏类型名称（动画语境）
  static String collectionLabel(int type, {int subjectType = subjectAnime}) {
    final bool isBook = subjectType == subjectBook;
    final bool isGame = subjectType == subjectGame;
    switch (type) {
      case collectionWish:
        return isBook ? '想读' : isGame ? '想玩' : '想看';
      case collectionDone:
        return isBook ? '读过' : isGame ? '玩过' : '看过';
      case collectionDoing:
        return isBook ? '在读' : isGame ? '在玩' : '在看';
      case collectionOnHold:
        return '搁置';
      case collectionDropped:
        return '抛弃';
      default:
        return '未知';
    }
  }

  /// 条目类型名称
  static String subjectTypeName(int type) {
    switch (type) {
      case subjectBook:
        return '书籍';
      case subjectAnime:
        return '动画';
      case subjectMusic:
        return '音乐';
      case subjectGame:
        return '游戏';
      case subjectReal:
        return '三次元';
      default:
        return '未知';
    }
  }
}
