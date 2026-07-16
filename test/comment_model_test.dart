import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/models/comment.dart';

void main() {
  group('Comment timestamps', () {
    test('uses createdAt when the private API omits updatedAt', () {
      final comment = Comment.fromJson({
        'id': 1,
        'content': '测试吐槽',
        'createdAt': 1216042657,
        'replies': const [],
        'user': const {'id': 2, 'nickname': '测试用户'},
      });

      expect(comment.createdAt.millisecondsSinceEpoch, 1216042657000);
      expect(comment.updatedAt, comment.createdAt);
    });

    test('recognizes millisecond timestamps without multiplying again', () {
      final comment = Comment.fromJson({
        'created_at': 1760000000123,
        'updated_at': '1760000001123',
      });

      expect(comment.createdAt.millisecondsSinceEpoch, 1760000000123);
      expect(comment.updatedAt.millisecondsSinceEpoch, 1760000001123);
    });

    test(
      'does not turn missing or invalid timestamps into the current time',
      () {
        final comment = Comment.fromJson({
          'created_at': 'not-a-date',
          'updated_at': '',
        });

        expect(comment.createdAt.millisecondsSinceEpoch, 0);
        expect(comment.updatedAt.millisecondsSinceEpoch, 0);
      },
    );
  });

  test('parses and preserves nested replies through cache serialization', () {
    final comment = Comment.fromJson({
      'id': 10,
      'content': '主吐槽',
      'createdAt': 1760000000,
      'user': const {'id': 1, 'nickname': '主楼用户'},
      'replies': [
        {
          'id': 11,
          'content': '楼中楼回复',
          'createdAt': 1760000100,
          'user': const {
            'id': 2,
            'nickname': '回复用户',
            'avatar': {
              'small': 'small.jpg',
              'medium': 'medium.jpg',
              'large': 'large.jpg',
            },
          },
        },
      ],
    });

    expect(comment.replies, 1);
    expect(comment.replyItems.single.id, 11);
    expect(comment.replyItems.single.userName, '回复用户');
    expect(comment.replyItems.single.userAvatar, 'medium.jpg');

    final restored = Comment.fromJson(comment.toJson());
    expect(restored.replies, 1);
    expect(restored.replyItems.single.content, '楼中楼回复');
    expect(
      restored.replyItems.single.createdAt,
      comment.replyItems.single.createdAt,
    );
  });

  test('keeps legacy count-only replies cache compatible', () {
    final comment = Comment.fromJson({'replies': '2'});

    expect(comment.replies, 2);
    expect(comment.replyItems, isEmpty);
    expect(comment.toJson()['replies'], 2);
  });
}
