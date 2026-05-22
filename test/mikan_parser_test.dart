import 'package:flutter_test/flutter_test.dart';
import 'package:zc_bangumi/services/mikan_service.dart';

void main() {
  const baseUrl = 'https://mikanani.me';

  test('extracts login verification token', () {
    const html = '''
      <form id="loginForm" action="/Account/Login">
        <input name="__RequestVerificationToken" value="token-123">
      </form>
    ''';

    expect(MikanHtmlParser.parseLoginToken(html), 'token-123');
  });

  test('parses logged-in user from home page', () {
    const html = '''
      <div id="user-name"><span class="text-right">mikan_user</span></div>
      <div id="user-welcome"><img id="head-pic" src="/images/avatar.png"></div>
      <div id="an-episode-updates"><a class="mikan-rss" href="/RSS/MyBangumi?token=abc"></a></div>
    ''';

    final user = MikanHtmlParser.parseUser(html, baseUrl: baseUrl);

    expect(user, isNotNull);
    expect(user!.name, 'mikan_user');
    expect(user.avatar, 'https://mikanani.me/images/avatar.png');
    expect(user.rss, 'https://mikanani.me/RSS/MyBangumi?token=abc');
  });

  test('parses search bangumi candidates and records', () {
    const html = '''
      <div class="leftbar-container">
        <div class="leftbar-item"><span class="subgroup-longname" data-subgroupid="12">字幕组</span></div>
      </div>
      <div class="central-container">
        <ul>
          <li>
            <a href="/Home/Bangumi/681"><span data-src="/images/681.jpg?x=1"></span></a>
            <span class="an-text" title="测试动画"></span>
          </li>
        </ul>
      </div>
      <table>
        <tr class="js-search-results-row">
          <td></td>
          <td><a href="/Home/Episode/1">[字幕组] 测试动画 [GB][1080P][MP4]</a></td>
          <td>300MB</td>
          <td>1月1日 12:00</td>
          <td><a href="/Download/1.torrent">种子</a></td>
        </tr>
      </table>
    ''';

    final result = MikanHtmlParser.parseSearch(html, baseUrl: baseUrl);

    expect(result.subgroups.single.id, '12');
    expect(result.bangumis.single.id, '681');
    expect(result.bangumis.single.name, '测试动画');
    expect(
      result.records.single.torrent,
      'https://mikanani.me/Download/1.torrent',
    );
    expect(result.records.single.tags, containsAll(['简', '1080P', 'MP4']));
  });

  test('parses bangumi detail, subgroup records, and Bangumi subject id', () {
    const html = '''
      <div id="sk-container">
        <div class="pull-left leftbar-container">
          <p class="bangumi-title"><a href="/Home/Bangumi?bangumiId=681">测试动画</a></p>
          <div class="bangumi-poster" style="background-image:url('/images/poster.jpg')"></div>
          <p class="bangumi-info">番组计划链接：<a href="https://bgm.tv/subject/12345">Bangumi</a></p>
        </div>
        <div class="central-container">
          <p>简介</p>
          <div class="episode-table">
            <div id="15" class="subgroup-text">
              <a href="/Home/PublishGroup/15" target="_blank" style="color: #3bc0c3;">清蓝字幕组</a>
              <a class="mikan-rss" href="/RSS/Bangumi?bangumiId=681&subgroupid=15"></a>
              <span class="subscribed">简中</span>
            </div>
            <table>
              <tbody>
                <tr>
                  <td><input data-magnet="magnet:?xt=urn:btih:test123"></td>
                  <td><a class="magnet-link-wrap" href="/Home/Episode/1">[清蓝字幕组] 测试动画 [GB][720P]</a></td>
                  <td>300MB</td>
                  <td>1月1日 12:00</td>
                  <td><a href="/Download/1.torrent">种子</a></td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    ''';

    final detail = MikanHtmlParser.parseBangumi(
      html,
      baseUrl: baseUrl,
      fallbackId: '681',
    );

    expect(detail.id, '681');
    expect(detail.bangumiSubjectId, 12345);
    expect(detail.subgroupBangumis.single.dataId, '15');
    expect(detail.subgroupBangumis.single.name, '清蓝字幕组');
    expect(
      detail.subgroupBangumis.single.records.single.magnet,
      'magnet:?xt=urn:btih:test123',
    );
  });

  test('parses real Mikan subgroup names from publish-group links', () {
    const html = '''
      <div id="sk-container">
        <div class="pull-left leftbar-container">
          <p class="bangumi-title"><a href="/Home/Bangumi?bangumiId=3927">一叠间漫画咖啡屋生活！</a></p>
          <p class="bangumi-info">番组计划链接：<a href="https://bgm.tv/subject/569161">Bangumi</a></p>
        </div>
        <div class="central-container">
          <div class="episode-table">
            <div class="subgroup-text" id="615">
              <a href="/Home/PublishGroup/392" target="_blank" style="color: #3bc0c3;">Kirara Fantasia</a>
              <a href="/RSS/Bangumi?bangumiId=3927&subgroupid=615" class="mikan-rss"><i class="fa fa-rss-square"></i></a>
              <span class="subscribed" style="display:none;">已订阅</span>
            </div>
            <table><tbody><tr><td></td><td><a class="magnet-link-wrap">KF 04</a></td><td>100MB</td><td>now</td><td></td></tr></tbody></table>
          </div>
          <div class="episode-table">
            <div class="subgroup-text" id="382">
              <a href="/Home/PublishGroup/233" target="_blank" style="color: #3bc0c3;">喵萌奶茶屋</a>
              <a href="/RSS/Bangumi?bangumiId=3927&subgroupid=382" class="mikan-rss"><i class="fa fa-rss-square"></i></a>
              <span class="subscribed">简中</span>
            </div>
            <table><tbody><tr><td></td><td><a class="magnet-link-wrap">MM 04</a></td><td>100MB</td><td>now</td><td></td></tr></tbody></table>
          </div>
        </div>
      </div>
    ''';

    final detail = MikanHtmlParser.parseBangumi(
      html,
      baseUrl: baseUrl,
      fallbackId: '3927',
    );

    expect(detail.subgroupBangumis.map((item) => item.name), [
      'Kirara Fantasia',
      '喵萌奶茶屋',
    ]);
    expect(detail.subgroupBangumis.first.subscribed, isFalse);
    expect(detail.subgroupBangumis.first.sublang, isEmpty);
    expect(detail.subgroupBangumis.last.subscribed, isTrue);
    expect(detail.subgroupBangumis.last.sublang, '简中');
    expect(detail.bangumiSubjectId, 569161);
  });
}
