import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/widgets/bangumi_post_widgets.dart';

void main() {
  test('shared post metadata uses one floor and absolute-time format', () {
    expect(
      formatBangumiPostMeta(
        floorText: '#2',
        dateTime: DateTime(2026, 7, 16, 11, 5),
      ),
      '#2  2026-7-16 11:05',
    );
    expect(
      formatBangumiPostMeta(floorText: '#2-1', rawTime: '2026-07-16 11:06'),
      '#2-1  2026-7-16 11:06',
    );
  });
}
