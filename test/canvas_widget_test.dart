import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:node_flow/node_flow.dart';

FlowNode<String> node(String id, double x, double y, {Size? size}) => FlowNode(
  id: id,
  type: 'test',
  data: id,
  position: GraphPosition(Offset(x, y)),
  size: size ?? const Size(120, 60),
);

/// Pumps a canvas sized to [size] with `fitViewOnLoad` off and the identity
/// viewport, so graph coordinates equal screen coordinates (zoom 1, no pan).
Future<void> pumpCanvas(
  WidgetTester tester,
  FlowController<String, String> controller, {
  Size size = const Size(800, 600),
  Widget Function(BuildContext, FlowNode<String>)? nodeBuilder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: NodeFlow<String, String>(
              controller: controller,
              fitViewOnLoad: false,
              minimap: false,
              nodeBuilder:
                  nodeBuilder ??
                  (context, n) => Container(
                    key: ValueKey<String>('card-${n.id}'),
                    width: n.measuredSize.value.width,
                    height: n.measuredSize.value.height,
                    color: const Color(0xFF2266AA),
                  ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('nodes appear at their graph position (identity viewport)', (
    tester,
  ) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);
    c.addNode(node('a', 100, 80, size: const Size(120, 60)));
    await pumpCanvas(tester, c);

    final canvasTopLeft = tester.getTopLeft(
      find.byType(NodeFlow<String, String>),
    );
    final cardTopLeft = tester.getTopLeft(find.byKey(const ValueKey('card-a')));

    // Node at graph (100, 80) renders at canvas origin + (100, 80).
    expect(cardTopLeft.dx - canvasTopLeft.dx, closeTo(100, 0.5));
    expect(cardTopLeft.dy - canvasTopLeft.dy, closeTo(80, 0.5));
  });

  testWidgets('tap selects a node', (tester) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);
    c.addNode(node('a', 100, 80));
    await pumpCanvas(tester, c);

    expect(c.getNode('a')!.selected.value, isFalse);
    await tester.tap(find.byKey(const ValueKey('card-a')));
    await tester.pump();

    expect(c.getNode('a')!.selected.value, isTrue);
    expect(c.selection.value, unorderedEquals(<String>['a']));
  });

  testWidgets('shift-tap adds to the selection', (tester) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);
    c.addNode(node('a', 40, 40));
    c.addNode(node('b', 300, 40));
    await pumpCanvas(tester, c);

    await tester.tap(find.byKey(const ValueKey('card-a')));
    await tester.pump();
    expect(c.selection.value, unorderedEquals(<String>['a']));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byKey(const ValueKey('card-b')));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(c.selection.value, unorderedEquals(<String>['a', 'b']));
  });

  testWidgets('dragging a node (mouse) moves it and snaps on release', (
    tester,
  ) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);
    c.addNode(node('a', 0, 0, size: const Size(120, 60)));
    await pumpCanvas(tester, c);

    // Node drags are mouse-only by design (trackpad/touch bubble to the canvas
    // for panning). At zoom 1, screen delta == graph delta.
    await tester.drag(
      find.byKey(const ValueKey('card-a')),
      const Offset(140, 100),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    // Moved from the origin and snapped to the 20-grid on release.
    final pos = c.getNode('a')!.position.value.offset;
    expect(pos, isNot(Offset.zero));
    expect(pos.dx % 20, 0);
    expect(pos.dy % 20, 0);
    expect(pos.dx, greaterThan(0));
    expect(pos.dy, greaterThan(0));
    // Canvas did not pan while the node was dragged.
    expect(c.viewport.value, const FlowViewport());
  });

  testWidgets('tapping empty canvas clears the selection', (tester) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);
    c.addNode(node('a', 40, 40));
    await pumpCanvas(tester, c);

    await tester.tap(find.byKey(const ValueKey('card-a')));
    await tester.pump();
    expect(c.selection.value, isNotEmpty);

    // Tap far from any node.
    await tester.tapAt(
      tester.getCenter(find.byType(NodeFlow<String, String>)) +
          const Offset(250, 200),
    );
    await tester.pump();
    expect(c.selection.value, isEmpty);
  });

  testWidgets('reports the child laid-out size into measuredSize', (
    tester,
  ) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);
    // Seed with a wrong size; the intrinsic-height child should override it.
    c.addNode(node('a', 20, 20, size: const Size(10, 10)));

    await pumpCanvas(
      tester,
      c,
      nodeBuilder: (context, n) => const SizedBox(
        key: ValueKey<String>('card-a'),
        width: 256,
        height: 140,
      ),
    );

    expect(c.getNode('a')!.measuredSize.value, const Size(256, 140));
  });

  testWidgets('many small drag events escape an alignment guide', (
    tester,
  ) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);
    c.addNode(node('anchor', 0, 0, size: const Size(120, 60)));
    c.addNode(node('a', 4, 300, size: const Size(120, 60)));
    await pumpCanvas(tester, c);

    // Regression for the snap feedback loop: 1px-per-event mouse movement
    // (the shape of a slow, precise drag) used to be cancelled forever once
    // the node snapped onto the anchor's guide.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('card-a'))),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 30; i += 1) {
      await gesture.moveBy(const Offset(1, 0));
    }
    await tester.pump();

    // Escaped the guide at x=0 and tracked the pointer (was: pinned at 0).
    final dragged = c.getNode('a')!.position.value.dx;
    expect(dragged, greaterThan(20));
    expect(c.activeGuides.value, isEmpty);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(c.getNode('a')!.position.value.dx % 20, 0);
  });

  testWidgets('at zoom 2 screen deltas convert to graph units', (tester) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);
    c.setViewport(const FlowViewport(zoom: 2));
    c.addNode(node('a', 10, 10, size: const Size(120, 60)));
    await pumpCanvas(tester, c);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('card-a'))),
      kind: PointerDeviceKind.mouse,
    );
    // A short move to spend the 2px mouse pan slop, then the real travel.
    await gesture.moveBy(const Offset(3, 0));
    await gesture.moveBy(const Offset(42, 0));
    await tester.pump();

    // ~45 screen px minus slop, divided by zoom 2 => ~21 graph units.
    expect(c.getNode('a')!.position.value.dx, closeTo(31, 1.5));
    expect(c.getNode('a')!.position.value.dy, 10);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(c.getNode('a')!.position.value.dx % 20, 0);
  });

  testWidgets('locked node does not move on drag', (tester) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);
    c.addNode(node('a', 20, 20)..locked = true);
    await pumpCanvas(tester, c);

    await tester.drag(
      find.byKey(const ValueKey('card-a')),
      const Offset(60, 60),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(c.getNode('a')!.position.value.offset, const Offset(20, 20));
  });
}
