import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../controller/flow_controller.dart';
import '../controller/interaction_state.dart';
import '../edges/edge_style.dart';
import '../models/connection.dart';
import '../models/coordinates.dart';
import '../models/flow_edge.dart';
import '../models/flow_node.dart';
import '../models/flow_port.dart';
import '../models/flow_viewport.dart';
import '../geometry/port_anchor.dart';
import '../controller/alignment_snap.dart';
import '../theme/flow_theme.dart';
import 'connection_preview.dart';
import 'edges_painter.dart';
import 'grid_painter.dart';
import 'marquee.dart';
import 'minimap.dart';
import 'snap_guides_painter.dart';
import 'node_container.dart';
import 'unbounded.dart';

/// A customizable node canvas inspired by React Flow.
///
/// Node visuals are entirely app-defined through [nodeBuilder]; the canvas owns
/// camera (pan/zoom), the dotted grid, node positioning, selection, drag,
/// marquee, edges, and drag-to-connect. State lives on [controller].
class NodeFlow<T, E> extends StatefulWidget {
  const NodeFlow({
    super.key,
    required this.controller,
    required this.nodeBuilder,
    this.theme,
    this.fitViewOnLoad = true,
    this.edgeStyle = FlowEdgeStyle.bezier,
    this.animateEdges = true,
    this.minimap = true,
    this.minimapMargin = const EdgeInsets.only(right: 12, bottom: 12),
    this.snapGuides = true,
    this.onConnect,
    this.onPortHover,
  });

  /// The state/behavior hub for this canvas.
  ///
  /// Use one mounted [NodeFlow] per controller. Canvas-local settings such as
  /// the last known screen size and alignment-guide enablement live on the
  /// controller and would otherwise compete across multiple canvases.
  final FlowController<T, E> controller;

  /// Builds the visual for a node. Should have a fixed width and intrinsic
  /// height; the canvas measures and reports the laid-out size.
  final Widget Function(BuildContext context, FlowNode<T> node) nodeBuilder;

  /// Resolved painter values. When `null`, the canvas resolves a [FlowTheme]
  /// registered as a [ThemeExtension] on the ambient [Theme] (via
  /// [FlowTheme.resolve]) once per dependency change, falling back to
  /// [FlowTheme.dark] when none is registered.
  final FlowTheme? theme;

  /// Whether to fit all nodes into view after the first layout.
  final bool fitViewOnLoad;

  /// How edges are routed between ports. Defaults to [FlowEdgeStyle.bezier].
  final FlowEdgeStyle edgeStyle;

  /// Whether edges render an animated flowing dash. When `false` they render as
  /// a static dashed line.
  final bool animateEdges;

  /// Whether the bottom-right [Minimap] overlay is mounted. Defaults to `true`.
  final bool minimap;

  /// Offset of the minimap from the canvas's bottom-right corner. Hosts that
  /// float other chrome over the canvas (e.g. an execution-log panel along
  /// the bottom) raise the bottom inset so the minimap stays clear of it.
  final EdgeInsets minimapMargin;

  /// Whether node drags detect alignment against other nodes, softly snapping
  /// and painting dashed guide lines. Defaults to `true`.
  final bool snapGuides;

  /// Called when a drag-to-connect gesture drops on a compatible target port
  /// with a normalized [FlowConnectionRequest]. The canvas never mutates the
  /// graph; add an edge through the controller to accept the request.
  ///
  /// The boolean return is retained for 0.2.x compatibility and is not
  /// currently consumed by the canvas. Identical connections are deduped and
  /// never reach this callback.
  final bool Function(FlowConnectionRequest request)? onConnect;

  /// Called when a port handle is hovered (with the anchor) or unhovered (with
  /// `null`), so the app can render hover cards.
  final void Function(FlowPortAnchor? anchor)? onPortHover;

  @override
  State<NodeFlow<T, E>> createState() => _NodeFlowState<T, E>();
}

