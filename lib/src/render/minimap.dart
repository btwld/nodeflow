import 'package:flutter/widgets.dart';

import '../controller/flow_controller.dart';
import '../models/coordinates.dart';
import '../models/flow_viewport.dart';
import '../theme/flow_theme.dart';

/// An affine graph -> minimap-local mapping: uniform [scale] followed by a
/// [translation], so a graph rect fits centered inside the minimap.
///
/// Pure and const so it can be unit-tested without pumping a widget.
@immutable
class MinimapProjection {
  const MinimapProjection({required this.scale, required this.translation});

  /// Uniform scale applied to graph coordinates.
  final double scale;

  /// Minimap-local offset added after scaling.
  final Offset translation;

  /// Maps a graph point into minimap-local pixels.
  Offset graphToMap(Offset graph) => graph * scale + translation;

  /// Maps a minimap-local point back into graph coordinates.
  Offset mapToGraph(Offset local) => (local - translation) / scale;

  /// Maps a graph rect into a minimap-local rect.
  Rect graphRectToMap(Rect graph) =>
      Rect.fromPoints(graphToMap(graph.topLeft), graphToMap(graph.bottomRight));

  @override
  bool operator ==(Object other) =>
      other is MinimapProjection &&
      other.scale == scale &&
      other.translation == translation;

  @override
  int get hashCode => Object.hash(scale, translation);
}

/// Builds the projection that fits [contentBounds] into a [mapSize] paint area,
/// leaving [padding] pixels of margin on every side and centering the content.
///
/// Degenerate bounds (empty or non-finite) collapse to a centered unit box so
/// the mapping stays finite.
MinimapProjection computeMinimapProjection({
  required Rect contentBounds,
  required Size mapSize,
  double padding = 8,
}) {
  final availableW = mapSize.width - padding * 2;
  final availableH = mapSize.height - padding * 2;
  if (availableW <= 0 || availableH <= 0) {
    return const MinimapProjection(scale: 1, translation: Offset.zero);
  }

  var bounds = contentBounds;
  if (!bounds.isFinite || bounds.width <= 0 || bounds.height <= 0) {
    // Fall back to a 1x1 box centered on the (possibly finite) origin so a
    // single degenerate node still lands in the middle of the map.
    final center = bounds.isFinite ? bounds.center : Offset.zero;
    bounds = Rect.fromCenter(center: center, width: 1, height: 1);
  }

  final scale = (availableW / bounds.width) < (availableH / bounds.height)
      ? availableW / bounds.width
      : availableH / bounds.height;

  // Center the scaled content inside the map.
  final scaledW = bounds.width * scale;
  final scaledH = bounds.height * scale;
  final dx = padding + (availableW - scaledW) / 2 - bounds.left * scale;
  final dy = padding + (availableH - scaledH) / 2 - bounds.top * scale;
  return MinimapProjection(scale: scale, translation: Offset(dx, dy));
}

/// The graph rect the minimap should frame: the union of [nodesBounds] and the
/// currently visible [visibleArea], so the viewport indicator is always in
/// frame even after panning away from the nodes. Either may be `null`.
Rect minimapContentBounds({
  required GraphRect? nodesBounds,
  required GraphRect? visibleArea,
}) {
  final nodes = nodesBounds?.rect;
  final visible = visibleArea?.rect;
  if (nodes == null) return visible ?? Rect.zero;
  if (visible == null) return nodes;
  return nodes.expandToInclude(visible);
}

/// The camera that centers the graph point under a minimap-local [localTap] on
/// screen, preserving [zoom]. This is the pure core of minimap click/drag
/// panning: minimap-local -> graph -> [FlowViewport].
FlowViewport viewportForMinimapTap({
  required Offset localTap,
  required MinimapProjection projection,
  required double zoom,
  required Size screenSize,
}) {
  final graph = projection.mapToGraph(localTap);
  return FlowViewport(
    x: screenSize.width / 2 - graph.dx * zoom,
    y: screenSize.height / 2 - graph.dy * zoom,
    zoom: zoom,
  );
}

