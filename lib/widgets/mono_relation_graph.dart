import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

enum MonoRelationViewMode { list, graph }

typedef MonoRelationNodeLoader = Future<List<MonoRelationGraphNode>> Function();

class MonoRelationGraphNode {
  final String key;
  final String relation;
  final String title;
  final String subtitle;
  final String imageUrl;
  final IconData placeholderIcon;
  final VoidCallback? onTap;
  final MonoRelationNodeLoader? loadChildren;

  const MonoRelationGraphNode({
    required this.key,
    required this.relation,
    required this.title,
    this.subtitle = '',
    this.imageUrl = '',
    this.placeholderIcon = Icons.circle_outlined,
    this.onTap,
    this.loadChildren,
  });
}

class MonoRelationViewSwitcher extends StatelessWidget {
  final MonoRelationViewMode mode;
  final ValueChanged<MonoRelationViewMode> onModeChanged;
  final int itemCount;
  final Widget listView;
  final Widget graphView;

  const MonoRelationViewSwitcher({
    super.key,
    required this.mode,
    required this.onModeChanged,
    required this.itemCount,
    required this.listView,
    required this.graphView,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Text(
                '$itemCount 项',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              SegmentedButton<MonoRelationViewMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: MonoRelationViewMode.list,
                    icon: Icon(Icons.view_list_outlined, size: 18),
                    label: Text('列表'),
                  ),
                  ButtonSegment(
                    value: MonoRelationViewMode.graph,
                    icon: Icon(Icons.account_tree_outlined, size: 18),
                    label: Text('脑图'),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (selection) {
                  if (selection.isNotEmpty) onModeChanged(selection.first);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: mode == MonoRelationViewMode.list ? 0 : 1,
            children: [listView, graphView],
          ),
        ),
      ],
    );
  }
}

class MonoRelationGraph extends StatefulWidget {
  final String graphId;
  final String centerTitle;
  final String centerSubtitle;
  final String centerImageUrl;
  final IconData centerPlaceholderIcon;
  final List<MonoRelationGraphNode> nodes;
  final int autoCollapseRootThreshold;
  final int autoCollapseRootRelationGroupThreshold;
  final int autoCollapseChildThreshold;
  final int autoCollapseRelationGroupThreshold;
  final _RelationGraphSession? _session;
  final bool _showFullscreenButton;

  const MonoRelationGraph({
    super.key,
    required this.graphId,
    required this.centerTitle,
    this.centerSubtitle = '',
    this.centerImageUrl = '',
    this.centerPlaceholderIcon = Icons.hub_outlined,
    required this.nodes,
    this.autoCollapseRootThreshold = 36,
    this.autoCollapseRootRelationGroupThreshold = 10,
    this.autoCollapseChildThreshold = 18,
    this.autoCollapseRelationGroupThreshold = 6,
  }) : _session = null,
       _showFullscreenButton = true;

  const MonoRelationGraph._shared({
    required this.graphId,
    required this.centerTitle,
    required this.centerSubtitle,
    required this.centerImageUrl,
    required this.centerPlaceholderIcon,
    required this.nodes,
    required this.autoCollapseRootThreshold,
    required this.autoCollapseRootRelationGroupThreshold,
    required this.autoCollapseChildThreshold,
    required this.autoCollapseRelationGroupThreshold,
    required _RelationGraphSession session,
  }) : _session = session,
       _showFullscreenButton = false;

  @override
  State<MonoRelationGraph> createState() => _MonoRelationGraphState();
}

class _MonoRelationGraphState extends State<MonoRelationGraph> {
  static const double _minScale = 0.04;
  static const double _maxScale = 2.4;
  static const double _fitPadding = 20;

  final TransformationController _transformController =
      TransformationController();
  late _RelationGraphSession _session;
  late bool _ownsSession;
  Size? _lastViewportSize;
  _RelationGraphLayout? _lastLayout;
  bool _fitScheduled = false;

