class RakuenTopicDetail {
  final String title;
  final String topicUrl;
  final String? canonicalUrl;
  final String? sourceTitle;
  final String? sourceUrl;
  final String? sectionTitle;
  final String? coverUrl;
  final String? episodeTip;
  final String? episodeDescription;
  final String? replyAuthor;
  final bool canReply;
  final RakuenPost? originalPost;
  final List<RakuenPost> replies;

  const RakuenTopicDetail({
    required this.title,
    required this.topicUrl,
    this.canonicalUrl,
    this.sourceTitle,
    this.sourceUrl,
    this.sectionTitle,
    this.coverUrl,
    this.episodeTip,
    this.episodeDescription,
    this.replyAuthor,
    this.canReply = false,
    this.originalPost,
    required this.replies,
  });
}

class RakuenPost {
  final String id;
  final String floor;
  final String timeText;
  final String username;
  final String nickname;
  final String avatarUrl;
  final String? sign;
  final String content;
  final String? subReplyAction;
  final List<RakuenPost> subReplies;

  const RakuenPost({
    required this.id,
    required this.floor,
    required this.timeText,
    required this.username,
    required this.nickname,
    required this.avatarUrl,
    this.sign,
    required this.content,
    this.subReplyAction,
    this.subReplies = const [],
  });
}
