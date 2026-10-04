import 'package:flutter/material.dart';

import 'scroll_aware_chrome.dart';

export 'scroll_aware_chrome.dart';

class ScrollAwareScaffold extends StatelessWidget {
  final AppBar? appBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor;
  final bool? resizeToAvoidBottomInset;
  final Object? resetKey;

  const ScrollAwareScaffold({
    super.key,
    this.appBar,
    this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
    this.resetKey,
  });

  @override
  Widget build(BuildContext context) {
    return ScrollAwareChrome(
      resetKey: resetKey,
      builder: (context, chrome) => Scaffold(
        appBar: appBar == null
            ? null
            : _compactAppBar(context, appBar!, chrome),
        body: body,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        backgroundColor: backgroundColor,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      ),
    );
  }

  AppBar _compactAppBar(
    BuildContext context,
    AppBar source,
    ScrollChromeData chrome,
  ) {
    final fullHeight =
        source.toolbarHeight ??
        AppBarTheme.of(context).toolbarHeight ??
        kToolbarHeight;
    final bottom = source.bottom;
    return AppBar(
      key: source.key,
      leading: source.leading,
      automaticallyImplyLeading: source.automaticallyImplyLeading,
      title: source.title,
      actions: source.actions,
      automaticallyImplyActions: source.automaticallyImplyActions,
      flexibleSpace: source.flexibleSpace,
      bottom: bottom == null
          ? null
          : PreferredSize(
              preferredSize: Size.fromHeight(
                bottom.preferredSize.height * chrome.animation.value,
              ),
              child: chrome.collapse(
                bottom,
                fullHeight: bottom.preferredSize.height,
              ),
            ),
      elevation: source.elevation,
      scrolledUnderElevation: source.scrolledUnderElevation,
      notificationPredicate: source.notificationPredicate,
      shadowColor: source.shadowColor,
      surfaceTintColor: source.surfaceTintColor,
      shape: source.shape,
      backgroundColor: source.backgroundColor,
      foregroundColor: source.foregroundColor,
      iconTheme: source.iconTheme,
      actionsIconTheme: source.actionsIconTheme,
      primary: source.primary,
      centerTitle: source.centerTitle,
      excludeHeaderSemantics: source.excludeHeaderSemantics,
      titleSpacing: source.titleSpacing,
      toolbarOpacity: source.toolbarOpacity,
      bottomOpacity: source.bottomOpacity,
      toolbarHeight: chrome.toolbarHeight(fullHeight),
      leadingWidth: source.leadingWidth,
      toolbarTextStyle: source.toolbarTextStyle,
      titleTextStyle: source.titleTextStyle,
      systemOverlayStyle: source.systemOverlayStyle,
      forceMaterialTransparency: source.forceMaterialTransparency,
      useDefaultSemanticsOrder: source.useDefaultSemanticsOrder,
      clipBehavior: source.clipBehavior,
      actionsPadding: source.actionsPadding,
      animateColor: source.animateColor,
    );
  }
}