  Map<String, List<MonoRelationGraphNode>> get _loadedChildren =>
      _session.loadedChildren;
  Set<String> get _expandedNodeKeys => _session.expandedNodeKeys;
  Set<String> get _loadingNodeKeys => _session.loadingNodeKeys;
  Set<String> get _failedNodeKeys => _session.failedNodeKeys;
  Set<String> get _collapsedRelationKeys => _session.collapsedRelationKeys;
  Set<String> get _expandedRelationKeys => _session.expandedRelationKeys;
  Set<String> get _autoCollapsedParentNodeKeys =>
      _session.autoCollapsedParentNodeKeys;

  @override
  void initState() {
    super.initState();
    _attachSession(widget._session);
  }

  @override
  void didUpdateWidget(covariant MonoRelationGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._session != widget._session) {
      _detachSession();
      _attachSession(widget._session);
    }
    if (oldWidget.graphId != widget.graphId) {
      _session.reset();
      _transformController.value = Matrix4.identity();
      _scheduleFit();
    }
  }

  @override
  void dispose() {
    _detachSession();
    _transformController.dispose();
    super.dispose();
  }

  void _attachSession(_RelationGraphSession? sharedSession) {
    _ownsSession = sharedSession == null;
    _session = sharedSession ?? _RelationGraphSession();
    _session.addListener(_handleSessionChanged);
  }

  void _detachSession() {
    _session.removeListener(_handleSessionChanged);
    if (_ownsSession) _session.dispose();
  }

  void _handleSessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final layout = _buildLayout();
    _lastLayout = layout;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 800,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 600,
        );
        final viewportChanged = _lastViewportSize != viewportSize;
        _lastViewportSize = viewportSize;
        if (viewportChanged) _scheduleFit();

        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                onPointerSignal: _handlePointerSignal,
                child: InteractiveViewer(
                  transformationController: _transformController,
                  minScale: _minScale,
                  maxScale: _maxScale,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  child: SizedBox(
                    width: layout.size.width,
                    height: layout.size.height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _RelationGraphLinePainter(
                              edges: layout.edges,
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                        for (final node in layout.nodes)
                          Positioned.fromRect(
                            rect: node.rect,
                            child: _buildPositionedNode(node),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    tooltip: '适应画布',
                    onPressed: _fitToViewport,
                    icon: const Icon(Icons.fit_screen_outlined),
                  ),
                  if (widget._showFullscreenButton) ...[
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      tooltip: '全屏查看',
                      onPressed: _openFullscreen,
                      icon: const Icon(Icons.fullscreen_rounded),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPositionedNode(_PositionedGraphNode positioned) {
    return switch (positioned.kind) {
      _GraphNodeKind.center => _buildCenterNode(),
      _GraphNodeKind.relation => _buildRelationNode(positioned),
      _GraphNodeKind.entity => _buildEntityNode(positioned),
    };
  }

  Future<void> _openFullscreen() async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _MonoRelationFullscreenPage(
          title: widget.centerTitle,
          graph: MonoRelationGraph._shared(
            graphId: widget.graphId,
            centerTitle: widget.centerTitle,
            centerSubtitle: widget.centerSubtitle,
            centerImageUrl: widget.centerImageUrl,
            centerPlaceholderIcon: widget.centerPlaceholderIcon,
            nodes: widget.nodes,
            autoCollapseRootThreshold: widget.autoCollapseRootThreshold,
            autoCollapseRootRelationGroupThreshold:
                widget.autoCollapseRootRelationGroupThreshold,
            autoCollapseChildThreshold: widget.autoCollapseChildThreshold,
            autoCollapseRelationGroupThreshold:
                widget.autoCollapseRelationGroupThreshold,
            session: _session,
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {});
    _scheduleFit();
  }

  Widget _buildCenterNode() {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            _GraphImage(
              imageUrl: widget.centerImageUrl,
              placeholderIcon: widget.centerPlaceholderIcon,
              width: 44,
              height: 56,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.centerTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.centerSubtitle.isEmpty
                        ? '${widget.nodes.length} 项关联'
                        : widget.centerSubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.75,
                      ),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRelationNode(_PositionedGraphNode positioned) {
    final colorScheme = Theme.of(context).colorScheme;
    final collapsed = positioned.relationCollapsed;
    return Material(
      color: colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          _session.mutate(() {
            if (collapsed) {
              _collapsedRelationKeys.remove(positioned.relationKey);
              _expandedRelationKeys.add(positioned.relationKey!);
            } else {
              _expandedRelationKeys.remove(positioned.relationKey);
              _collapsedRelationKeys.add(positioned.relationKey!);
            }
          });
          _scheduleFit();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  positioned.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                collapsed
                    ? Icons.add_circle_outline
                    : Icons.remove_circle_outline,
                size: 15,
                color: colorScheme.onSecondaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntityNode(_PositionedGraphNode positioned) {
    final node = positioned.entity!;
    final colorScheme = Theme.of(context).colorScheme;
    final loading = _loadingNodeKeys.contains(node.key);
    final failed = _failedNodeKeys.contains(node.key);
    final expanded = _expandedNodeKeys.contains(node.key);
    final expandable = node.loadChildren != null;

    final expandButton = expandable
        ? SizedBox(
            width: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              tooltip: expanded ? '收起' : (failed ? '重试展开' : '展开'),
              onPressed: loading ? null : () => _toggleNode(node),
              icon: loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      failed
                          ? Icons.refresh_rounded
                          : expanded
                          ? Icons.remove_circle_outline
                          : Icons.add_circle_outline,
                      size: 17,
                    ),
            ),
          )
        : const SizedBox.shrink();

    return Material(
      color: colorScheme.surfaceContainerLow,
      elevation: 1,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: node.onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              if (positioned.side == _GraphSide.left) expandButton,
              _GraphImage(
                imageUrl: node.imageUrl,
                placeholderIcon: node.placeholderIcon,
                width: 40,
                height: 54,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    if (node.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        node.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (positioned.side == _GraphSide.right) expandButton,
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleNode(MonoRelationGraphNode node) async {
    if (_expandedNodeKeys.contains(node.key)) {
      _session.mutate(() => _expandedNodeKeys.remove(node.key));
      _scheduleFit();
      return;
    }

    if (!_loadedChildren.containsKey(node.key)) {
      _session.mutate(() {
        _loadingNodeKeys.add(node.key);
        _failedNodeKeys.remove(node.key);
      });
      try {
        final children = await node.loadChildren!();
        if (!mounted) return;
        final relationGroupCount = children
            .map(
              (child) =>
                  child.relation.trim().isEmpty ? '其他' : child.relation.trim(),
            )
            .toSet()
            .length;
        final shouldAutoCollapse =
            children.length >= widget.autoCollapseChildThreshold ||
            relationGroupCount >= widget.autoCollapseRelationGroupThreshold;
        _session.mutate(() {
          _loadedChildren[node.key] = children;
          _expandedNodeKeys.add(node.key);
          _loadingNodeKeys.remove(node.key);
          if (shouldAutoCollapse) {
            _autoCollapsedParentNodeKeys.add(node.key);
          } else {
            _autoCollapsedParentNodeKeys.remove(node.key);
          }
        });
      } catch (_) {
        if (!mounted) return;
        _session.mutate(() {
          _loadingNodeKeys.remove(node.key);
          _failedNodeKeys.add(node.key);
        });
      }
    } else {
      _session.mutate(() => _expandedNodeKeys.add(node.key));
    }
    _scheduleFit();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _lastViewportSize == null) return;
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final factor = math.exp(-event.scrollDelta.dy * 0.0015);
    final nextScale = (currentScale * factor).clamp(_minScale, _maxScale);
    final focalScene = _transformController.toScene(event.localPosition);
    final matrix = Matrix4.identity()
      ..translateByDouble(event.localPosition.dx, event.localPosition.dy, 0, 1)
      ..scaleByDouble(nextScale, nextScale, nextScale, 1)
      ..translateByDouble(-focalScene.dx, -focalScene.dy, 0, 1);
    _transformController.value = matrix;
  }

  void _scheduleFit() {
    if (_fitScheduled) return;
    _fitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitScheduled = false;
      if (mounted) _fitToViewport();
    });
  }

  void _fitToViewport() {
    final viewport = _lastViewportSize;
    final layout = _lastLayout;
    if (viewport == null || layout == null) return;
    final availableWidth = math.max(1.0, viewport.width - _fitPadding * 2);
    final availableHeight = math.max(1.0, viewport.height - _fitPadding * 2);
    final scale = math
        .min(
          availableWidth / layout.size.width,
          availableHeight / layout.size.height,
        )
        .clamp(_minScale, 1.0);
    final tx = (viewport.width - layout.size.width * scale) / 2;
    final ty = (viewport.height - layout.size.height * scale) / 2;
    _transformController.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  _RelationGraphLayout _buildLayout() {
    const centerSize = Size(170, 76);
    const relationSize = Size(126, 40);
    const entitySize = Size(196, 72);
    const horizontalGap = 48.0;
    const verticalGap = 14.0;
    const groupGap = 24.0;
    const canvasPadding = 64.0;

    final rootRelationGroupCount = widget.nodes
        .map(
          (node) => node.relation.trim().isEmpty ? '其他' : node.relation.trim(),
        )
        .toSet()
        .length;
    final shouldAutoCollapseRoots =
        widget.nodes.length >= widget.autoCollapseRootThreshold ||
        rootRelationGroupCount >= widget.autoCollapseRootRelationGroupThreshold;
    final rootGroups = _groupNodes(
      widget.nodes,
      path: widget.graphId,
      ancestors: const {},
      defaultCollapsed: shouldAutoCollapseRoots,
    );
    final left = <_GraphRelationBranch>[];
    final right = <_GraphRelationBranch>[];
    var leftHeight = 0.0;
    var rightHeight = 0.0;
    for (final group in rootGroups) {
      final height = _groupHeight(
        group,
        relationSize: relationSize,
        entitySize: entitySize,
        verticalGap: verticalGap,
        groupGap: groupGap,
      );
      if (leftHeight <= rightHeight) {
        left.add(group);
        leftHeight += height + groupGap;
      } else {
        right.add(group);
        rightHeight += height + groupGap;
      }
    }

    final contentHeight = math.max(
      centerSize.height,
      math.max(
        math.max(0, leftHeight - groupGap),
        math.max(0, rightHeight - groupGap),
      ),
    );
    final centerRect = Rect.fromCenter(
      center: Offset(0, contentHeight / 2),
      width: centerSize.width,
      height: centerSize.height,
    );
    final nodes = <_PositionedGraphNode>[
      _PositionedGraphNode(
        kind: _GraphNodeKind.center,
        rect: centerRect,
        label: widget.centerTitle,
        side: _GraphSide.none,
      ),
    ];
    final edges = <_GraphEdge>[];

    void layoutSide(List<_GraphRelationBranch> groups, _GraphSide side) {
      final totalHeight =
          groups.fold<double>(0, (sum, group) {
            return sum +
                _groupHeight(
                  group,
                  relationSize: relationSize,
                  entitySize: entitySize,
                  verticalGap: verticalGap,
                  groupGap: groupGap,
                );
          }) +
          math.max(0, groups.length - 1) * groupGap;
      var cursorY = (contentHeight - totalHeight) / 2;
      for (final group in groups) {
        final height = _groupHeight(
          group,
          relationSize: relationSize,
          entitySize: entitySize,
          verticalGap: verticalGap,
          groupGap: groupGap,
        );
        _layoutGroup(
          group: group,
          side: side,
          top: cursorY,
          anchorRect: centerRect,
          nodes: nodes,
          edges: edges,
          relationSize: relationSize,
          entitySize: entitySize,
          horizontalGap: horizontalGap,
          verticalGap: verticalGap,
          groupGap: groupGap,
        );
        cursorY += height + groupGap;
      }
    }

    layoutSide(left, _GraphSide.left);
    layoutSide(right, _GraphSide.right);

    var bounds = centerRect;
    for (final node in nodes.skip(1)) {
      bounds = bounds.expandToInclude(node.rect);
    }
    final shift = Offset(
      canvasPadding - bounds.left,
      canvasPadding - bounds.top,
    );
    return _RelationGraphLayout(
      size: Size(
        bounds.width + canvasPadding * 2,
        bounds.height + canvasPadding * 2,
      ),
      nodes: nodes.map((node) => node.shift(shift)).toList(),
      edges: edges.map((edge) => edge.shift(shift)).toList(),
    );
  }

  List<_GraphRelationBranch> _groupNodes(
    List<MonoRelationGraphNode> nodes, {
    required String path,
    required Set<String> ancestors,
    bool defaultCollapsed = false,
  }) {
    final grouped = <String, List<MonoRelationGraphNode>>{};
    for (final node in nodes) {
      if (ancestors.contains(node.key)) continue;
      final relation = node.relation.trim().isEmpty
          ? '其他'
          : node.relation.trim();
      grouped.putIfAbsent(relation, () => []).add(node);
    }
    return grouped.entries.map((entry) {
      final relationKey = '$path::${entry.key}';
      return _GraphRelationBranch(
        key: relationKey,
        label: entry.key,
        collapsed:
            _collapsedRelationKeys.contains(relationKey) ||
            (defaultCollapsed && !_expandedRelationKeys.contains(relationKey)),
        entities: entry.value.map((node) {
          final nextAncestors = {...ancestors, node.key};
          final children = _expandedNodeKeys.contains(node.key)
              ? _loadedChildren[node.key] ?? const <MonoRelationGraphNode>[]
              : const <MonoRelationGraphNode>[];
          return _GraphEntityBranch(
            node: node,
            childGroups: _groupNodes(
              children,
              path: '$path/${node.key}',
              ancestors: nextAncestors,
              defaultCollapsed: _autoCollapsedParentNodeKeys.contains(node.key),
            ),
          );
        }).toList(),
      );
    }).toList();
  }

  double _groupHeight(
    _GraphRelationBranch group, {
    required Size relationSize,
    required Size entitySize,
    required double verticalGap,
    required double groupGap,
  }) {
    if (group.collapsed || group.entities.isEmpty) return relationSize.height;
    final entitiesHeight =
        group.entities.fold<double>(0, (sum, entity) {
          return sum +
              _entityHeight(
                entity,
                relationSize: relationSize,
                entitySize: entitySize,
                verticalGap: verticalGap,
                groupGap: groupGap,
              );
        }) +
        math.max(0, group.entities.length - 1) * verticalGap;
    return math.max(relationSize.height, entitiesHeight);
  }

  double _entityHeight(
    _GraphEntityBranch entity, {
    required Size relationSize,
    required Size entitySize,
    required double verticalGap,
    required double groupGap,
  }) {
    if (entity.childGroups.isEmpty) return entitySize.height;
    final groupsHeight =
        entity.childGroups.fold<double>(0, (sum, group) {
          return sum +
              _groupHeight(
                group,
                relationSize: relationSize,
                entitySize: entitySize,
                verticalGap: verticalGap,
                groupGap: groupGap,
              );
        }) +
        math.max(0, entity.childGroups.length - 1) * groupGap;
    return math.max(entitySize.height, groupsHeight);
  }

  void _layoutGroup({
    required _GraphRelationBranch group,
    required _GraphSide side,
    required double top,
    required Rect anchorRect,
    required List<_PositionedGraphNode> nodes,
    required List<_GraphEdge> edges,
    required Size relationSize,
    required Size entitySize,
    required double horizontalGap,
    required double verticalGap,
    required double groupGap,
  }) {
    final height = _groupHeight(
      group,
      relationSize: relationSize,
      entitySize: entitySize,
      verticalGap: verticalGap,
      groupGap: groupGap,
    );
    final relationCenterX = side == _GraphSide.right
        ? anchorRect.right + horizontalGap + relationSize.width / 2
        : anchorRect.left - horizontalGap - relationSize.width / 2;
    final relationRect = Rect.fromCenter(
      center: Offset(relationCenterX, top + height / 2),
      width: relationSize.width,
      height: relationSize.height,
    );
    nodes.add(
      _PositionedGraphNode(
        kind: _GraphNodeKind.relation,
        rect: relationRect,
        label: group.label,
        side: side,
        relationKey: group.key,
        relationCollapsed: group.collapsed,
      ),
    );
    edges.add(_GraphEdge(from: anchorRect, to: relationRect, side: side));
    if (group.collapsed) return;

    final entitiesHeight =
        group.entities.fold<double>(0, (sum, entity) {
          return sum +
              _entityHeight(
                entity,
                relationSize: relationSize,
                entitySize: entitySize,
                verticalGap: verticalGap,
                groupGap: groupGap,
              );
        }) +
        math.max(0, group.entities.length - 1) * verticalGap;
    var cursorY = top + (height - entitiesHeight) / 2;
    for (final entity in group.entities) {
      final entityHeight = _entityHeight(
        entity,
        relationSize: relationSize,
        entitySize: entitySize,
        verticalGap: verticalGap,
        groupGap: groupGap,
      );
      final entityCenterX = side == _GraphSide.right
          ? relationRect.right + horizontalGap + entitySize.width / 2
          : relationRect.left - horizontalGap - entitySize.width / 2;
      final entityRect = Rect.fromCenter(
        center: Offset(entityCenterX, cursorY + entityHeight / 2),
        width: entitySize.width,
        height: entitySize.height,
      );
      nodes.add(
        _PositionedGraphNode(
          kind: _GraphNodeKind.entity,
          rect: entityRect,
          label: entity.node.title,
          side: side,
          entity: entity.node,
        ),
      );
      edges.add(_GraphEdge(from: relationRect, to: entityRect, side: side));

      if (entity.childGroups.isNotEmpty) {
        final childrenHeight =
            entity.childGroups.fold<double>(0, (sum, child) {
              return sum +
                  _groupHeight(
                    child,
                    relationSize: relationSize,
                    entitySize: entitySize,
                    verticalGap: verticalGap,
                    groupGap: groupGap,
                  );
            }) +
            math.max(0, entity.childGroups.length - 1) * groupGap;
        var childTop = cursorY + (entityHeight - childrenHeight) / 2;
        for (final child in entity.childGroups) {
          final childHeight = _groupHeight(
            child,
            relationSize: relationSize,
            entitySize: entitySize,
            verticalGap: verticalGap,
            groupGap: groupGap,
          );
          _layoutGroup(
            group: child,
            side: side,
            top: childTop,
            anchorRect: entityRect,
            nodes: nodes,
            edges: edges,
            relationSize: relationSize,
            entitySize: entitySize,
            horizontalGap: horizontalGap,
            verticalGap: verticalGap,
            groupGap: groupGap,
          );
          childTop += childHeight + groupGap;
        }
      }
      cursorY += entityHeight + verticalGap;
    }
  }
}

class _RelationGraphSession extends ChangeNotifier {
  final Map<String, List<MonoRelationGraphNode>> loadedChildren = {};
  final Set<String> expandedNodeKeys = {};
  final Set<String> loadingNodeKeys = {};
  final Set<String> failedNodeKeys = {};
  final Set<String> collapsedRelationKeys = {};
  final Set<String> expandedRelationKeys = {};
  final Set<String> autoCollapsedParentNodeKeys = {};

  void mutate(VoidCallback update) {
    update();
    notifyListeners();
  }

  void reset() {
    loadedChildren.clear();
    expandedNodeKeys.clear();
    loadingNodeKeys.clear();
    failedNodeKeys.clear();
    collapsedRelationKeys.clear();
    expandedRelationKeys.clear();
    autoCollapsedParentNodeKeys.clear();
    notifyListeners();
  }
}

class _MonoRelationFullscreenPage extends StatelessWidget {
  final String title;
  final Widget graph;

  const _MonoRelationFullscreenPage({required this.title, required this.graph});

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final compact = mediaQuery.size.width < 600;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '$title · 脑图',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        toolbarHeight: compact ? kToolbarHeight : 64,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        minimum: EdgeInsets.only(
          left: mediaQuery.padding.left,
          right: mediaQuery.padding.right,
          bottom: mediaQuery.padding.bottom,
        ),
        child: graph,
      ),
    );
  }
}

class _GraphImage extends StatelessWidget {
  final String imageUrl;
  final IconData placeholderIcon;
  final double width;
  final double height;

  const _GraphImage({
    required this.imageUrl,
    required this.placeholderIcon,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Container(
      width: width,
      height: height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(placeholderIcon, size: 20),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: imageUrl.isEmpty
          ? placeholder()
          : CachedNetworkImage(
              imageUrl: imageUrl,
              width: width,
              height: height,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              placeholder: (_, _) => placeholder(),
              errorWidget: (_, _, _) => placeholder(),
            ),
    );
  }
}

enum _GraphNodeKind { center, relation, entity }

enum _GraphSide { none, left, right }

class _GraphRelationBranch {
  final String key;
  final String label;
  final bool collapsed;
  final List<_GraphEntityBranch> entities;

  const _GraphRelationBranch({
    required this.key,
    required this.label,
    required this.collapsed,
    required this.entities,
  });
}

class _GraphEntityBranch {
  final MonoRelationGraphNode node;
  final List<_GraphRelationBranch> childGroups;

  const _GraphEntityBranch({required this.node, required this.childGroups});
}

class _PositionedGraphNode {
  final _GraphNodeKind kind;
  final Rect rect;
  final String label;
  final _GraphSide side;
  final String? relationKey;
  final bool relationCollapsed;
  final MonoRelationGraphNode? entity;

  const _PositionedGraphNode({
    required this.kind,
    required this.rect,
    required this.label,
    required this.side,
    this.relationKey,
    this.relationCollapsed = false,
    this.entity,
  });

  _PositionedGraphNode shift(Offset offset) => _PositionedGraphNode(
    kind: kind,
    rect: rect.shift(offset),
    label: label,
    side: side,
    relationKey: relationKey,
    relationCollapsed: relationCollapsed,
    entity: entity,
  );
}

class _GraphEdge {
  final Rect from;
  final Rect to;
  final _GraphSide side;

  const _GraphEdge({required this.from, required this.to, required this.side});

  _GraphEdge shift(Offset offset) =>
      _GraphEdge(from: from.shift(offset), to: to.shift(offset), side: side);
}

class _RelationGraphLayout {
  final Size size;
  final List<_PositionedGraphNode> nodes;
  final List<_GraphEdge> edges;

  const _RelationGraphLayout({
    required this.size,
    required this.nodes,
    required this.edges,
  });
}

class _RelationGraphLinePainter extends CustomPainter {
  final List<_GraphEdge> edges;
  final Color color;

  const _RelationGraphLinePainter({required this.edges, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final edge in edges) {
      final start = edge.side == _GraphSide.left
          ? edge.from.centerLeft
          : edge.from.centerRight;
      final end = edge.side == _GraphSide.left
          ? edge.to.centerRight
          : edge.to.centerLeft;
      final controlX = (start.dx + end.dx) / 2;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(controlX, start.dy, controlX, end.dy, end.dx, end.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RelationGraphLinePainter oldDelegate) {
    return oldDelegate.edges != edges || oldDelegate.color != color;
  }
}
