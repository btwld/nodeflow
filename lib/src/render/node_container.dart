import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../controller/flow_controller.dart';
import '../geometry/port_anchor.dart';
import '../interaction/non_trackpad_pan_gesture_recognizer.dart';
import '../models/connection.dart';
import '../models/coordinates.dart';
import '../models/flow_node.dart';
import '../models/flow_port.dart';
import '../theme/flow_theme.dart';
import 'port_handle.dart';
import 'unbounded.dart';

/// Hosts a single node's builder output at the node's graph position, with its
/// port handles stacked over the node edges.
///
/// Responsibilities:
/// - Positions the node via a [Positioned] driven by [FlowNode.position].
/// - Reports the child's laid-out size back into [FlowNode.measuredSize].
/// - Handles tap (select / additive-select) and mouse/touch drag (move the
///   selection, snapping on release). Trackpad pans bubble to the canvas'
///   [InteractiveViewer] via [NonTrackpadPanGestureRecognizer].
/// - Renders a [PortHandle] per port, reporting hover and starting
///   drag-to-connect gestures through the canvas callbacks.
///
/// This widget lives inside the canvas' transformed subtree, so pointer deltas
/// it receives are already in graph coordinates (no zoom division needed).
class NodeContainer<T, E> extends StatelessWidget {
  const NodeContainer({
    super.key,
    required this.node,
    required this.controller,
    required this.theme,
    required this.child,
    required this.onPortDragStart,
    required this.onPortDragUpdate,
    required this.onPortDragEnd,
    this.onPortHover,
  });

  final FlowNode<T> node;
  final FlowController<T, E> controller;
  final FlowTheme theme;

  /// The app-built visual for this node (fixed width, intrinsic height).
  final Widget child;

  /// Reports port hover/exit to the app so it can render hover cards.
  final void Function(FlowPortAnchor? anchor)? onPortHover;

  /// Called when a connection drag begins from a port on this node.
  final void Function(String nodeId, FlowPort port, Offset globalPosition)
  onPortDragStart;

  /// Called on each connection-drag move.
  final void Function(Offset globalPosition) onPortDragUpdate;

  /// Called when the connection drag ends.
  final void Function(Offset globalPosition) onPortDragEnd;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GraphPosition>(
      valueListenable: node.position,
      builder: (context, position, _) {
        return Positioned(
          left: position.dx,
          top: position.dy,
          child: ValueListenableBuilder<Size>(
            valueListenable: node.measuredSize,
            builder: (context, _, _) {
              return UnboundedStack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  RepaintBoundary(
                    child: RawGestureDetector(
                      behavior: HitTestBehavior.deferToChild,
                      gestures: <Type, GestureRecognizerFactory>{
                        TapGestureRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                              TapGestureRecognizer
                            >(
                              TapGestureRecognizer.new,
                              (recognizer) => recognizer.onTap = _handleTap,
                            ),
                        NonTrackpadPanGestureRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                              NonTrackpadPanGestureRecognizer
                            >(NonTrackpadPanGestureRecognizer.new, (
                              recognizer,
                            ) {
                              recognizer
                                ..onStart = _handleDragStart
                                ..onUpdate = _handleDragUpdate
                                ..onEnd = _handleDragEnd
                                ..onCancel = _handleDragCancel;
                            }),
                      },
                      child: _MeasureSize(
                        onChange: (size) => node.measuredSize.value = size,
                        child: child,
                      ),
                    ),
                  ),
                  ..._buildHandles(position),
                ],
              );
            },
          ),
        );
      },
    );
  }

  List<Widget> _buildHandles(GraphPosition nodeTopLeft) {
    if (node.ports.isEmpty) return const <Widget>[];
    return <Widget>[
      for (final port in node.ports) _positionedHandle(port, nodeTopLeft),
    ];
  }

  Widget _positionedHandle(FlowPort port, GraphPosition nodeTopLeft) {
    final size = port.visual == PortVisual.branch
        ? theme.branchHandleSize
        : theme.handleSize;
    final anchor = portAnchor(node, port);
    final localX = anchor.dx - nodeTopLeft.dx;
    final localY = anchor.dy - nodeTopLeft.dy;

    return Positioned(
      key: ValueKey<String>('port-${node.id}-${port.id}'),
      left: localX - size / 2,
      top: localY - size / 2,
      child: ValueListenableBuilder<PendingConnection?>(
        valueListenable: controller.pendingConnection,
        builder: (context, pending, _) {
          final highlighted =
              pending != null &&
              pending.targetNodeId == node.id &&
              pending.targetPort?.id == port.id;
          return PortHandle(
            port: port,
            theme: theme,
            highlighted: highlighted,
            onHoverChanged: (entered) => _reportHover(port, size, entered),
            onDragStart: (g) => onPortDragStart(node.id, port, g),
            onDragUpdate: onPortDragUpdate,
            onDragEnd: onPortDragEnd,
          );
        },
      ),
    );
  }

  void _reportHover(FlowPort port, double size, bool entered) {
    final handler = onPortHover;
    if (handler == null) return;
    if (!entered) {
      handler(null);
      return;
    }
    final anchor = portAnchor(node, port);
    final half = size / 2;
    final graphRect = GraphRect.fromLTWH(
      anchor.dx - half,
      anchor.dy - half,
      size,
      size,
    );
    handler(
      FlowPortAnchor(
        nodeId: node.id,
        port: port,
        anchorScreenRect: controller.viewport.value.toScreenRect(graphRect),
      ),
    );
  }

  bool get _additivePressed {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight) ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
  }

  void _handleTap() {
    if (_additivePressed) {
      controller.toggle(node.id);
    } else {
      controller.select(<String>[node.id]);
    }
  }

  void _handleDragStart(DragStartDetails details) {
    if (node.locked) return;
    controller.beginNodeDrag(node.id);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (node.locked) return;
    // `details.delta` is already in graph coordinates because this recognizer
    // lives inside the InteractiveViewer's transformed subtree.
    controller.moveNodeBy(node.id, GraphOffset(details.delta));
  }

  // No locked guard here: locking a node mid-drag must not skip the commit,
  // or the drag session (and the interaction mode) would be stranded.
  void _handleDragEnd(DragEndDetails details) {
    controller.endNodeDrag();
  }

  void _handleDragCancel() {
    controller.cancelNodeDrag();
  }
}

/// Reports its child's laid-out size via [onChange] whenever it changes.
///
/// The report is deferred to a post-frame callback so it never mutates state
/// during layout.
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required Widget super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureSizeRenderObject(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    _MeasureSizeRenderObject renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject(this.onChange);

  ValueChanged<Size> onChange;
  Size? _lastReported;

  @override
  void performLayout() {
    super.performLayout();
    final size = child?.size ?? Size.zero;
    if (_lastReported == size) return;
    _lastReported = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(size));
  }
}
