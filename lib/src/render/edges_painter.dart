import 'package:flutter/widgets.dart';

import '../controller/flow_controller.dart';
import '../edges/edge_style.dart';
import '../edges/flowing_dash.dart';
import '../geometry/port_anchor.dart';
import '../models/coordinates.dart';
import '../models/flow_edge.dart';
import '../models/flow_port.dart';
import '../models/flow_viewport.dart';
import '../theme/flow_theme.dart';

/// Paints edges behind the node layer, split into a cached static layer and a
/// live active layer for edges attached to dragging nodes.
class EdgesLayer<T, E> extends StatelessWidget {
  const EdgesLayer({
    super.key,
    required this.controller,
    required this.theme,
    required this.style,
    required this.dash,
  });

  final FlowController<T, E> controller;
  final FlowTheme theme;
  final FlowEdgeStyle style;

  /// Dash-flow phase in `[0, 1)`. Use `AlwaysStoppedAnimation(0)` to disable
  /// animation (edges then render as a static dashed line).
  final Animation<double> dash;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: controller.structureVersion,
      builder: (context, _, _) {
        return ValueListenableBuilder<Set<String>>(
          valueListenable: controller.draggingNodeIds,
          builder: (context, dragging, _) {
            final active = <Listenable>[];
            for (final id in dragging) {
              final n = controller.getNode(id);
              if (n != null) {
                active
                  ..add(n.position)
                  ..add(n.measuredSize);
              }
            }
            final staticRepaint = Listenable.merge(<Listenable>[
              controller.viewport,
              controller.edgeSelectionVersion,
              controller.edgeAccentVersion,
              dash,
            ]);
            final activeRepaint = Listenable.merge(<Listenable>[
              controller.viewport,
              controller.edgeSelectionVersion,
              controller.edgeAccentVersion,
              dash,
              ...active,
            ]);
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                RepaintBoundary(
                  child: CustomPaint(
                    painter: EdgesPainter<T, E>(
                      controller: controller,
                      theme: theme,
                      style: style,
                      dash: dash,
                      dragging: dragging,
                      includeDragging: false,
                      repaint: staticRepaint,
                    ),
                    size: Size.infinite,
                  ),
                ),
                if (dragging.isNotEmpty)
                  CustomPaint(
                    painter: EdgesPainter<T, E>(
                      controller: controller,
                      theme: theme,
                      style: style,
                      dash: dash,
                      dragging: dragging,
                      includeDragging: true,
                      repaint: activeRepaint,
                    ),
                    size: Size.infinite,
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Paints the subset of edges selected by [includeDragging] against
/// [dragging]: `false` paints edges with no dragging endpoint, `true` paints
/// only edges incident to a dragging node.
class EdgesPainter<T, E> extends CustomPainter {
  EdgesPainter({
    required this.controller,
    required this.theme,
    required this.style,
    required this.dash,
    required this.dragging,
    required this.includeDragging,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final FlowController<T, E> controller;
  final FlowTheme theme;
  final FlowEdgeStyle style;
  final Animation<double> dash;
  final Set<String> dragging;
  final bool includeDragging;

  static const double _strokeWidth = 3;
  static const double _selectedStrokeWidth = 3.5;

  @override
  void paint(Canvas canvas, Size size) {
    final vp = controller.viewport.value;
    final phase = dash.value;
    for (final edge in controller.edges) {
      final incident =
          dragging.contains(edge.sourceNodeId) ||
          dragging.contains(edge.targetNodeId);
      if (incident != includeDragging) continue;
      _paintEdge(canvas, vp, phase, edge);
    }
  }

  void _paintEdge(
    Canvas canvas,
    FlowViewport vp,
    double phase,
    FlowEdge<E> edge,
  ) {
    final geometry = resolveEdgeGeometry(controller, edge, vp, style);
    if (geometry == null) return;

    final path = geometry.toPath();

    final stroke = resolveEdgeStroke(edge, theme);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = stroke.color
      ..strokeWidth = stroke.width;

    paintFlowingDash(canvas, path, paint, phase: phase);

    if (edge.dangling) {
      paintDanglingBadge(canvas, path, theme.warning);
    }
  }

  @override
  bool shouldRepaint(covariant EdgesPainter<T, E> oldDelegate) =>
      oldDelegate.theme != theme ||
      oldDelegate.style != style ||
      oldDelegate.includeDragging != includeDragging ||
      !identical(oldDelegate.dragging, dragging);
}

/// The stroke an edge is painted with, resolved from its state and [theme].
///
/// Precedence is selected > [FlowEdge.accent] > theme default. The accent only
/// swaps the color: an accented edge keeps the ordinary stroke width, so the
/// extra weight stays a selection-only cue and both can be told apart when an
/// accented edge is also selected. Exposed for painter unit tests.
({Color color, double width}) resolveEdgeStroke<E>(
  FlowEdge<E> edge,
  FlowTheme theme,
) {
  if (edge.selected.value) {
    return (
      color: theme.edgeSelected,
      width: EdgesPainter._selectedStrokeWidth,
    );
  }
  return (color: edge.accent ?? theme.edge, width: EdgesPainter._strokeWidth);
}

/// Paints an amber "!" badge at the midpoint of [path]. Exposed for painter
/// unit tests.
void paintDanglingBadge(Canvas canvas, Path path, Color color) {
  final center = _pathMidpoint(path);
  if (center == null) return;

  const badge = 16.0;
  final rect = Rect.fromCenter(center: center, width: badge, height: badge);
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, const Radius.circular(4)),
    Paint()..color = color,
  );

  // Draw a deterministic "!" (bar + dot) in a dark ink, no font dependency.
  final ink = Paint()..color = const Color(0xFF1A1A1E);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: center.translate(0, -1.5), width: 2.4, height: 6),
      const Radius.circular(1.2),
    ),
    ink,
  );
  canvas.drawCircle(center.translate(0, 4), 1.4, ink);
}

/// Resolves an edge to its screen-space [EdgeGeometry] using [style], or `null`
/// when either endpoint's node/port is missing. Shared by the painter and the
/// canvas' edge hit-testing so painting and hit testing never diverge.
EdgeGeometry? resolveEdgeGeometry<T, E>(
  FlowController<T, E> controller,
  FlowEdge<E> edge,
  FlowViewport vp,
  FlowEdgeStyle style,
) {
  final src = _resolveEndpoint(
    controller,
    edge.sourceNodeId,
    edge.sourcePortId,
  );
  final tgt = _resolveEndpoint(
    controller,
    edge.targetNodeId,
    edge.targetPortId,
  );
  if (src == null || tgt == null) return null;
  final srcScreen = vp.toScreen(src.$1).offset;
  final tgtScreen = vp.toScreen(tgt.$1).offset;
  return style.geometry(srcScreen, src.$2, tgtScreen, tgt.$2);
}

(GraphPosition, PortSide)? _resolveEndpoint<T, E>(
  FlowController<T, E> controller,
  String nodeId,
  String portId,
) {
  final node = controller.getNode(nodeId);
  if (node == null) return null;
  final port = portById(node, portId);
  if (port == null) return null;
  return (portAnchor(node, port), port.side);
}

Offset? _pathMidpoint(Path path) {
  final metrics = path.computeMetrics().toList(growable: false);
  if (metrics.isEmpty) return null;
  var total = 0.0;
  for (final m in metrics) {
    total += m.length;
  }
  final mid = total / 2;
  var acc = 0.0;
  for (final m in metrics) {
    if (acc + m.length >= mid) {
      final tangent = m.getTangentForOffset(mid - acc);
      return tangent?.position;
    }
    acc += m.length;
  }
  return metrics.last.getTangentForOffset(metrics.last.length)?.position;
}
