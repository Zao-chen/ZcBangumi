/// Bangumi 用户模型
class BangumiUser {
  final int id;
  final String username;
  final String nickname;
  final UserAvatar avatar;
  final String sign;
  final int userGroup;

  BangumiUser({
    required this.id,
    required this.username,
    required this.nickname,
    required this.avatar,
    required this.sign,
    required this.userGroup,
  });

  factory BangumiUser.fromJson(Map<String, dynamic> json) {
    return BangumiUser(
      id: json['id'] as int,
      username: json['username'] as String,
      nickname: json['nickname'] as String,
      avatar: UserAvatar.fromJson(json['avatar'] as Map<String, dynamic>),
      sign: (json['sign'] as String?) ?? '',
      userGroup: json['user_group'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'nickname': nickname,
        'avatar': avatar.toJson(),
        'sign': sign,
        'user_group': userGroup,
      };
}

/// 用户头像
class UserAvatar {
  final String large;
  final String medium;
  final String small;

  UserAvatar({
    required this.large,
    required this.medium,
    required this.small,
  });

  factory UserAvatar.fromJson(Map<String, dynamic> json) {
    return UserAvatar(
      large: (json['large'] as String?) ?? '',
      medium: (json['medium'] as String?) ?? '',
      small: (json['small'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'large': large,
        'medium': medium,
        'small': small,
      };
}
