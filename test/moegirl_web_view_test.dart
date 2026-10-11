import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zc_bangumi/pages/moegirl_web_view.dart';

void main() {
  final searchUri = Uri.https('zh.moegirl.org.cn', '/index.php', {
    'search': '芙莉莲',
  });
  final articleUri = WebUri('https://zh.moegirl.org.cn/葬送的芙莉莲');
  late _FakeController platformController;
  late InAppWebViewController controller;
  late InAppWebViewPlatform originalPlatform;
  late _FakeWebViewPlatform platform;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    originalPlatform = InAppWebViewPlatform.instance ?? _FakeWebViewPlatform();
    platform = _FakeWebViewPlatform();
    InAppWebViewPlatform.instance = platform;
    platformController = _FakeController();
    controller = InAppWebViewController.fromPlatform(
      platform: platformController,
    );
  });

  tearDown(() => InAppWebViewPlatform.instance = originalPlatform);

  Future<PlatformInAppWebViewWidgetCreationParams> showReader(
    WidgetTester tester, {
    int subjectId = 1,
    bool isActive = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MoegirlWebView(
            subjectId: subjectId,
            initialUri: searchUri,
            isActive: isActive,
          ),
        ),
      ),
    );
    await tester.pump();
    final params = tester
        .widget<InAppWebView>(find.byType(InAppWebView))
        .platform
        .params;
    params.onWebViewCreated!(controller);
    return params;
  }

  testWidgets('loads the original URL without reconstructed HTML or scripts', (
    tester,
  ) async {
    final params = await showReader(tester);
    expect(params.initialUrlRequest!.url!.uriValue, searchUri);
    expect(params.initialData, isNull);
    expect(params.initialUserScripts, isNull);
    expect(params.initialSettings!.javaScriptEnabled, isTrue);
    expect(params.initialSettings!.userAgent, isEmpty);
  });

  testWidgets(
    'restores per-subject selection before legacy keyword selection',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'moegirl_subject_1': articleUri.toString(),
        'moegirl_selection_芙莉莲': 'https://zh.moegirl.org.cn/芙莉莲',
        'moegirl_subject_2': 'https://zh.moegirl.org.cn/葬送的芙莉莲#动画版',
      });
      final first = await showReader(tester);
      expect(first.initialUrlRequest!.url!.uriValue, articleUri.uriValue);
      final second = await showReader(tester, subjectId: 2);
      expect(
        Uri.decodeComponent(second.initialUrlRequest!.url!.uriValue.fragment),
        '动画版',
      );
      final legacy = await showReader(tester, subjectId: 3);
      expect(legacy.initialUrlRequest!.url!.uriValue.pathSegments, ['芙莉莲']);
    },
  );

  testWidgets('ignores saved URLs outside the original site', (tester) async {
    SharedPreferences.setMockInitialValues({
      'moegirl_subject_1': 'https://zh.moegirl.org.cn.example.com/fake',
    });
    final params = await showReader(tester);
    expect(params.initialUrlRequest!.url!.uriValue, searchUri);
  });

  testWidgets(
    'keeps article links, anchors and embedded frames in the webview',
    (tester) async {
      final params = await showReader(tester);
      for (final url in [
        articleUri,
        WebUri('${articleUri.toString()}#cite_note-1'),
      ]) {
        expect(
          await params.shouldOverrideUrlLoading!(
            controller,
            NavigationAction(
              request: URLRequest(url: url),
              isForMainFrame: true,
            ),
          ),
          NavigationActionPolicy.ALLOW,
        );
      }
      expect(
        await params.shouldOverrideUrlLoading!(
          controller,
          NavigationAction(
            request: URLRequest(url: WebUri('https://example.com/embedded')),
            isForMainFrame: false,
          ),
        ),
        NavigationActionPolicy.ALLOW,
      );
      expect(
        await params.shouldOverrideUrlLoading!(
          controller,
          NavigationAction(
            request: URLRequest(url: WebUri('file:///tmp/test.html')),
            isForMainFrame: true,
          ),
        ),
        NavigationActionPolicy.CANCEL,
      );
      expect(
        await params.onCreateWindow!(
          controller,
          CreateWindowAction(
            windowId: 1,
            request: URLRequest(url: articleUri),
            isForMainFrame: true,
          ),
        ),
        isFalse,
      );
      expect(platformController.loadedUrls, [articleUri]);
    },
  );

  testWidgets('only the active reader consumes back navigation', (
    tester,
  ) async {
    final params = await showReader(tester);
    platformController.back = true;
    params.onLoadStop!(controller, articleUri);
    await tester.pump();
    var scope = tester.widget<PopScope<Object?>>(
      find.byType(PopScope<Object?>),
    );
    expect(scope.canPop, isFalse);
    await tester.tap(find.byTooltip('网页后退'));
    expect(platformController.backCalls, 1);

    await showReader(tester, isActive: false);
    scope = tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>));
    expect(scope.canPop, isTrue);
    scope.onPopInvokedWithResult!(false, null);
    expect(platformController.backCalls, 1);
  });

  testWidgets('fullscreen retains the webview and closes before web history', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final inline = await showReader(tester);
    final keepAlive = inline.keepAlive;
    expect(keepAlive, isNotNull);
    platformController.back = true;
    inline.onLoadStop!(controller, articleUri);
    await tester.pump();

    for (final useSystemBack in [false, true]) {
      await tester.tap(find.byTooltip('全屏查看'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('退出全屏'), findsOneWidget);
      expect(find.byTooltip('全屏查看'), findsNothing);
      expect(find.byType(InAppWebView, skipOffstage: false), findsOneWidget);
      final fullscreen = tester
          .widget<InAppWebView>(find.byType(InAppWebView))
          .platform
          .params;
      expect(fullscreen.keepAlive, same(keepAlive));
      fullscreen.onWebViewCreated!(controller);
      fullscreen.onLoadStop!(controller, articleUri);
      await tester.pump();
      await tester.tap(find.byTooltip('萌百选项'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('记住当前条目'));
      await tester.pumpAndSettle();
      expect(find.text('已记住此作品的萌百条目'), findsOneWidget);

      if (useSystemBack) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.byTooltip('退出全屏'));
      }
      await tester.pumpAndSettle();
      expect(find.byTooltip('退出全屏'), findsNothing);
      expect(find.byTooltip('全屏查看'), findsOneWidget);
      expect(find.byType(InAppWebView, skipOffstage: false), findsOneWidget);
      final restored = tester
          .widget<InAppWebView>(find.byType(InAppWebView))
          .platform
          .params;
      expect(restored.keepAlive, same(keepAlive));
      restored.onWebViewCreated!(controller);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(platformController.loadedUrls, isEmpty);
      expect(platformController.reloadCalls, 0);
      expect(platformController.backCalls, 0);
      expect(platform.staticController.disposedKeepAlives, isEmpty);
      expect(
        tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>)).canPop,
        isFalse,
      );
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(platform.staticController.disposedKeepAlives, [keepAlive]);
  });

  testWidgets('subresource and cancelled errors do not cover the page', (
    tester,
  ) async {
    final params = await showReader(tester);
    params.onLoadStart!(controller, articleUri);
    params.onReceivedError!(
      controller,
      WebResourceRequest(url: articleUri, isForMainFrame: false),
      WebResourceError(
        type: WebResourceErrorType.HOST_LOOKUP,
        description: 'image failed',
      ),
    );
    params.onReceivedError!(
      controller,
      WebResourceRequest(url: articleUri, isForMainFrame: true),
      WebResourceError(
        type: WebResourceErrorType.CANCELLED,
        description: 'cancelled',
      ),
    );
    await tester.pump();
    expect(find.text('重试'), findsNothing);

    params.onReceivedError!(
      controller,
      WebResourceRequest(url: articleUri, isForMainFrame: true),
      WebResourceError(
        type: WebResourceErrorType.HOST_LOOKUP,
        description: 'failed',
      ),
    );
    await tester.pump();
    expect(find.text('重试'), findsOneWidget);
    expect(find.byType(InAppWebView), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(platformController.reloadCalls, 1);
    params.onLoadStart!(controller, articleUri);
    params.onLoadStop!(controller, articleUri);
    await tester.pump();
    expect(find.text('重试'), findsNothing);
  });

  testWidgets(
    'remembers an explicit selection without overwriting it while browsing',
    (tester) async {
      final params = await showReader(tester);
      params.onLoadStop!(controller, articleUri);
      await tester.pump();
      await tester.tap(find.byTooltip('萌百选项'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('记住当前条目'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('moegirl_subject_1'), articleUri.toString());

      params.onLoadStop!(controller, WebUri('https://zh.moegirl.org.cn/芙莉莲'));
      await tester.pump();
      expect(prefs.getString('moegirl_subject_1'), articleUri.toString());
      await tester.tap(find.byTooltip('萌百选项'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新搜索'));
      await tester.pumpAndSettle();
      expect(platformController.loadedUrls.single!.uriValue, searchUri);
    },
  );
}

class _FakeWebViewPlatform extends InAppWebViewPlatform {
  final staticController = _FakeController();

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewControllerStatic() =>
      staticController;

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _FakeWebViewWidget(params);
}

class _FakeWebViewWidget extends PlatformInAppWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;

  @override
  void dispose() {}
}

class _FakeController extends PlatformInAppWebViewController {
  _FakeController()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 1),
      );
  bool back = false;
  int backCalls = 0;
  int reloadCalls = 0;
  final loadedUrls = <WebUri?>[];
  final disposedKeepAlives = <InAppWebViewKeepAlive>[];

  @override
  Future<void> disposeKeepAlive(InAppWebViewKeepAlive keepAlive) async {
    disposedKeepAlives.add(keepAlive);
  }

  @override
  Future<bool> canGoBack() async => back;

  @override
  Future<bool> canGoForward() async => false;

  @override
  Future<void> goBack() async => backCalls++;

  @override
  Future<void> reload() async => reloadCalls++;

  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    Uri? iosAllowingReadAccessTo,
    WebUri? allowingReadAccessTo,
  }) async {
    loadedUrls.add(urlRequest.url);
  }
}
