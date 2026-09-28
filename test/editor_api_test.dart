import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:node_flow/node_flow.dart';

FlowNode<String> _node({bool locked = false}) => FlowNode<String>(
  id: 'job',
  type: 'task',
  data: 'idle',
  position: const GraphPosition(Offset(100, 150)),
  ports: const [
    FlowPort(id: 'out', side: PortSide.right, kind: PortKind.output),
  ],
  locked: locked,
);

void main() {
  test('data updates preserve graph and node interaction state', () {
    final controller = FlowController<String, void>();
    addTearDown(controller.dispose);
    final original = _node(locked: true);
    controller.addNode(original);
    original.measuredSize.value = const Size(180, 90);
    original.zIndex.value = 7;
    controller.select(['job']);
    final edge = FlowEdge<void>(
      id: 'edge',
      sourceNodeId: 'job',
      sourcePortId: 'out',
      targetNodeId: 'external',
      targetPortId: 'in',
    );
    controller.addEdge(edge);

    expect(
      controller.updateNodeData('job', (data) => '$data -> running'),
      isTrue,
    );

    final updated = controller.getNode('job')!;
    expect(updated.data, 'idle -> running');
    expect(updated.type, 'task');
    expect(updated.position.value, const GraphPosition(Offset(100, 150)));
    expect(updated.measuredSize.value, const Size(180, 90));
    expect(updated.zIndex.value, 7);
    expect(updated.selected.value, isTrue);
    expect(controller.selection.value, {'job'});
    expect(updated.locked, isTrue);
    expect(updated.ports.single.id, 'out');
    expect(controller.getEdge('edge'), same(edge));
  });

  test('data update preserves an active drag and its next delta', () {
    final controller = FlowController<String, void>();
    addTearDown(controller.dispose);
    controller.addNode(_node());
    controller.beginNodeDrag('job');
    controller.moveNodeBy('job', const GraphOffset(Offset(13, 17)));

    controller.updateNodeData('job', (_) => 'running');
    expect(controller.draggingNodeIds.value, {'job'});
    controller.moveNodeBy('job', const GraphOffset(Offset(5, 3)));
    expect(
      controller.getNode('job')!.position.value,
      const GraphPosition(Offset(118, 170)),
    );
    controller.endNodeDrag();
    expect(controller.getNode('job')!.data, 'running');
    expect(controller.draggingNodeIds.value, isEmpty);
  });

  test('cancelling a drag restores position but keeps updated data', () {
    final controller = FlowController<String, void>();
    addTearDown(controller.dispose);
    controller.addNode(_node());
    final initialPosition = controller.getNode('job')!.position.value;
    controller.beginNodeDrag('job');
    controller.moveNodeBy('job', const GraphOffset(Offset(13, 17)));
    controller.updateNodeData('job', (_) => 'running');

    controller.cancelNodeDrag();

    expect(controller.getNode('job')!.position.value, initialPosition);
    expect(controller.getNode('job')!.data, 'running');
    expect(controller.draggingNodeIds.value, isEmpty);
    expect(controller.mode.value, FlowInteractionMode.idle);
  });

  test(
    'missing node skips updater; throwing updater leaves node unchanged',
    () {
      final controller = FlowController<String, void>();
      addTearDown(controller.dispose);
      var calls = 0;
      expect(
        controller.updateNodeData('missing', (_) {
          calls++;
          return 'running';
        }),
        isFalse,
      );
      expect(calls, 0);
      final original = _node();
      controller.addNode(original);
      final version = controller.structureVersion.value;
      expect(
        () =>
            controller.updateNodeData('job', (_) => throw StateError('failed')),
        throwsStateError,
      );
      expect(controller.getNode('job'), same(original));
      expect(original.data, 'idle');
      expect(controller.structureVersion.value, version);
    },
  );

  test(
    'centering uses known size, explicit size wins, unavailable is a no-op',
    () {
      final controller = FlowController<String, void>(
        initialViewport: const FlowViewport(zoom: 2),
      );
      addTearDown(controller.dispose);
      controller.addNode(_node());
      controller.getNode('job')!.measuredSize.value = const Size(100, 50);
      controller.centerOnNode('job');
      expect(controller.viewport.value, const FlowViewport(zoom: 2));

      controller.lastKnownScreenSize = const Size(800, 600);
      controller.centerOnNode('job');
      expect(
        controller.viewport.value,
        const FlowViewport(x: 100, y: -50, zoom: 2),
      );
      controller.centerOnNode('job', const Size(1000, 800));
      expect(
        controller.viewport.value,
        const FlowViewport(x: 200, y: 50, zoom: 2),
      );
      final before = controller.viewport.value;
      controller.centerOnNode('missing');
      controller.centerOnNode('job', Size.zero);
      expect(controller.viewport.value, before);
    },
  );

  testWidgets(
    'mounted data updates resize the node and navigation centers it',
    (tester) async {
      final controller = FlowController<String, void>();
      addTearDown(controller.dispose);
      controller.addNode(_node());
      await tester.pumpWidget(
        MaterialApp(
          home: NodeFlow<String, void>(
            key: const ValueKey('canvas'),
            controller: controller,
            fitViewOnLoad: false,
            animateEdges: false,
            nodeBuilder: (context, node) => SizedBox(
              key: const ValueKey('job-card'),
              width: node.data == 'idle' ? 100 : 200,
              height: 60,
              child: Text(node.data),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('idle'), findsOneWidget);
      controller.updateNodeData('job', (_) => 'running');
      await tester.pump();
      await tester.pump();
      expect(find.text('running'), findsOneWidget);
      expect(find.text('idle'), findsNothing);
      expect(
        controller.getNode('job')!.measuredSize.value,
        const Size(200, 60),
      );

      controller.centerOnNode('job');
      await tester.pump();
      expect(
        tester.getCenter(find.byKey(const ValueKey('job-card'))),
        tester.getCenter(find.byKey(const ValueKey('canvas'))),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