/// Paints node rectangles and the viewport indicator into the minimap, using a
/// [MinimapProjection] to map graph -> minimap-local space.
class MinimapPainter<T, E> extends CustomPainter {
  MinimapPainter({
    required this.controller,
    required this.theme,
    required this.projection,
    required this.visibleArea,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final FlowController<T, E> controller;
  final FlowTheme theme;
  final MinimapProjection projection;

  /// The visible graph area (viewport indicator), or `null` to omit it.
  final GraphRect? visibleArea;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);

    final nodePaint = Paint()..style = PaintingStyle.fill;
    for (final node in controller.nodes) {
      final rect = projection.graphRectToMap(node.bounds.rect);
      nodePaint.color = node.selected.value
          ? theme.selectionStroke
          : theme.minimapNode;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        nodePaint,
      );
    }

    final visible = visibleArea;
    if (visible != null) {
      final rect = projection.graphRectToMap(visible.rect);
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.fill
          ..color = theme.minimapViewport.withValues(alpha: 0.12),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = theme.minimapViewport,
      );
    }
  }

  @override
  bool shouldRepaint(covariant MinimapPainter<T, E> oldDelegate) =>
      !identical(oldDelegate.controller, controller) ||
      oldDelegate.theme != theme ||
      oldDelegate.projection != projection ||
      oldDelegate.visibleArea != visibleArea;
}

/// A bottom-right overlay that mirrors the whole graph at a glance and pans the
/// camera on click/drag.
///
/// The panel is a glass card ([FlowTheme.minimapBackground] +
/// [FlowTheme.minimapBorder]); inside, node rectangles (accent when selected)
/// and the viewport indicator are painted through a [MinimapProjection].
/// Rebuilds on graph structure, viewport, selection, and node geometry changes;
/// it never animates.
class Minimap<T, E> extends StatelessWidget {
  const Minimap({
    super.key,
    required this.controller,
    required this.theme,
    this.size = const Size(200, 140),
    this.padding = 8,
  });

  final FlowController<T, E> controller;
  final FlowTheme theme;

  /// The minimap panel size.
  final Size size;

  /// Inner margin (pixels) reserved on every side when fitting the graph.
  final double padding;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: controller.structureVersion,
    builder: (context, _, _) => _buildMinimap(context),
  );

  Widget _buildMinimap(BuildContext context) {
    final nodeGeometry = <Listenable>[
      for (final node in controller.nodes) ...[
        node.position,
        node.measuredSize,
      ],
    ];
    return RepaintBoundary(
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          controller.viewport,
          controller.selection,
          ...nodeGeometry,
        ]),
        builder: (context, _) {
          final screenSize = controller.lastKnownScreenSize;
          final visibleArea = screenSize == null || screenSize.isEmpty
              ? null
              : controller.viewport.value.getVisibleArea(screenSize);
          final projection = computeMinimapProjection(
            contentBounds: minimapContentBounds(
              nodesBounds: controller.nodesBounds,
              visibleArea: visibleArea,
            ),
            mapSize: size,
            padding: padding,
          );

          void recenter(Offset local) {
            final screen = controller.lastKnownScreenSize;
            if (screen == null || screen.isEmpty) return;
            controller.setViewport(
              viewportForMinimapTap(
                localTap: local,
                projection: projection,
                zoom: controller.viewport.value.zoom,
                screenSize: screen,
              ),
            );
          }

          // Glass panel: high-alpha background, hairline border, and a
          // theme-driven corner radius.
          return Container(
            width: size.width,
            height: size.height,
            decoration: BoxDecoration(
              color: theme.minimapBackground,
              borderRadius: BorderRadius.circular(theme.minimapRadius),
              border: Border.all(color: theme.minimapBorder, width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(theme.minimapRadius),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => recenter(details.localPosition),
                onPanStart: (details) => recenter(details.localPosition),
                onPanUpdate: (details) => recenter(details.localPosition),
                child: CustomPaint(
                  painter: MinimapPainter<T, E>(
                    controller: controller,
                    theme: theme,
                    projection: projection,
                    visibleArea: visibleArea,
                    repaint: Listenable.merge(<Listenable>[
                      controller.structureVersion,
                      controller.viewport,
                      controller.selection,
                      ...nodeGeometry,
                    ]),
                  ),
                  size: size,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
