import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/models/rakuen_topic.dart';
import 'package:zc_bangumi/models/rakuen_topic_favorite.dart';

void main() {
  test('favorite key is derived from canonical topic urls', () {
    const topic = RakuenTopic(
      id: 'manual',
      type: 'group',
      title: 'API',
      topicUrl: 'https://bgm.tv/group/topic/349911',
      avatarUrl: '',
      replyCount: 0,
      timeText: '',
    );

    expect(RakuenFavoriteTopic.keyForTopic(topic), 'group_349911');
  });

  test('cloud document is embedded and parsed from index description', () {
    final now = DateTime.parse('2026-05-20T12:00:00Z');
    final favorite = RakuenFavoriteTopic.fromTopic(
      const RakuenTopic(
        id: 'group_349911',
        type: 'group',
        title: 'API',
        topicUrl: 'https://bgm.tv/group/topic/349911',
        avatarUrl: '',
        replyCount: 3,
        timeText: 'now',
      ),
      now: now,
    );
    final desc = RakuenFavoriteCloudDocument.buildDescription(
      existingDescription: 'intro',
      document: RakuenFavoriteCloudDocument(
        version: 1,
        updatedAt: now,
        items: [favorite],
      ),
    );

    final parsed = RakuenFavoriteCloudDocument.tryParseFromDescription(desc);

    expect(parsed, isNotNull);
    expect(parsed!.items, hasLength(1));
    expect(parsed.items.single.key, 'group_349911');
    expect(desc, contains(rakuenFavoriteBlockStart));
    expect(desc, contains(rakuenFavoriteBlockEnd));
  });
}
