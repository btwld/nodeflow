import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:node_flow/node_flow.dart';

FlowController<String, String> _controller(FlowViewport viewport) {
  final controller = FlowController<String, String>(initialViewport: viewport);
  controller.addNode(
    FlowNode<String>(
      id: 'node',
      type: 'card',
      data: 'node',
      position: const GraphPosition(Offset(30, 40)),
      size: const Size(80, 40),
    ),
  );
  return controller;
}

Widget _canvas(FlowController<String, String> controller) {
  return MaterialApp(
    home: SizedBox(
      width: 800,
      height: 600,
      child: NodeFlow<String, String>(
        key: const ValueKey<String>('canvas'),
        controller: controller,
        fitViewOnLoad: false,
        animateEdges: false,
        minimap: false,
        snapGuides: false,
        nodeBuilder: (context, node) => SizedBox(
          key: ValueKey<String>('node-card-${node.id}'),
          width: 80,
          height: 40,
        ),
      ),
    ),
  );
}

Offset _cardOffset(WidgetTester tester) {
  final card = tester.getTopLeft(find.byKey(const ValueKey('node-card-node')));
  final canvas = tester.getTopLeft(find.byKey(const ValueKey('canvas')));
  return card - canvas;
}

void main() {
  testWidgets('swapping controllers updates the viewport source', (
    tester,
  ) async {
    final first = _controller(const FlowViewport());
    final second = _controller(const FlowViewport(x: 120, y: 80, zoom: 1.5));
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(_canvas(first));
    await tester.pump();
    final state = tester.state(find.byKey(const ValueKey('canvas')));
    expect(_cardOffset(tester), const Offset(30, 40));

    await tester.pumpWidget(_canvas(second));
    await tester.pump();

    expect(tester.state(find.byKey(const ValueKey('canvas'))), same(state));
    expect(_cardOffset(tester), const Offset(165, 140));

    second.setViewport(const FlowViewport(x: 40, y: 20, zoom: 2));
    await tester.pump();
    expect(_cardOffset(tester), const Offset(100, 100));

    first.setViewport(const FlowViewport(x: 900, y: 900));
    await tester.pump();
    expect(_cardOffset(tester), const Offset(100, 100));
    expect(second.viewport.value, const FlowViewport(x: 40, y: 20, zoom: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching A to B to A rebinds the active controller', (
    tester,
  ) async {
    final first = _controller(const FlowViewport());
    final second = _controller(const FlowViewport(x: 120, y: 80, zoom: 1.5));
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(_canvas(first));
    final state = tester.state(find.byKey(const ValueKey('canvas')));
    expect(_cardOffset(tester), const Offset(30, 40));

    await tester.pumpWidget(_canvas(second));
    expect(tester.state(find.byKey(const ValueKey('canvas'))), same(state));
    expect(_cardOffset(tester), const Offset(165, 140));

    first.setViewport(const FlowViewport(x: 30, y: 20, zoom: 1.25));
    await tester.pump();
    expect(_cardOffset(tester), const Offset(165, 140));

    await tester.pumpWidget(_canvas(first));
    expect(tester.state(find.byKey(const ValueKey('canvas'))), same(state));
    expect(_cardOffset(tester), const Offset(67.5, 70));

    second.setViewport(const FlowViewport(x: 500, y: 500));
    await tester.pump();
    expect(_cardOffset(tester), const Offset(67.5, 70));

    first.setViewport(const FlowViewport(x: 40, y: 10, zoom: 2));
    await tester.pump();
    expect(_cardOffset(tester), const Offset(100, 90));
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching A to B to A follows graph structure changes', (
    tester,
  ) async {
    final first = _controller(const FlowViewport());
    final second = _controller(const FlowViewport());
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(_canvas(first));
    await tester.pump();
    expect(find.byKey(const ValueKey('node-card-node')), findsOneWidget);

    await tester.pumpWidget(_canvas(second));
    await tester.pump();
    first.addNode(
      FlowNode<String>(
        id: 'first-extra',
        type: 'card',
        data: 'first-extra',
        position: const GraphPosition(Offset(100, 100)),
        size: const Size(80, 40),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('node-card-first-extra')), findsNothing);

    second.addNode(
      FlowNode<String>(
        id: 'second-extra',
        type: 'card',
        data: 'second-extra',
        position: const GraphPosition(Offset(100, 100)),
        size: const Size(80, 40),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('node-card-second-extra')),
      findsOneWidget,
    );

    await tester.pumpWidget(_canvas(first));
    await tester.pump();
    expect(find.byKey(const ValueKey('node-card-first-extra')), findsOneWidget);
    second.addNode(
      FlowNode<String>(
        id: 'second-late',
        type: 'card',
        data: 'second-late',
        position: const GraphPosition(Offset(200, 100)),
        size: const Size(80, 40),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('node-card-second-late')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swapping controllers aborts transient interaction state', (
    tester,
  ) async {
    final first = _controller(const FlowViewport());
    final second = _controller(const FlowViewport());
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(_canvas(first));
    await tester.pump();

    first.beginConnection(
      'node',
      const FlowPort(id: 'out', side: PortSide.right, kind: PortKind.output),
      GraphPosition.zero,
    );
    expect(first.mode.value, FlowInteractionMode.draggingConnection);
    expect(first.pendingConnection.value, isNotNull);

    await tester.pumpWidget(_canvas(second));
    await tester.pump();

    expect(first.mode.value, FlowInteractionMode.idle);
    expect(first.pendingConnection.value, isNull);
  });

  testWidgets('controllers remain usable after canvas disposal', (
    tester,
  ) async {
    final first = _controller(const FlowViewport());
    final second = _controller(const FlowViewport());
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(_canvas(first));
    await tester.pump();
    await tester.pumpWidget(_canvas(second));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());

    first.setViewport(const FlowViewport(x: 10));
    expect(tester.takeException(), isNull);

    second.setViewport(const FlowViewport(y: 20));
    expect(tester.takeException(), isNull);

    expect(first.viewport.value, const FlowViewport(x: 10));
    expect(second.viewport.value, const FlowViewport(y: 20));
  });
}
