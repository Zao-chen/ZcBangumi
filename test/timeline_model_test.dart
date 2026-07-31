import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/models/timeline.dart';

void main() {
  test('daily friend timeline items render as friend additions', () {
    final items = TimelineItem.fromApiJsonList([
      {
        'id': 67877417,
        'uid': 683794,
        'cat': 1,
        'type': 2,
        'memo': {
          'daily': {
            'users': [
              {'username': '811352', 'nickname': '1097'},
              {'username': '827214', 'nickname': '后藤五里'},
            ],
          },
        },
        'createdAt': 1778567362,
        'user': {
          'username': 'tiger1218',
          'nickname': 'Tiger1218',
          'avatar': {'small': '', 'medium': '', 'large': ''},
        },
      },
    ]);

    expect(items, hasLength(1));
    expect(items.single.nickname, 'Tiger1218');
    expect(items.single.actionText, '将');
    expect(items.single.targetText, '1097、后藤五里 加为了好友');
  });

  test('directory timeline keeps index id through cache round-trip', () {
    final item = TimelineItem.fromApiJsonList([
      {
        'id': 1,
        'cat': 7,
        'memo': {
          'index': {'id': 94881, 'title': '测试目录'},
        },
        'createdAt': 100,
        'user': {
          'username': 'tester',
          'nickname': 'Tester',
          'avatar': <String, dynamic>{},
        },
      },
    ]).single;

    expect(item.actionText, '创建了目录');
    expect(item.targetText, '测试目录');
    expect(item.indexId, 94881);
    expect(TimelineItem.fromCacheJson(item.toJson()).indexId, 94881);
    expect(
      TimelineItem.fromCacheJson({
        ...item.toJson(),
        'indexId': '94881',
      }).indexId,
      94881,
    );
  });
}
