import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderCustomPaint;
import 'package:flutter_test/flutter_test.dart';
import 'package:node_flow/node_flow.dart';

FlowNode<String> node(String id, double x, double y, {Size? size}) => FlowNode(
  id: id,
  type: 'test',
  data: id,
  position: GraphPosition(Offset(x, y)),
  size: size ?? const Size(120, 60),
);

void main() {
  group('computeMinimapProjection', () {
    test('fits content centered inside the padded map bounds', () {
      const mapSize = Size(200, 140);
      const padding = 8.0;
      final projection = computeMinimapProjection(
        contentBounds: const Rect.fromLTWH(0, 0, 400, 200),
        mapSize: mapSize,
        padding: padding,
      );

      // Uniform scale is the tighter of the two axes (width-bound here).
      expect(projection.scale, closeTo((200 - 16) / 400, 1e-9));

      // Both corners of the content land inside the map bounds.
      final topLeft = projection.graphToMap(const Offset(0, 0));
      final bottomRight = projection.graphToMap(const Offset(400, 200));
      final bounds = Offset.zero & mapSize;
      expect(bounds.contains(topLeft), isTrue);
      expect(bounds.contains(bottomRight), isTrue);
      // Padding is respected on the width-bound axis.
      expect(topLeft.dx, closeTo(padding, 1e-9));
      expect(bottomRight.dx, closeTo(mapSize.width - padding, 1e-9));
    });

    test('maps every node rect within the map bounds', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', -300, -100, size: const Size(120, 60)));
      c.addNode(node('b', 500, 400, size: const Size(200, 120)));

      const mapSize = Size(200, 140);
      final projection = computeMinimapProjection(
        contentBounds: minimapContentBounds(
          nodesBounds: c.nodesBounds,
          visibleArea: null,
        ),
        mapSize: mapSize,
      );

      final bounds = Offset.zero & mapSize;
      for (final n in c.nodes) {
        final rect = projection.graphRectToMap(n.bounds.rect);
        expect(bounds.contains(rect.topLeft), isTrue, reason: '${n.id} TL');
        expect(bounds.contains(rect.bottomRight), isTrue, reason: '${n.id} BR');
      }
    });

    test('collapses degenerate bounds to a finite centered mapping', () {
      final projection = computeMinimapProjection(
        contentBounds: const Rect.fromLTWH(50, 50, 0, 0),
        mapSize: const Size(200, 140),
      );
      final mapped = projection.graphToMap(const Offset(50, 50));
      expect(mapped.dx.isFinite, isTrue);
      expect(mapped.dy.isFinite, isTrue);
    });
  });

  group('viewportForMinimapTap', () {
    test('centers the tapped graph point on screen, preserving zoom', () {
      const projection = MinimapProjection(
        scale: 0.5,
        translation: Offset(10, 10),
      );
      // localTap (60,60) -> graph ((60-10)/0.5) = (100,100).
      final viewport = viewportForMinimapTap(
        localTap: const Offset(60, 60),
        projection: projection,
        zoom: 2,
        screenSize: const Size(800, 600),
      );

      expect(viewport.zoom, 2);
      expect(viewport.x, closeTo(800 / 2 - 100 * 2, 1e-9)); // 200
      expect(viewport.y, closeTo(600 / 2 - 100 * 2, 1e-9)); // 100
    });
  });

  group('minimapContentBounds', () {
    test('unions node bounds with the visible area', () {
      final union = minimapContentBounds(
        nodesBounds: GraphRect.fromLTWH(0, 0, 100, 100),
        visibleArea: GraphRect.fromLTWH(200, 200, 50, 50),
      );
      expect(union, const Rect.fromLTRB(0, 0, 250, 250));
    });

    test('falls back to whichever bound is present', () {
      expect(
        minimapContentBounds(
          nodesBounds: GraphRect.fromLTWH(1, 2, 3, 4),
          visibleArea: null,
        ),
        const Rect.fromLTWH(1, 2, 3, 4),
      );
      expect(
        minimapContentBounds(nodesBounds: null, visibleArea: null),
        Rect.zero,
      );
    });
  });

  group('Minimap widget', () {
    testWidgets('is mounted by default and omitted when minimap: false', (
      tester,
    ) async {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));

      Widget canvas({required bool minimap}) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: NodeFlow<String, String>(
              controller: c,
              fitViewOnLoad: false,
              animateEdges: false,
              minimap: minimap,
              nodeBuilder: (context, n) =>
                  const SizedBox(width: 120, height: 60),
            ),
          ),
        ),
      );

      await tester.pumpWidget(canvas(minimap: true));
      await tester.pumpAndSettle();
      expect(find.byType(Minimap<String, String>), findsOneWidget);

      await tester.pumpWidget(canvas(minimap: false));
      await tester.pumpAndSettle();
      expect(find.byType(Minimap<String, String>), findsNothing);
    });

    testWidgets('minimapMargin offsets it from the bottom-right corner', (
      tester,
    ) async {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: NodeFlow<String, String>(
                controller: c,
                fitViewOnLoad: false,
                animateEdges: false,
                minimapMargin: const EdgeInsets.only(right: 16, bottom: 80),
                nodeBuilder: (context, n) =>
                    const SizedBox(width: 120, height: 60),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final map = tester.getBottomRight(find.byType(Minimap<String, String>));
      final canvas = tester.getBottomRight(
        find.byType(NodeFlow<String, String>),
      );
      expect(canvas.dx - map.dx, 16);
      expect(canvas.dy - map.dy, 80);
    });

    testWidgets('node geometry changes invalidate the minimap painter', (
      tester,
    ) async {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));
      c.lastKnownScreenSize = const Size(800, 600);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Minimap<String, String>(
                controller: c,
                theme: const FlowTheme.dark(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final paint = tester.renderObject<RenderCustomPaint>(
        find.descendant(
          of: find.byType(Minimap<String, String>),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(paint.debugNeedsPaint, isFalse);

      c.getNode('a')!.position.value =
          const GraphPosition(Offset(100, 80));

      expect(paint.debugNeedsPaint, isTrue);
    });

    testWidgets('tapping the minimap pans the viewport', (tester) async {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', -400, -400, size: const Size(120, 60)));
      c.addNode(node('b', 400, 400, size: const Size(120, 60)));
      // Seed the screen size the recenter math needs (set by the canvas layout
      // in-app; set here since we pump the Minimap in isolation).
      c.lastKnownScreenSize = const Size(800, 600);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Minimap<String, String>(
                controller: c,
                theme: const FlowTheme.dark(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(c.viewport.value, const FlowViewport());

      // Tap near the top-left of the minimap: pans toward the graph top-left.
      final topLeft = tester.getTopLeft(find.byType(Minimap<String, String>));
      await tester.tapAt(topLeft + const Offset(20, 20));
      await tester.pump();

      expect(c.viewport.value, isNot(const FlowViewport()));
      // Zoom is preserved by a minimap pan.
      expect(c.viewport.value.zoom, 1.0);
    });
  });
}
