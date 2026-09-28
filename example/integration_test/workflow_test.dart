import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:node_flow/node_flow.dart';
import 'package:node_flow_example/demo_node.dart';
import 'package:node_flow_example/main.dart';

typedef DemoController = FlowController<DemoNode, Object?>;

Finder nodeCard(String id) => find.byKey(ValueKey<String>('node-$id'));

Future<DemoController> openRoute(WidgetTester tester, String route) async {
  await tester.pumpWidget(const NodeFlowExampleApp());
  await tester.tap(find.byKey(ValueKey<String>('route-$route')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump(const Duration(milliseconds: 100));
  final canvas = tester.widget<NodeFlow<DemoNode, Object?>>(
    find.byType(NodeFlow<DemoNode, Object?>),
  );
  return canvas.controller;
}

Future<void> dragPort(WidgetTester tester, String source, String target) async {
  final from = tester.getCenter(find.byKey(ValueKey<String>(source)));
  final to = tester.getCenter(find.byKey(ValueKey<String>(target)));
  final gesture = await tester.startGesture(
    from,
    kind: PointerDeviceKind.mouse,
  );
  var active = true;
  try {
    await tester.pump();
    await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    active = false;
  } finally {
    if (active) {
      await gesture.cancel();
    }
  }
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('camera zoom, pan, and fit update state and node layout', (
    tester,
  ) async {
    final controller = await openRoute(tester, 'static');
    final canvas = find.byType(NodeFlow<DemoNode, Object?>);
    final beforeZoom = controller.viewport.value.zoom;
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    expect(controller.viewport.value.zoom, greaterThan(beforeZoom));

    final beforePan = tester.getTopLeft(nodeCard('input'));
    final canvasRect = tester.getRect(canvas);
    await tester.dragFrom(
      canvasRect.bottomLeft + const Offset(50, -80),
      const Offset(90, 45),
    );
    await tester.pump();
    expect(tester.getTopLeft(nodeCard('input')).dx, greaterThan(beforePan.dx));

    await tester.tap(find.byTooltip('Fit to view'));
    await tester.pump();
    final visible = controller.viewport.value
        .getVisibleArea(canvasRect.size)
        .rect;
    final bounds = controller.nodesBounds!.rect;
    expect(visible.contains(bounds.topLeft), isTrue);
    expect(visible.contains(bounds.bottomRight), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing drag, multi-selection, and deletion update the canvas', (
    tester,
  ) async {
    final controller = await openRoute(tester, 'editing');
    // This scenario checks grid snapping. Alignment guides intentionally win
    // over the grid and depend on the demo cards' measured dimensions.
    controller.snapGuidesEnabled = false;
    final before = tester.getTopLeft(nodeCard('alpha'));
    final drag = await tester.startGesture(
      tester.getCenter(nodeCard('alpha')),
      kind: PointerDeviceKind.mouse,
    );
    var dragging = true;
    try {
      await drag.moveBy(const Offset(20, 20));
      await tester.pump();
      await drag.moveBy(const Offset(180, 110));
      await tester.pump();
      await drag.up();
      dragging = false;
    } finally {
      if (dragging) {
        await drag.cancel();
      }
    }
    await tester.pump();
    final moved = controller.getNode('alpha')!.position.value.offset;
    expect(moved, isNot(const Offset(-360, -160)));
    expect(
      moved.dx / controller.snapGrid,
      closeTo((moved.dx / controller.snapGrid).round(), 1e-6),
    );
    expect(
      moved.dy / controller.snapGrid,
      closeTo((moved.dy / controller.snapGrid).round(), 1e-6),
    );
    expect(tester.getTopLeft(nodeCard('alpha')), isNot(before));

    await tester.tap(nodeCard('alpha'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    try {
      await tester.tap(nodeCard('bravo'));
      await tester.pump(const Duration(milliseconds: 400));
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    }
    await tester.pump();
    expect(controller.selection.value, containsAll(<String>['alpha', 'bravo']));

    await tester.tap(find.byTooltip('Delete selection'));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('node-alpha')), findsNothing);
    expect(find.byKey(const ValueKey<String>('node-bravo')), findsNothing);
    expect(find.byKey(const ValueKey<String>('node-charlie')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing controls update status and focus without losing state', (
    tester,
  ) async {
    final controller = await openRoute(tester, 'editing');
    await tester.tap(nodeCard('alpha'));
    await tester.pump(const Duration(milliseconds: 400));
    final position = controller.getNode('alpha')!.position.value;
    final zoom = controller.viewport.value.zoom;

    await tester.tap(find.byTooltip('Toggle Alpha status'));
    await tester.pump();
    expect(controller.getNode('alpha')!.data.status, DemoStatus.running);
    expect(
      find.descendant(of: nodeCard('alpha'), matching: find.text('Running')),
      findsOneWidget,
    );
    expect(controller.selection.value, {'alpha'});
    expect(controller.getNode('alpha')!.position.value, position);

    await tester.tap(find.byTooltip('Focus Alpha'));
    await tester.pump();
    final canvas = find.byType(NodeFlow<DemoNode, Object?>);
    expect(
      (tester.getCenter(nodeCard('alpha')) - tester.getCenter(canvas)).distance,
      lessThan(1),
    );
    expect(controller.viewport.value.zoom, zoom);

    await tester.tap(find.byTooltip('Toggle Alpha status'));
    await tester.pump();
    expect(controller.getNode('alpha')!.data.status, DemoStatus.idle);
    await tester.tap(find.byTooltip('Delete selection'));
    await tester.pump();
    await tester.tap(find.byTooltip('Focus Alpha'));
    await tester.tap(find.byTooltip('Toggle Alpha status'));
    await tester.pump();
    expect(nodeCard('alpha'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double tap and secondary click open node details', (
    tester,
  ) async {
    final controller = await openRoute(tester, 'editing');
    final alpha = tester.getCenter(nodeCard('alpha'));
    await tester.tapAt(alpha);
    await tester.pump(const Duration(milliseconds: 90));
    await tester.tapAt(alpha);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Node ID: alpha'), findsOneWidget);
    expect(controller.selection.value, {'alpha'});
    await tester.tap(find.text('Close'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Node ID: alpha'), findsNothing);

    final bravo = tester.getCenter(nodeCard('bravo'));
    final secondary = await tester.startGesture(
      bravo,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await secondary.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Node ID: bravo'), findsOneWidget);
    expect(controller.selection.value, {'alpha'});
    await tester.tap(find.text('Close'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Shift-drag marquee selects only enclosed nodes', (tester) async {
    final controller = await openRoute(tester, 'editing');
    final alpha = tester.getRect(nodeCard('alpha'));
    final bravo = tester.getRect(nodeCard('bravo'));
    final start = alpha.topLeft - const Offset(15, 15);
    final end = bravo.bottomRight + const Offset(15, 15);
    TestGesture? marquee;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    try {
      await tester.pump();
      marquee = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
      await marquee.moveTo(Offset.lerp(start, end, 0.5)!);
      await tester.pump();
      await marquee.moveTo(end);
      await tester.pump();
      await marquee.up();
      marquee = null;
      await tester.pump();
    } finally {
      await marquee?.cancel();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
    }
    expect(controller.selection.value, <String>{'alpha', 'bravo'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('connection cancel, accept, dedupe, and rejection', (
    tester,
  ) async {
    final controller = await openRoute(tester, 'connect');
    final from = tester.getCenter(
      find.byKey(const ValueKey<String>('port-source-b-out')),
    );
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    var active = true;
    try {
      await tester.pump();
      await gesture.moveBy(const Offset(60, 80));
      await tester.pump();
      await gesture.cancel();
      active = false;
    } finally {
      if (active) {
        await gesture.cancel();
      }
    }
    await tester.pump();
    expect(controller.pendingConnection.value, isNull);
    expect(controller.edges, isEmpty);

    await dragPort(tester, 'port-source-a-out', 'port-target-in');
    expect(controller.edges, hasLength(1));
    expect(controller.edges.single.sourceNodeId, 'source-a');
    await dragPort(tester, 'port-source-a-out', 'port-target-in');
    expect(controller.edges, hasLength(1));

    final secondSource = tester.getCenter(
      find.byKey(const ValueKey<String>('port-source-b-out')),
    );
    final target = tester.getCenter(
      find.byKey(const ValueKey<String>('port-target-in')),
    );
    final rejected = await tester.startGesture(
      secondSource,
      kind: PointerDeviceKind.mouse,
    );
    await rejected.moveTo(target);
    await tester.pump();
    expect(controller.pendingConnection.value?.hasTarget, isFalse);
    await rejected.up();
    await tester.pump();
    expect(controller.edges, hasLength(1));
    expect(controller.pendingConnection.value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving a connection drag clears the old route', (tester) async {
    final oldController = await openRoute(tester, 'connect');
    final from = tester.getCenter(
      find.byKey(const ValueKey<String>('port-source-a-out')),
    );
    TestGesture? connection;
    try {
      connection = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await connection.moveBy(const Offset(100, 20));
      await tester.pump();
      expect(oldController.pendingConnection.value, isNotNull);
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(
        find.byKey(const ValueKey<String>('route-connect')),
        findsOneWidget,
      );
    } finally {
      await connection?.cancel();
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey<String>('route-connect')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    final newController = tester
        .widget<NodeFlow<DemoNode, Object?>>(
          find.byType(NodeFlow<DemoNode, Object?>),
        )
        .controller;
    expect(identical(newController, oldController), isFalse);
    expect(newController.pendingConnection.value, isNull);
    await dragPort(tester, 'port-source-a-out', 'port-target-in');
    expect(newController.edges, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('edges select, delete, accent, and follow node movement', (
    tester,
  ) async {
    final controller = await openRoute(tester, 'edges');
    final edge = controller.getEdge('e-input-condition')!;
    final source = controller.getNode('input')!;
    final target = controller.getNode('condition')!;
    final sourceAnchor = portAnchor(source, source.ports.single);
    final targetAnchor = portAnchor(target, target.ports.first);
    final midpoint = GraphPosition.fromXY(
      (sourceAnchor.dx + targetAnchor.dx) / 2,
      (sourceAnchor.dy + targetAnchor.dy) / 2,
    );
    final canvas = find.byType(NodeFlow<DemoNode, Object?>);
    final screen = controller.graphToScreen(midpoint).offset;
    await tester.tapAt(tester.getTopLeft(canvas) + screen);
    await tester.pump();
    expect(edge.selected.value, isTrue);

    await tester.tap(find.byTooltip('Accent the TRUE path'));
    await tester.pump();
    expect(edge.accent, isNotNull);
    expect(controller.getEdge('e-true')!.accent, edge.accent);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(controller.getEdge('e-input-condition'), isNull);
    expect(controller.getEdge('e-false'), isNotNull);

    final before = controller.getNode('accept')!.position.value;
    await tester.drag(nodeCard('accept'), const Offset(43, 23));
    await tester.pump();
    expect(controller.getNode('accept')!.position.value, isNot(before));
    expect(controller.getEdge('e-true'), isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('minimap pan preserves zoom and node drag updates the graph', (
    tester,
  ) async {
    final controller = await openRoute(tester, 'edges');
    final nodeBefore = controller.getNode('condition')!.position.value;
    final nodeDrag = await tester.startGesture(
      tester.getCenter(nodeCard('condition')),
      kind: PointerDeviceKind.mouse,
    );
    var dragging = true;
    try {
      await nodeDrag.moveBy(const Offset(20, 20));
      await tester.pump();
      await nodeDrag.moveBy(const Offset(120, 70));
      await tester.pump();
      await nodeDrag.up();
      dragging = false;
    } finally {
      if (dragging) {
        await nodeDrag.cancel();
      }
    }
    await tester.pump();
    expect(controller.getNode('condition')!.position.value, isNot(nodeBefore));

    final minimap = find.byType(Minimap<DemoNode, Object?>);
    final zoom = controller.viewport.value.zoom;
    final before = controller.viewport.value;
    final topLeft = tester.getTopLeft(minimap);
    await tester.tapAt(topLeft + const Offset(25, 25));
    await tester.pump();
    expect(controller.viewport.value, isNot(before));
    expect(controller.viewport.value.zoom, zoom);

    final afterTap = controller.viewport.value;
    await tester.dragFrom(topLeft + const Offset(45, 45), const Offset(45, 25));
    await tester.pump();
    expect(controller.viewport.value, isNot(afterTap));

    expect(tester.takeException(), isNull);
  });
}
