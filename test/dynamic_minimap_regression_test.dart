import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderCustomPaint;
import 'package:flutter_test/flutter_test.dart';
import 'package:node_flow/src/render/edges_painter.dart';
import 'package:node_flow/node_flow.dart';

FlowNode<String> node(String id) => FlowNode(
  id: id,
  type: 'test',
  data: id,
  position: const GraphPosition(Offset.zero),
  size: const Size(120, 60),
);

FlowNode<String> nodeAt(String id, Offset position) => FlowNode(
  id: id,
  type: 'test',
  data: id,
  position: GraphPosition(position),
  size: const Size(10, 10),
);

void main() {
  testWidgets('minimap repaints when membership changes within equal bounds', (
    tester,
  ) async {
    final controller = FlowController<String, String>();
    addTearDown(controller.dispose);
    controller.addNode(nodeAt('top-left', Offset.zero));
    controller.addNode(nodeAt('bottom-right', const Offset(100, 100)));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Minimap<String, String>(
              controller: controller,
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
    controller.addNode(nodeAt('middle', const Offset(50, 50)));
    expect(paint.debugNeedsPaint, isTrue);
  });

  testWidgets('minimap tracks geometry of nodes added after mount', (
    tester,
  ) async {
    final controller = FlowController<String, String>();
    addTearDown(controller.dispose);
    controller.addNode(node('first'));
    controller.lastKnownScreenSize = const Size(800, 600);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Minimap<String, String>(
              controller: controller,
              theme: const FlowTheme.dark(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final added = node('added');
    controller.addNode(added);
    await tester.pump();
    final paint = tester.renderObject<RenderCustomPaint>(
      find.descendant(
        of: find.byType(Minimap<String, String>),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(paint.debugNeedsPaint, isFalse);
    added.position.value = const GraphPosition(Offset(100, 80));
    expect(paint.debugNeedsPaint, isTrue);
  });

  testWidgets('minimap tracks geometry of replacement nodes', (tester) async {
    final controller = FlowController<String, String>();
    addTearDown(controller.dispose);
    controller.addNode(node('first'));
    controller.lastKnownScreenSize = const Size(800, 600);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Minimap<String, String>(
              controller: controller,
              theme: const FlowTheme.dark(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final replacement = node('first');
    controller.replaceNode(replacement);
    await tester.pump();
    final paint = tester.renderObject<RenderCustomPaint>(
      find.descendant(
        of: find.byType(Minimap<String, String>),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(paint.debugNeedsPaint, isFalse);
    replacement.measuredSize.value = const Size(150, 80);
    expect(paint.debugNeedsPaint, isTrue);
  });

  test('minimap painter invalidates on controller replacement', () {
    final a = FlowController<String, String>();
    final b = FlowController<String, String>();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    const theme = FlowTheme.dark();
    const projection = MinimapProjection(scale: 1, translation: Offset.zero);

    final oldPainter = MinimapPainter<String, String>(
      controller: a,
      theme: theme,
      projection: projection,
      visibleArea: null,
      repaint: a.viewport,
    );
    final newPainter = MinimapPainter<String, String>(
      controller: b,
      theme: theme,
      projection: projection,
      visibleArea: null,
      repaint: b.viewport,
    );
    expect(newPainter.shouldRepaint(oldPainter), isTrue);
  });

  test('edge painter invalidates on controller replacement', () {
    final a = FlowController<String, String>();
    final b = FlowController<String, String>();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    const theme = FlowTheme.dark();
    const dash = AlwaysStoppedAnimation<double>(0);
    const dragging = <String>{};

    EdgesPainter<String, String> painter(FlowController<String, String> c) =>
        EdgesPainter<String, String>(
          controller: c,
          theme: theme,
          style: FlowEdgeStyle.bezier,
          dash: dash,
          dragging: dragging,
          includeDragging: false,
          repaint: c.viewport,
        );
    expect(painter(b).shouldRepaint(painter(a)), isTrue);
  });
}
