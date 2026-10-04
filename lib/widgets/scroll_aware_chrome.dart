import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class ScrollChromeData {
  final Animation<double> animation;
  final bool expanded;
  final VoidCallback expand;
  final bool Function(ScrollNotification) handleScrollNotification;
  final bool Function(ScrollMetricsNotification) handleScrollMetrics;
  final ValueChanged<double> handleNativeScroll;

  const ScrollChromeData({
    required this.animation,
    required this.expanded,
    required this.expand,
    required this.handleScrollNotification,
    required this.handleScrollMetrics,
    required this.handleNativeScroll,
  });

  double toolbarHeight(double fullHeight) {
    final compactHeight = fullHeight < 48 ? fullHeight : 48.0;
    return compactHeight + (fullHeight - compactHeight) * animation.value;
  }

  Widget collapse(
    Widget child, {
    Key? key,
    bool fromTop = true,
    Axis axis = Axis.vertical,
    double? fullHeight,
  }) {
    final content = IgnorePointer(
      ignoring: !expanded,
      child: ExcludeFocus(
        excluding: !expanded,
        child: ExcludeSemantics(excluding: !expanded, child: child),
      ),
    );
    final alignedContent = axis == Axis.horizontal
        ? Center(child: content)
        : content;
    final direction = fromTop ? -1.0 : 1.0;
    if (fullHeight != null) {
      return ClipRect(
        child: SizedBox(
          key: key,
          height: fullHeight * animation.value,
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: fullHeight,
            maxHeight: fullHeight,
            child: FractionalTranslation(
              translation: Offset(0, direction * (1 - animation.value)),
              child: content,
            ),
          ),
        ),
      );
    }
    return SizeTransition(
      key: key,
      sizeFactor: animation,
      axis: axis,
      axisAlignment: fromTop ? 1 : -1,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: axis == Axis.vertical
              ? Offset(0, direction)
              : Offset(direction, 0),
          end: Offset.zero,
        ).animate(animation),
        child: alignedContent,
      ),
    );
  }
}

class ScrollChromeCollapse extends StatelessWidget {
  final Widget child;
  final Axis axis;

  const ScrollChromeCollapse({
    super.key,
    required this.child,
    this.axis = Axis.vertical,
  });

  @override
  Widget build(BuildContext context) {
    return ScrollAwareChrome.maybeOf(context)?.collapse(child, axis: axis) ??
        child;
  }
}

class ScrollAwareChrome extends StatelessWidget {
  final Widget Function(BuildContext, ScrollChromeData) builder;
  final Object? resetKey;
  final bool listenToScroll;

  const ScrollAwareChrome({
    super.key,
    required this.builder,
    this.resetKey,
    this.listenToScroll = true,
  });

  static ScrollChromeData? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_ScrollChromeScope>()
        ?.data;
  }

  @override
  Widget build(BuildContext context) {
    final inherited = maybeOf(context);
    if (inherited != null) return builder(context, inherited);
    return _ScrollChromeHost(
      builder: builder,
      resetKey: resetKey,
      listenToScroll: listenToScroll,
    );
  }
}

class _ScrollChromeScope extends InheritedNotifier<Animation<double>> {
  final ScrollChromeData data;

  _ScrollChromeScope({required this.data, required super.child})
    : super(notifier: data.animation);

  @override
  bool updateShouldNotify(covariant _ScrollChromeScope oldWidget) {
    return data.expanded != oldWidget.data.expanded ||
        super.updateShouldNotify(oldWidget);
  }
}

class _ScrollChromeHost extends StatefulWidget {
  final Widget Function(BuildContext, ScrollChromeData) builder;
  final Object? resetKey;
  final bool listenToScroll;

  const _ScrollChromeHost({
    required this.builder,
    required this.resetKey,
    required this.listenToScroll,
  });

  @override
  State<_ScrollChromeHost> createState() => _ScrollChromeHostState();
}

class _ScrollChromeHostState extends State<_ScrollChromeHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _animation;
  bool _expanded = true;
  double _nativeScrollOffset = 0;
  BuildContext? _activeScrollContext;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(covariant _ScrollChromeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey) {
      _expanded = true;
      _nativeScrollOffset = 0;
      _activeScrollContext = null;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _setExpanded(bool expanded) {
    if (_expanded == expanded) return;
    setState(() => _expanded = expanded);
    if (expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle) {
      if (metrics.maxScrollExtent > metrics.minScrollExtent) {
        _activeScrollContext = notification.context;
      }
      final towardTop =
          (notification.direction == ScrollDirection.forward) ==
          (metrics.axisDirection == AxisDirection.down);
      if (towardTop || metrics.maxScrollExtent > metrics.minScrollExtent) {
        _setExpanded(towardTop);
      }
    } else if (notification is ScrollUpdateNotification) {
      final atTop = metrics.axisDirection == AxisDirection.down
          ? metrics.pixels <= metrics.minScrollExtent
          : metrics.pixels >= metrics.maxScrollExtent;
      if (atTop) _setExpanded(true);
    }
    return false;
  }

  bool _handleScrollMetrics(ScrollMetricsNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis == Axis.vertical &&
        notification.context == _activeScrollContext &&
        metrics.maxScrollExtent <= metrics.minScrollExtent) {
      _setExpanded(true);
    }
    return false;
  }

  void _handleNativeScroll(double offset) {
    final delta = offset - _nativeScrollOffset;
    _nativeScrollOffset = offset;
    if (offset <= 0 || delta < 0) {
      _setExpanded(true);
    } else if (delta > 0) {
      _setExpanded(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final data = ScrollChromeData(
          animation: _animation,
          expanded: _expanded,
          expand: () => _setExpanded(true),
          handleScrollNotification: _handleScrollNotification,
          handleScrollMetrics: _handleScrollMetrics,
          handleNativeScroll: _handleNativeScroll,
        );
        return _ScrollChromeScope(
          data: data,
          child: Builder(
            builder: (context) {
              final child = widget.builder(context, data);
              return widget.listenToScroll
                  ? NotificationListener<ScrollNotification>(
                      onNotification: _handleScrollNotification,
                      child: NotificationListener<ScrollMetricsNotification>(
                        onNotification: _handleScrollMetrics,
                        child: child,
                      ),
                    )
                  : child;
            },
          ),
        );
      },
    );
  }
}