class _NodeFlowState<T, E> extends State<NodeFlow<T, E>>
    with SingleTickerProviderStateMixin {
  late final TransformationController _transformationController;
  late final AnimationController _dashController;

  final GlobalKey _rootKey = GlobalKey();

  /// Guards the bidirectional viewport <-> transform sync against feedback.
  bool _syncing = false;

  /// Whether a shift key is currently held. While held, the InteractiveViewer's
  /// pan/zoom is suppressed so shift-drag draws a marquee instead of panning.
  bool _shiftHeld = false;

  Offset? _pointerDownLocal;
  bool _pointerMoved = false;
  bool _downOnEmpty = false;

  FlowController<T, E> get _controller => widget.controller;

  /// The theme resolved from the ambient [Theme] when [NodeFlow.theme]
  /// is null. Recomputed in [didChangeDependencies] so theme changes re-resolve
  /// without touching the paint path.
  FlowTheme? _resolvedTheme;

  FlowTheme get _theme =>
      widget.theme ?? _resolvedTheme ?? const FlowTheme.dark();

  Animation<double> get _dash => widget.animateEdges
      ? _dashController
      : const AlwaysStoppedAnimation<double>(0);

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController(
      _matrixOf(_controller.viewport.value),
    );
    _dashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _transformationController.addListener(_onTransformChanged);
    _attachController(_controller);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncDashAnimation();
      if (!widget.fitViewOnLoad) return;

      final initialController = _controller;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(initialController, _controller)) return;
        initialController.fitView(padding: 0.2, maxZoom: 1);
      });
      // addPostFrameCallback does not request another frame. The extra frame
      // lets deferred node-size reports land before the initial fit runs.
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolve the canvas palette from the ambient Theme once per dependency
    // change (never in paint()). No registered extension -> dark defaults.
    _resolvedTheme = widget.theme == null ? FlowTheme.resolve(context) : null;
  }

  @override
  void didUpdateWidget(covariant NodeFlow<T, E> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _cancelControllerInteraction(oldWidget.controller);
      _detachController(oldWidget.controller);
      _attachController(widget.controller);
      _syncTransformFromController();
      _resetPointer();
      _syncDashAnimation();
    } else {
      _controller.snapGuidesEnabled = widget.snapGuides;
      if (oldWidget.animateEdges != widget.animateEdges) _syncDashAnimation();
    }
    if (oldWidget.theme != widget.theme) {
      _resolvedTheme = widget.theme == null ? FlowTheme.resolve(context) : null;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _transformationController.removeListener(_onTransformChanged);
    _cancelControllerInteraction(_controller);
    _detachController(_controller);
    _dashController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _cancelControllerInteraction(FlowController<T, E> controller) {
    switch (controller.mode.value) {
      case FlowInteractionMode.draggingNode:
        controller.cancelNodeDrag();
      case FlowInteractionMode.draggingConnection:
        controller.endConnection();
      case FlowInteractionMode.marquee:
        controller.endMarquee();
      case FlowInteractionMode.idle:
      case FlowInteractionMode.panning:
        break;
    }
  }

  void _attachController(FlowController<T, E> controller) {
    controller.viewport.addListener(_onViewportChanged);
    controller.structureVersion.addListener(_syncDashAnimation);
    controller.snapGuidesEnabled = widget.snapGuides;
  }

  void _detachController(FlowController<T, E> controller) {
    controller.viewport.removeListener(_onViewportChanged);
    controller.structureVersion.removeListener(_syncDashAnimation);
  }

  void _syncTransformFromController() {
    _syncing = true;
    try {
      _transformationController.value = _matrixOf(_controller.viewport.value);
    } finally {
      _syncing = false;
    }
  }

  void _syncDashAnimation() {
    final shouldRun = widget.animateEdges && _controller.edges.isNotEmpty;
    if (shouldRun) {
      if (!_dashController.isAnimating) _dashController.repeat();
    } else if (_dashController.isAnimating) {
      _dashController.stop();
    }
  }

  bool _onKeyEvent(KeyEvent event) {
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (shift != _shiftHeld && mounted) {
      setState(() => _shiftHeld = shift);
    }
    return false; // Never consume; other handlers still run.
  }

  // The TransformationController is the source of truth during user pan/zoom;
  // public viewport ops write back through the controller's viewport notifier.
  Matrix4 _matrixOf(FlowViewport vp) => Matrix4.identity()
    ..translateByDouble(vp.x, vp.y, 0, 1)
    ..scaleByDouble(vp.zoom, vp.zoom, vp.zoom, 1);

  void _onTransformChanged() {
    if (_syncing) return;
    final matrix = _transformationController.value;
    final translation = matrix.getTranslation();
    final next = FlowViewport(
      x: translation.x,
      y: translation.y,
      zoom: matrix.getMaxScaleOnAxis(),
    );
    if (next == _controller.viewport.value) return;
    _syncing = true;
    try {
      _controller.setViewport(next);
    } finally {
      _syncing = false;
    }
  }

  void _onViewportChanged() {
    if (_syncing) return;
    _syncTransformFromController();
  }

  bool get _shiftPressed {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  FlowNode<T>? _hitTestNode(GraphPosition point) {
    final ordered = _controller.nodes; // ascending z-order
    for (var i = ordered.length - 1; i >= 0; i--) {
      final node = ordered[i];
      if (node.bounds.contains(point)) return node;
    }
    return null;
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointerDownLocal = event.localPosition;
    _pointerMoved = false;
    final graph = _controller.screenToGraph(
      ScreenPosition(event.localPosition),
    );
    final hit = _hitTestNode(graph);
    _downOnEmpty = hit == null;
    if (hit == null && _shiftPressed) {
      _controller.beginMarquee(graph);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final down = _pointerDownLocal;
    if (down != null && (event.localPosition - down).distance > kTouchSlop) {
      _pointerMoved = true;
    }
    if (_controller.mode.value == FlowInteractionMode.marquee) {
      _controller.updateMarquee(
        _controller.screenToGraph(ScreenPosition(event.localPosition)),
      );
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_controller.mode.value == FlowInteractionMode.marquee) {
      _controller.endMarquee();
      _resetPointer();
      return;
    }
    if (_downOnEmpty && !_pointerMoved && !_shiftPressed) {
      final edge = _hitTestEdge(event.localPosition);
      _controller.clearSelection();
      if (edge != null) {
        _controller.selectEdge(edge.id);
      } else {
        _controller.clearEdgeSelection();
      }
    }
    _resetPointer();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_controller.mode.value == FlowInteractionMode.marquee) {
      _controller.endMarquee();
    }
    _resetPointer();
  }

  void _resetPointer() {
    _pointerDownLocal = null;
    _pointerMoved = false;
    _downOnEmpty = false;
  }

  // ---------------------------------------------------------------------------
  // Edge hit-testing
  // ---------------------------------------------------------------------------

  FlowEdge<E>? _hitTestEdge(Offset localScreen) {
    final vp = _controller.viewport.value;
    const tolerance = 3.0 + 6.0; // stroke width + slack, in screen pixels.
    final edges = _controller.edges;
    for (var i = edges.length - 1; i >= 0; i--) {
      final edge = edges[i];
      final geometry = resolveEdgeGeometry(
        _controller,
        edge,
        vp,
        widget.edgeStyle,
      );
      if (geometry == null) continue;
      for (final rect in geometry.hitTestRects(tolerance)) {
        if (rect.contains(localScreen)) return edge;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Drag-to-connect
  // ---------------------------------------------------------------------------

  Offset _globalToLocal(Offset global) {
    final box = _rootKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return global;
    return box.globalToLocal(global);
  }

  void _onPortDragStart(String nodeId, FlowPort port, Offset globalPosition) {
    final local = _globalToLocal(globalPosition);
    final graph = _controller.screenToGraph(ScreenPosition(local));
    _controller.beginConnection(nodeId, port, graph);
  }

  void _onPortDragUpdate(Offset globalPosition) {
    final pending = _controller.pendingConnection.value;
    if (pending == null) return;
    final local = _globalToLocal(globalPosition);
    final graph = _controller.screenToGraph(ScreenPosition(local));
    final hit = _hitTestPort(local, pending.sourceNodeId, pending.sourcePort);
    _controller.updateConnection(
      graph,
      targetNodeId: hit?.$1,
      targetPort: hit?.$2,
    );
  }

  void _onPortDragEnd(Offset globalPosition) {
    final pending = _controller.pendingConnection.value;
    if (pending == null) {
      _controller.endConnection();
      return;
    }
    try {
      final local = _globalToLocal(globalPosition);
      final hit = _hitTestPort(local, pending.sourceNodeId, pending.sourcePort);
      if (hit != null) {
        final request = _normalizeRequest(
          pending.sourceNodeId,
          pending.sourcePort,
          hit.$1,
          hit.$2,
        );
        if (request != null &&
            !_controller.connectionExists(
              request.sourceNodeId,
              request.sourcePortId,
              request.targetNodeId,
              request.targetPortId,
            )) {
          // The canvas never adds the edge: the app owns the model and adds it
          // through the controller when it accepts the request.
          widget.onConnect?.call(request);
        }
      }
    } finally {
      _controller.endConnection();
    }
  }

  void _onPortDragCancel() {
    _controller.endConnection();
  }

  /// Finds the nearest compatible port (opposite kind, different node) whose
  /// screen anchor is within tolerance of [localScreen].
  (String, FlowPort)? _hitTestPort(
    Offset localScreen,
    String sourceNodeId,
    FlowPort sourcePort,
  ) {
    final vp = _controller.viewport.value;
    final maxHandle = _theme.branchHandleSize > _theme.handleSize
        ? _theme.branchHandleSize
        : _theme.handleSize;
    final tolerance = maxHandle * vp.zoom / 2 + 10;

    (String, FlowPort)? best;
    var bestDistance = double.infinity;
    final ordered = _controller.nodes;
    for (var i = ordered.length - 1; i >= 0; i--) {
      final node = ordered[i];
      if (node.id == sourceNodeId) continue; // no self-connections
      for (final port in node.ports) {
        if (port.kind == sourcePort.kind) continue; // need opposite kind
        final anchorScreen = vp.toScreen(portAnchor(node, port)).offset;
        final distance = (anchorScreen - localScreen).distance;
        if (distance <= tolerance && distance < bestDistance) {
          bestDistance = distance;
          best = (node.id, port);
        }
      }
    }
    return best;
  }

  /// Normalizes a dropped port pair so the output side becomes the source.
  /// Returns `null` when the two ports are not input/output complementary.
  FlowConnectionRequest? _normalizeRequest(
    String aNode,
    FlowPort aPort,
    String bNode,
    FlowPort bPort,
  ) {
    if (aPort.kind == bPort.kind) return null;
    final aIsOutput = aPort.kind == PortKind.output;
    final outNode = aIsOutput ? aNode : bNode;
    final outPort = aIsOutput ? aPort : bPort;
    final inNode = aIsOutput ? bNode : aNode;
    final inPort = aIsOutput ? bPort : aPort;
    return FlowConnectionRequest(
      sourceNodeId: outNode,
      sourcePortId: outPort.id,
      targetNodeId: inNode,
      targetPortId: inPort.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    return LayoutBuilder(
      builder: (context, constraints) {
        _controller.lastKnownScreenSize = constraints.biggest;
        final size = constraints.biggest;

        return Listener(
          key: _rootKey,
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: ClipRect(
            child: ColoredBox(
              color: theme.background,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  // Grid: screen space, behind everything.
                  RepaintBoundary(
                    child: ValueListenableBuilder<FlowViewport>(
                      valueListenable: _controller.viewport,
                      builder: (context, viewport, _) => CustomPaint(
                        painter: GridPainter(viewport: viewport, theme: theme),
                        size: Size.infinite,
                      ),
                    ),
                  ),

                  // Edges: screen space, behind the nodes.
                  IgnorePointer(
                    child: EdgesLayer<T, E>(
                      controller: _controller,
                      theme: theme,
                      style: widget.edgeStyle,
                      dash: _dash,
                    ),
                  ),

                  // Node layer: transformed by the InteractiveViewer.
                  ValueListenableBuilder<FlowInteractionMode>(
                    valueListenable: _controller.mode,
                    builder: (context, mode, child) {
                      final interactive =
                          !_shiftHeld &&
                          (mode == FlowInteractionMode.idle ||
                              mode == FlowInteractionMode.panning);
                      return InteractiveViewer(
                        transformationController: _transformationController,
                        constrained: false,
                        boundaryMargin: const EdgeInsets.all(double.infinity),
                        minScale: _controller.minZoom,
                        maxScale: _controller.maxZoom,
                        trackpadScrollCausesScale: true,
                        panEnabled: interactive,
                        scaleEnabled: interactive,
                        child: child!,
                      );
                    },
                    child: UnboundedSizedBox(
                      width: size.width,
                      height: size.height,
                      child: _NodeLayer<T, E>(
                        controller: _controller,
                        theme: theme,
                        nodeBuilder: widget.nodeBuilder,
                        onPortHover: widget.onPortHover,
                        onPortDragStart: _onPortDragStart,
                        onPortDragUpdate: _onPortDragUpdate,
                        onPortDragEnd: _onPortDragEnd,
                        onPortDragCancel: _onPortDragCancel,
                      ),
                    ),
                  ),

                  // Drag-to-connect preview: screen space, above the nodes.
                  IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: ConnectionPreviewPainter<T, E>(
                          controller: _controller,
                          theme: theme,
                          repaint: Listenable.merge(<Listenable>[
                            _controller.pendingConnection,
                            _controller.viewport,
                          ]),
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ),

                  // Marquee: screen space, above content, non-interactive.
                  IgnorePointer(
                    child: RepaintBoundary(
                      child: ValueListenableBuilder<GraphRect?>(
                        valueListenable: _controller.marqueeRect,
                        builder: (context, rect, _) =>
                            ValueListenableBuilder<FlowViewport>(
                              valueListenable: _controller.viewport,
                              builder: (context, viewport, _) => CustomPaint(
                                painter: MarqueePainter(
                                  rect: rect,
                                  viewport: viewport,
                                  theme: theme,
                                ),
                                size: Size.infinite,
                              ),
                            ),
                      ),
                    ),
                  ),

                  // Alignment guides: screen space, non-interactive; painted
                  // only while a drag has active alignments.
                  if (widget.snapGuides)
                    IgnorePointer(
                      child: RepaintBoundary(
                        child: ValueListenableBuilder<List<FlowAlignmentGuide>>(
                          valueListenable: _controller.activeGuides,
                          builder: (context, guides, _) =>
                              ValueListenableBuilder<FlowViewport>(
                                valueListenable: _controller.viewport,
                                builder: (context, viewport, _) => CustomPaint(
                                  painter: SnapGuidesPainter(
                                    guides: guides,
                                    viewport: viewport,
                                    theme: theme,
                                  ),
                                  size: Size.infinite,
                                ),
                              ),
                        ),
                      ),
                    ),

                  // Minimap: screen space, bottom-right, interactive (pans).
                  if (widget.minimap)
                    Positioned(
                      right: widget.minimapMargin.right,
                      bottom: widget.minimapMargin.bottom,
                      child: Minimap<T, E>(
                        controller: _controller,
                        theme: theme,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The set of node widgets, rebuilt only when the graph structure changes.
class _NodeLayer<T, E> extends StatelessWidget {
  const _NodeLayer({
    required this.controller,
    required this.theme,
    required this.nodeBuilder,
    required this.onPortDragStart,
    required this.onPortDragUpdate,
    required this.onPortDragEnd,
    required this.onPortDragCancel,
    this.onPortHover,
  });

  final FlowController<T, E> controller;
  final FlowTheme theme;
  final Widget Function(BuildContext context, FlowNode<T> node) nodeBuilder;
  final void Function(FlowPortAnchor? anchor)? onPortHover;
  final void Function(String nodeId, FlowPort port, Offset globalPosition)
  onPortDragStart;
  final void Function(Offset globalPosition) onPortDragUpdate;
  final void Function(Offset globalPosition) onPortDragEnd;
  final VoidCallback onPortDragCancel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: controller.structureVersion,
      builder: (context, _, _) {
        final nodes = controller.nodes; // ascending z-order
        return UnboundedStack(
          clipBehavior: Clip.none,
          children: <Widget>[
            for (final node in nodes)
              NodeContainer<T, E>(
                key: ValueKey<String>(node.id),
                node: node,
                controller: controller,
                theme: theme,
                onPortHover: onPortHover,
                onPortDragStart: onPortDragStart,
                onPortDragUpdate: onPortDragUpdate,
                onPortDragEnd: onPortDragEnd,
                onPortDragCancel: onPortDragCancel,
                child: nodeBuilder(context, node),
              ),
          ],
        );
      },
    );
  }
}
