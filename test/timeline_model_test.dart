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
}
