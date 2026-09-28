import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:node_flow/node_flow.dart';

const _outPort = FlowPort(
  id: 'out',
  side: PortSide.right,
  kind: PortKind.output,
);
const _inPort = FlowPort(id: 'in', side: PortSide.left, kind: PortKind.input);

FlowNode<String> node(String id, double x, double y, List<FlowPort> ports) =>
    FlowNode<String>(
      id: id,
      type: 'test',
      data: id,
      position: GraphPosition(Offset(x, y)),
      size: const Size(120, 60),
      ports: ports,
    );

/// Pumps a two-node graph: `a` (output on the right, anchor (220,130)) and `b`
/// (input on the left, anchor (400,130)), identity viewport.
Future<Offset> pumpConnect(
  WidgetTester tester,
  FlowController<String, String> controller,
  bool Function(FlowConnectionRequest request) onConnect, {
  bool Function(FlowConnectionRequest request)? isValidConnection,
  List<FlowPort> targetPorts = const <FlowPort>[_inPort],
}) async {
  controller.addNode(node('a', 100, 100, const <FlowPort>[_outPort]));
  controller.addNode(node('b', 400, 100, targetPorts));

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 800,
            height: 600,
            child: NodeFlow<String, String>(
              controller: controller,
              fitViewOnLoad: false,
              animateEdges: false,
              minimap: false,
              onConnect: onConnect,
              isValidConnection: isValidConnection,
              nodeBuilder: (context, n) => SizedBox(
                key: ValueKey<String>('card-${n.id}'),
                width: n.measuredSize.value.width,
                height: n.measuredSize.value.height,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getTopLeft(find.byType(NodeFlow<String, String>));
}

void main() {
  testWidgets('drag output -> input invokes onConnect with a normalized '
      'request and the app adds the edge', (tester) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);

    var calls = 0;
    FlowConnectionRequest? captured;
    final tl = await pumpConnect(tester, c, (req) {
      calls++;
      captured = req;
      c.addEdge(
        FlowEdge<String>(
          id: 'e',
          sourceNodeId: req.sourceNodeId,
          sourcePortId: req.sourcePortId,
          targetNodeId: req.targetNodeId,
          targetPortId: req.targetPortId,
        ),
      );
      return true;
    });

    final gesture = await tester.startGesture(
      tl + const Offset(220, 130),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(tl + const Offset(300, 130));
    await tester.pump();
    expect(c.mode.value, FlowInteractionMode.draggingConnection);
    await gesture.moveTo(tl + const Offset(300, 130));
    await tester.pump();
    await gesture.moveTo(tl + const Offset(400, 130));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(calls, 1);
    expect(
      captured,
      const FlowConnectionRequest(
        sourceNodeId: 'a',
        sourcePortId: 'out',
        targetNodeId: 'b',
        targetPortId: 'in',
      ),
    );
    expect(c.edges.map((e) => e.id), contains('e'));
    expect(c.mode.value, FlowInteractionMode.idle);
    expect(c.pendingConnection.value, isNull);
  });

  testWidgets('dragging from an input normalizes the output as the source', (
    tester,
  ) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);

    FlowConnectionRequest? captured;
    final tl = await pumpConnect(tester, c, (req) {
      captured = req;
      return true;
    });

    // Start on b's input (400,130) and drop on a's output (220,130).
    final gesture = await tester.startGesture(
      tl + const Offset(400, 130),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(tl + const Offset(300, 130));
    await tester.pump();
    await gesture.moveTo(tl + const Offset(220, 130));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(
      captured,
      const FlowConnectionRequest(
        sourceNodeId: 'a',
        sourcePortId: 'out',
        targetNodeId: 'b',
        targetPortId: 'in',
      ),
    );
  });

  testWidgets('a duplicate connection does not re-invoke onConnect', (
    tester,
  ) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);

    var calls = 0;
    final tl = await pumpConnect(tester, c, (req) {
      calls++;
      return true;
    });

    // The edge already exists.
    c.addEdge(
      FlowEdge<String>(
        id: 'e',
        sourceNodeId: 'a',
        sourcePortId: 'out',
        targetNodeId: 'b',
        targetPortId: 'in',
      ),
    );
    await tester.pump();

    final gesture = await tester.startGesture(
      tl + const Offset(220, 130),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(tl + const Offset(300, 130));
    await tester.pump();
    await gesture.moveTo(tl + const Offset(400, 130));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(calls, 0);
    expect(c.mode.value, FlowInteractionMode.idle);
  });

  testWidgets('validator rejects hover and drop in either drag direction', (
    tester,
  ) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);
    final proposals = <FlowConnectionRequest>[];
    var accepted = 0;
    final tl = await pumpConnect(
      tester,
      c,
      (_) {
        accepted++;
        return true;
      },
      isValidConnection: (request) {
        proposals.add(request);
        return false;
      },
    );

    for (final (start, end) in <(Offset, Offset)>[
      (const Offset(220, 130), const Offset(400, 130)),
      (const Offset(400, 130), const Offset(220, 130)),
    ]) {
      final gesture = await tester.startGesture(
        tl + start,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(tl + Offset.lerp(start, end, 0.5)!);
      await tester.pump();
      await gesture.moveTo(tl + end);
      await tester.pump();
      expect(c.pendingConnection.value?.hasTarget, isFalse);
      await gesture.up();
      await tester.pump();
      expect(c.pendingConnection.value, isNull);
      expect(c.mode.value, FlowInteractionMode.idle);
    }

    expect(accepted, 0);
    expect(proposals, isNotEmpty);
    expect(
      proposals,
      everyElement(
        const FlowConnectionRequest(
          sourceNodeId: 'a',
          sourcePortId: 'out',
          targetNodeId: 'b',
          targetPortId: 'in',
        ),
      ),
    );
  });

  testWidgets('drop rechecks changing app state and skips duplicate pairs', (
    tester,
  ) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);
    var allowed = true;
    var proposals = 0;
    var accepted = 0;
    final tl = await pumpConnect(
      tester,
      c,
      (_) {
        accepted++;
        return true;
      },
      isValidConnection: (_) {
        proposals++;
        return allowed;
      },
    );

    final gesture = await tester.startGesture(
      tl + const Offset(220, 130),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(tl + const Offset(300, 130));
    await tester.pump();
    await gesture.moveTo(tl + const Offset(400, 130));
    await tester.pump();
    expect(c.pendingConnection.value?.hasTarget, isTrue);
    final hoverCalls = proposals;
    allowed = false;
    await gesture.up();
    await tester.pump();
    expect(accepted, 0);
    expect(proposals, greaterThan(hoverCalls));
    expect(c.pendingConnection.value, isNull);
    final callsBeforeDuplicate = proposals;

    c.addEdge(
      FlowEdge<String>(
        id: 'existing',
        sourceNodeId: 'a',
        sourcePortId: 'out',
        targetNodeId: 'b',
        targetPortId: 'in',
      ),
    );
    allowed = true;
    final duplicate = await tester.startGesture(
      tl + const Offset(220, 130),
      kind: PointerDeviceKind.mouse,
    );
    await duplicate.moveTo(tl + const Offset(300, 130));
    await tester.pump();
    await duplicate.moveTo(tl + const Offset(400, 130));
    await tester.pump();
    expect(c.pendingConnection.value?.hasTarget, isFalse);
    await duplicate.up();
    await tester.pump();
    expect(proposals, callsBeforeDuplicate);
    expect(accepted, 0);
  });

  testWidgets('invalid nearest port does not redirect to adjacent input', (
    tester,
  ) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);
    var allowNearest = false;
    final accepted = <FlowConnectionRequest>[];
    final tl = await pumpConnect(
      tester,
      c,
      (request) {
        accepted.add(request);
        return true;
      },
      targetPorts: const <FlowPort>[
        FlowPort(id: 'near', side: PortSide.left, kind: PortKind.input),
        FlowPort(id: 'far', side: PortSide.left, kind: PortKind.input),
      ],
      isValidConnection: (request) =>
          request.targetPortId != 'near' || allowNearest,
    );
    final source = tl + const Offset(220, 130);
    // Inputs are at y=120 and y=140. The pointer is inside both hit radii,
    // but 8px from 'near' and 12px from 'far'.
    final target = tl + const Offset(400, 128);

    final rejected = await tester.startGesture(
      source,
      kind: PointerDeviceKind.mouse,
    );
    await rejected.moveTo(tl + const Offset(300, 130));
    await tester.pump();
    await rejected.moveTo(target);
    await tester.pump();
    expect(c.pendingConnection.value?.hasTarget, isFalse);
    await rejected.up();
    await tester.pump();
    expect(accepted, isEmpty);

    allowNearest = true;
    final changed = await tester.startGesture(
      source,
      kind: PointerDeviceKind.mouse,
    );
    await changed.moveTo(tl + const Offset(300, 130));
    await tester.pump();
    await changed.moveTo(target);
    await tester.pump();
    expect(c.pendingConnection.value?.targetPort?.id, 'near');
    allowNearest = false;
    await changed.up();
    await tester.pump();
    expect(accepted, isEmpty);
    expect(c.pendingConnection.value, isNull);
  });

  testWidgets('validator errors end the gesture during hover and drop', (
    tester,
  ) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);
    var throws = true;
    final tl = await pumpConnect(
      tester,
      c,
      (_) => true,
      isValidConnection: (_) {
        if (throws) throw StateError('validation failed');
        return true;
      },
    );

    final hover = await tester.startGesture(
      tl + const Offset(220, 130),
      kind: PointerDeviceKind.mouse,
    );
    await hover.moveTo(tl + const Offset(300, 130));
    await tester.pump();
    await hover.moveTo(tl + const Offset(400, 130));
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    expect(c.pendingConnection.value, isNull);
    expect(c.mode.value, FlowInteractionMode.idle);
    await hover.cancel();
    await tester.pump();

    throws = false;
    final drop = await tester.startGesture(
      tl + const Offset(220, 130),
      kind: PointerDeviceKind.mouse,
    );
    await drop.moveTo(tl + const Offset(300, 130));
    await tester.pump();
    await drop.moveTo(tl + const Offset(400, 130));
    await tester.pump();
    expect(c.pendingConnection.value?.hasTarget, isTrue);
    throws = true;
    await drop.up();
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    expect(c.pendingConnection.value, isNull);
    expect(c.mode.value, FlowInteractionMode.idle);
  });

  testWidgets('cancelling a connection drag restores idle state', (
    tester,
  ) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);

    final tl = await pumpConnect(tester, c, (req) => true);
    final gesture = await tester.startGesture(
      tl + const Offset(220, 130),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(tl + const Offset(300, 130));
    await tester.pump();

    expect(c.mode.value, FlowInteractionMode.draggingConnection);
    expect(c.pendingConnection.value, isNotNull);

    await gesture.cancel();
    await tester.pump();

    expect(c.mode.value, FlowInteractionMode.idle);
    expect(c.pendingConnection.value, isNull);
  });

  testWidgets('onConnect errors still end the connection gesture', (
    tester,
  ) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);

    final tl = await pumpConnect(tester, c, (req) {
      throw StateError('connect failed');
    });

    final gesture = await tester.startGesture(
      tl + const Offset(220, 130),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(tl + const Offset(400, 130));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(tester.takeException(), isA<StateError>());
    expect(c.pendingConnection.value, isNull);
    expect(c.mode.value, FlowInteractionMode.idle);
  });

  testWidgets('dropping on empty space cancels without invoking onConnect', (
    tester,
  ) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);

    var calls = 0;
    final tl = await pumpConnect(tester, c, (req) {
      calls++;
      return true;
    });

    final gesture = await tester.startGesture(
      tl + const Offset(220, 130),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(tl + const Offset(300, 130));
    await tester.pump();
    expect(c.mode.value, FlowInteractionMode.draggingConnection);
    await gesture.moveTo(tl + const Offset(300, 320)); // empty space
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(calls, 0);
    expect(c.pendingConnection.value, isNull);
    expect(c.mode.value, FlowInteractionMode.idle);
  });
}
