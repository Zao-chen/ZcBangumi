import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/models/bangumi_index.dart';
import 'package:zc_bangumi/models/rakuen_topic_favorite.dart';
import 'package:zc_bangumi/services/internal_link_handler.dart';

void main() {
  group('Bangumi index models', () {
    test('parses full index and keeps cache round-trip compatible', () {
      final index = BangumiIndex.fromJson({
        'id': 42,
        'uid': 7,
        'user': {
          'username': 'alice',
          'nickname': 'Alice',
          'avatar': {'medium': 'avatar.jpg'},
        },
        'type': 0,
        'title': '动画目录',
        'desc': '介绍',
        'private': true,
        'total': 9,
        'replies': 2,
        'collects': 3,
        'stats': {
          'subject': {'anime': 4, 'book': 1},
          'character': 2,
          'groupTopic': 1,
        },
        'award': 0,
        'createdAt': 100,
        'updatedAt': 200,
        'collectedAt': 300,
      });

      expect(index.id, 42);
      expect(index.userName, 'Alice');
      expect(index.stats.countFor(IndexRelatedCategory.subject), 5);
      expect(index.stats.character, 2);
      expect(index.isCollected, isTrue);
      expect(index.isPrivate, isTrue);

      final restored = BangumiIndex.fromJson(index.toJson());
      expect(restored.title, index.title);
      expect(restored.description, index.description);
      expect(restored.collectedAt, index.collectedAt);
    });

    test('recognizes protected sync directory by title or description', () {
      final summary = BangumiIndexSummary.fromJson({
        'id': 1,
        'uid': 1,
        'type': 0,
        'title': rakuenFavoriteIndexTitle,
      });
      final detail = BangumiIndex.fromJson({
        'id': 2,
        'uid': 1,
        'type': 0,
        'title': 'renamed',
        'desc': 'data $rakuenFavoriteBlockStart',
      });

      expect(summary.isSystemSyncIndex, isTrue);
      expect(detail.isSystemSyncIndex, isTrue);
      expect(
        rakuenFavoriteIndexCacheKey(' alice '),
        'rakuen_topic_favorite_index_alice',
      );
    });

    test('accepts legacy string booleans and ISO timestamps', () {
      final index = BangumiIndex.fromJson({
        'id': 3,
        'uid': 1,
        'type': 0,
        'title': '旧缓存',
        'private': 'true',
        'createdAt': '2024-01-02T03:04:05Z',
        'updatedAt': '2024-01-03T03:04:05Z',
        'collectedAt': '2024-01-04T03:04:05Z',
      });

      expect(index.isPrivate, isTrue);
      expect(index.createdAt.toUtc().year, 2024);
      expect(index.isCollected, isTrue);
    });

    test('parses every related category and derives navigation URL', () {
      final payloads = <IndexRelatedCategory, Map<String, dynamic>>{
        IndexRelatedCategory.subject: {
          'subject': {'name': 'Subject'},
        },
        IndexRelatedCategory.character: {
          'character': {'name': 'Character'},
        },
        IndexRelatedCategory.person: {
          'person': {'name': 'Person'},
        },
        IndexRelatedCategory.episode: {
          'episode': {'name': 'Episode', 'sort': 3},
        },
        IndexRelatedCategory.blog: {
          'blog': {'title': 'Blog'},
        },
        IndexRelatedCategory.groupTopic: {
          'groupTopic': {'title': 'Group topic'},
        },
        IndexRelatedCategory.subjectTopic: {
          'subjectTopic': {'title': 'Subject topic'},
        },
      };

      for (final entry in payloads.entries) {
        final item = BangumiIndexRelated.fromJson({
          'id': entry.key.value + 1,
          'cat': entry.key.value,
          'rid': 10,
          'sid': 100 + entry.key.value,
          'order': 10,
          'createdAt': 100,
          ...entry.value,
        });
        expect(item.category, entry.key);
        expect(item.title, isNotEmpty);
        expect(item.webUrl, contains('${item.sid}'));
        expect(BangumiIndexRelated.fromJson(item.toJson()).category, entry.key);
      }
    });

    test('renumbers changed related items in stable ten-point steps', () {
      BangumiIndexRelated item(int id, int order) =>
          BangumiIndexRelated.fromJson({
            'id': id,
            'cat': 0,
            'rid': 1,
            'sid': id,
            'order': order,
            'createdAt': 1,
          });

      expect(
        buildBangumiIndexOrderUpdates([item(2, 50), item(1, 10), item(3, 30)]),
        {2: 10, 1: 20},
      );
    });

    test('isolates private-capable caches by viewer account', () {
      expect(
        bangumiIndexDetailCacheKey(42, 'Alice'),
        isNot(bangumiIndexDetailCacheKey(42, 'Bob')),
      );
      expect(
        bangumiIndexRelatedCacheKey(
          42,
          IndexRelatedCategory.subject,
          2,
          ' Alice ',
        ),
        contains('alice'),
      );
      expect(
        bangumiUserIndexesCacheKey(
          targetUsername: 'Alice',
          viewerUsername: 'Bob',
          collected: false,
        ),
        isNot(
          bangumiUserIndexesCacheKey(
            targetUsername: 'Alice',
            viewerUsername: 'Alice',
            collected: false,
          ),
        ),
      );
    });
  });

  group('Bangumi index content links', () {
    final cases = {
      'https://bgm.tv/subject/1': IndexRelatedCategory.subject,
      'https://bangumi.tv/character/2': IndexRelatedCategory.character,
      'https://chii.in/character/2': IndexRelatedCategory.character,
      'bgm.tv/subject/9': IndexRelatedCategory.subject,
      '/person/3': IndexRelatedCategory.person,
      'ep/4': IndexRelatedCategory.episode,
      'https://bgm.tv/blog/5': IndexRelatedCategory.blog,
      'https://bgm.tv/group/topic/6': IndexRelatedCategory.groupTopic,
      'https://bgm.tv/subject/topic/7': IndexRelatedCategory.subjectTopic,
      'https://bgm.tv/rakuen/topic/group/8': IndexRelatedCategory.groupTopic,
    };

    for (final entry in cases.entries) {
      test('parses ${entry.key}', () {
        final result = BangumiIndexContentRef.parse(entry.key);
        expect(result, isNotNull);
        expect(result!.category, entry.value);
        expect(result.id, greaterThan(0));
      });
    }

    test('rejects an unknown link', () {
      expect(BangumiIndexContentRef.parse('https://bgm.tv/user/test'), isNull);
      expect(
        BangumiIndexContentRef.parse('https://example.com/subject/1'),
        isNull,
      );
      expect(
        BangumiIndexContentRef.parse('https://evilbgm.tv/subject/1'),
        isNull,
      );
    });
  });

  test('internal links require an exact Bangumi host boundary', () {
    expect(
      InternalLinkHandler.handleLink(
        Uri.parse('https://bgm.tv/index/1'),
        null,
      ),
      InternalLinkResult.failed,
    );
    expect(
      InternalLinkHandler.handleLink(
        Uri.parse('https://chii.in/index/1'),
        null,
      ),
      InternalLinkResult.failed,
    );
    expect(
      InternalLinkHandler.handleLink(
        Uri.parse('https://evilbgm.tv/index/1'),
        null,
      ),
      InternalLinkResult.openInBrowser,
    );
  });
}
