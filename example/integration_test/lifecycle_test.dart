import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:node_flow/node_flow.dart';

import 'support/lifecycle_fixture.dart';

List<double> _region(Rect rect) => <double>[
  rect.left,
  rect.top,
  rect.width,
  rect.height,
];

Future<void> _capture(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name, {
  String? compareWith,
  bool expectChange = true,
  Rect? region,
}) async {
  // ChromeDriver screenshots use browser pixels; CI pins device pixel ratio 1.
  final minimap = tester.getRect(
    find.byType(Minimap<FixtureNodeData, Object?>),
  );
  final canvas = tester.getRect(
    find.byType(NodeFlow<FixtureNodeData, Object?>),
  );
  final args = <String, Object?>{
    'expectChange': expectChange,
    'region': _region(region ?? minimap.deflate(4)),
    'controlRegion': _region(
      Rect.fromLTWH(canvas.left + 20, canvas.bottom - 120, 80, 70),
    ),
  };
  if (compareWith != null) args['compareWith'] = compareWith;
  await binding.takeScreenshot(name, args);
}

Future<void> _tapControl(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(ValueKey<String>('fixture-$name')));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('minimap paints insertion, movement, replacement, and resize', (
    tester,
  ) async {
    await tester.pumpWidget(const LifecycleFixture());
    await tester.pump(const Duration(milliseconds: 300));
    final fixture = tester.state<LifecycleFixtureState>(
      find.byType(LifecycleFixture),
    );
    fixture.refreshProjection();
    await tester.pump();
    expect(fixture.controllerA.lastKnownScreenSize, isNotNull);
    final originalBounds = fixture.controllerA.nodesBounds!.rect;
    final originalVisibleArea = fixture.controllerA.viewport.value
        .getVisibleArea(fixture.controllerA.lastKnownScreenSize!)
        .rect;
    await _capture(tester, binding, 'minimap-initial');

    await _tapControl(tester, 'add');
    expect(fixture.controllerA.nodesBounds!.rect, originalBounds);
    expect(
      fixture.controllerA.viewport.value
          .getVisibleArea(fixture.controllerA.lastKnownScreenSize!)
          .rect,
      originalVisibleArea,
    );
    expect(
      find.byKey(const ValueKey<String>('fixture-node-interior')),
      findsOneWidget,
    );
    await _capture(
      tester,
      binding,
      'minimap-added',
      compareWith: 'minimap-initial',
    );

    await _tapControl(tester, 'move');
    await _capture(
      tester,
      binding,
      'minimap-moved',
      compareWith: 'minimap-added',
    );

    await _tapControl(tester, 'replace');
    await _capture(
      tester,
      binding,
      'minimap-replaced',
      compareWith: 'minimap-moved',
    );

    await _tapControl(tester, 'resize');
    expect(
      fixture.controllerA.getNode('interior')!.measuredSize.value,
      const Size(160, 85),
    );
    await _capture(
      tester,
      binding,
      'minimap-resized',
      compareWith: 'minimap-replaced',
    );

    await _tapControl(tester, 'remove');
    expect(fixture.controllerA.getNode('interior'), isNull);
    await _capture(
      tester,
      binding,
      'minimap-removed',
      compareWith: 'minimap-resized',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('equal-projection controller swap repaints and detaches', (
    tester,
  ) async {
    await tester.pumpWidget(const LifecycleFixture());
    await tester.pump(const Duration(milliseconds: 300));
    final fixture = tester.state<LifecycleFixtureState>(
      find.byType(LifecycleFixture),
    );
    fixture.refreshProjection();
    await tester.pump();
    expect(fixture.controllerA.nodesBounds, fixture.controllerB.nodesBounds);
    await _capture(tester, binding, 'swap-a');

    await _tapControl(tester, 'b');
    fixture.refreshProjection();
    await tester.pump();
    expect(
      fixture.controllerA.lastKnownScreenSize,
      fixture.controllerB.lastKnownScreenSize,
    );
    expect(
      fixture.controllerA.viewport.value,
      fixture.controllerB.viewport.value,
    );
    expect(
      find.byKey(const ValueKey<String>('fixture-node-b-interior')),
      findsOneWidget,
    );
    await _capture(tester, binding, 'swap-b', compareWith: 'swap-a');

    await _tapControl(tester, 'detached');
    expect(fixture.controllerA.getNode('detached-change'), isNotNull);
    expect(
      find.byKey(const ValueKey<String>('fixture-node-detached-change')),
      findsNothing,
    );
    await _capture(
      tester,
      binding,
      'swap-b-detached-a-mutated',
      compareWith: 'swap-b',
      expectChange: false,
    );

    await _tapControl(tester, 'a');
    fixture.refreshProjection();
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('fixture-node-detached-change')),
      findsOneWidget,
    );
    await _capture(
      tester,
      binding,
      'swap-a-returned',
      compareWith: 'swap-b-detached-a-mutated',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('static edge paints accent, movement, and deletion', (
    tester,
  ) async {
    await tester.pumpWidget(const LifecycleFixture());
    await tester.pump(const Duration(milliseconds: 300));
    final fixture = tester.state<LifecycleFixtureState>(
      find.byType(LifecycleFixture),
    );
    final controller = fixture.controllerA;
    final left = controller.getNode('left')!;
    final right = controller.getNode('right')!;
    final source = controller.graphToScreen(
      portAnchor(left, left.ports.single),
    );
    final target = controller.graphToScreen(
      portAnchor(right, right.ports.single),
    );
    final canvas = tester.getRect(
      find.byType(NodeFlow<FixtureNodeData, Object?>),
    );
    final midpoint = Offset(
      (source.dx + target.dx) / 2 + canvas.left,
      (source.dy + target.dy) / 2 + canvas.top,
    );
    final edgeRegion = Rect.fromCenter(
      center: midpoint,
      width: 250,
      height: 180,
    );
    await _capture(tester, binding, 'edge-default', region: edgeRegion);

    await _tapControl(tester, 'accent-edge');
    expect(controller.getEdge('fixture-edge')!.accent, isNotNull);
    await _capture(
      tester,
      binding,
      'edge-accented',
      compareWith: 'edge-default',
      region: edgeRegion,
    );

    await _tapControl(tester, 'move-edge-target');
    expect(right.position.value, const GraphPosition(Offset(600, 340)));
    await _capture(
      tester,
      binding,
      'edge-moved',
      compareWith: 'edge-accented',
      region: edgeRegion,
    );

    await _tapControl(tester, 'delete-edge');
    expect(controller.getEdge('fixture-edge'), isNull);
    await _capture(
      tester,
      binding,
      'edge-deleted',
      compareWith: 'edge-moved',
      region: edgeRegion,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
