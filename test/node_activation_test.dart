import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:node_flow/node_flow.dart';

FlowController<String, void> _controller() {
  final controller = FlowController<String, void>();
  controller.addNode(
    FlowNode<String>(
      id: 'one',
      type: 'card',
      data: 'One',
      position: const GraphPosition(Offset(100, 100)),
      size: const Size(180, 100),
    ),
  );
  return controller;
}

Widget _canvas(
  FlowController<String, void> controller, {
  ValueChanged<FlowNode<String>>? onNodeTap,
  ValueChanged<FlowNode<String>>? onNodeDoubleTap,
  void Function(FlowNode<String>, Offset)? onNodeContextMenu,
  VoidCallback? onChildTap,
}) => MaterialApp(
  home: Scaffold(
    body: NodeFlow<String, void>(
      controller: controller,
      fitViewOnLoad: false,
      animateEdges: false,
      minimap: false,
      snapGuides: false,
      onNodeTap: onNodeTap,
      onNodeDoubleTap: onNodeDoubleTap,
      onNodeContextMenu: onNodeContextMenu,
      nodeBuilder: (context, node) => Container(
        key: ValueKey('node-card-${node.id}'),
        width: 180,
        height: 100,
        color: Colors.blue,
        child: Column(
          children: <Widget>[
            Text(node.data),
            ElevatedButton(onPressed: onChildTap, child: const Text('Open')),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'primary tap selects before callback; child control owns its tap',
    (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final selectedDuringCallback = <bool>[];
      var childTaps = 0;
      await tester.pumpWidget(
        _canvas(
          controller,
          onNodeTap: (node) => selectedDuringCallback.add(
            controller.selection.value.contains(node.id),
          ),
          onChildTap: () => childTaps++,
        ),
      );
      await tester.pump();

      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('node-card-one'))) +
            const Offset(20, 12),
      );
      await tester.pump();
      expect(selectedDuringCallback, [true]);
      expect(controller.selection.value, {'one'});

      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(childTaps, 1);
      expect(selectedDuringCallback, [true]);
    },
  );

  testWidgets('child control keeps its tap with double-tap enabled', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    var childTaps = 0;
    var nodeTaps = 0;
    var doubleTaps = 0;
    await tester.pumpWidget(
      _canvas(
        controller,
        onNodeTap: (_) => nodeTaps++,
        onNodeDoubleTap: (_) => doubleTaps++,
        onChildTap: () => childTaps++,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(childTaps, 1);
    expect(nodeTaps, 0);
    expect(doubleTaps, 0);
    expect(controller.selection.value, isEmpty);
  });

  testWidgets(
    'shift selection uses modifier at pointer down with double-tap enabled',
    (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.addNode(
        FlowNode<String>(
          id: 'other',
          type: 'card',
          data: 'Other',
          position: const GraphPosition(Offset(350, 100)),
        ),
      );
      controller.select(['other']);
      await tester.pumpWidget(_canvas(controller, onNodeDoubleTap: (_) {}));
      await tester.pump();
      final point =
          tester.getTopLeft(find.byKey(const ValueKey('node-card-one')).first) +
          const Offset(20, 12);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tapAt(point);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump(const Duration(milliseconds: 400));

      expect(controller.selection.value, {'other', 'one'});
    },
  );

  testWidgets('double tap calls only double callback and selects once', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    var taps = 0;
    var doubleTaps = 0;
    await tester.pumpWidget(
      _canvas(
        controller,
        onNodeTap: (_) => taps++,
        onNodeDoubleTap: (_) {
          doubleTaps++;
          expect(controller.selection.value, {'one'});
        },
      ),
    );
    await tester.pump();
    final point =
        tester.getTopLeft(find.byKey(const ValueKey('node-card-one'))) +
        const Offset(20, 12);
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 90));
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 400));

    expect(doubleTaps, 1);
    expect(taps, 0);
    expect(controller.selection.value, {'one'});
  });

  testWidgets('two distant taps keep the first tap modifier', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.addNode(
      FlowNode<String>(
        id: 'other',
        type: 'card',
        data: 'Other',
        position: const GraphPosition(Offset(350, 100)),
      ),
    );
    controller.select(['other']);
    final selections = <Set<String>>[];
    await tester.pumpWidget(
      _canvas(
        controller,
        onNodeTap: (_) => selections.add({...controller.selection.value}),
        onNodeDoubleTap: (_) => fail('Distant taps are not a double tap'),
      ),
    );
    await tester.pump();
    final topLeft = tester.getTopLeft(
      find.byKey(const ValueKey('node-card-one')),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.tapAt(topLeft + const Offset(20, 12));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(topLeft + const Offset(155, 12));
    await tester.pump(const Duration(milliseconds: 400));

    expect(selections, [
      {'other', 'one'},
      {'one'},
    ]);
  });

  testWidgets('secondary click and long press report global point without '
      'selecting', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    final positions = <Offset>[];
    await tester.pumpWidget(
      _canvas(
        controller,
        onNodeContextMenu: (node, point) {
          expect(node.id, 'one');
          positions.add(point);
        },
      ),
    );
    await tester.pump();
    final point =
        tester.getTopLeft(find.byKey(const ValueKey('node-card-one'))) +
        const Offset(20, 12);

    final secondary = await tester.startGesture(
      point,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await secondary.up();
    await tester.pump();
    await tester.longPressAt(point);
    await tester.pump();

    expect(positions, [point, point]);
    expect(controller.selection.value, isEmpty);
  });

  testWidgets('throwing tap callback does not strand node interaction', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    var calls = 0;
    await tester.pumpWidget(
      _canvas(
        controller,
        onNodeTap: (_) {
          calls++;
          if (calls == 1) throw StateError('activation failed');
        },
      ),
    );
    await tester.pump();
    final point =
        tester.getTopLeft(find.byKey(const ValueKey('node-card-one'))) +
        const Offset(20, 12);

    await tester.tapAt(point);
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    expect(controller.selection.value, {'one'});

    await tester.tapAt(point);
    await tester.pump();
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid taps on an embedded button stay with the button', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    var childTaps = 0;
    var nodeTaps = 0;
    var doubleTaps = 0;
    await tester.pumpWidget(
      _canvas(
        controller,
        onNodeTap: (_) => nodeTaps++,
        onNodeDoubleTap: (_) => doubleTaps++,
        onChildTap: () => childTaps++,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.text('Open'));
    await tester.pump();

    expect(childTaps, 2);
    expect(nodeTaps, 0);
    expect(doubleTaps, 0);
    expect(controller.selection.value, isEmpty);
  });

  testWidgets('small mouse movement on second click still double taps', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    var doubleTaps = 0;
    await tester.pumpWidget(
      _canvas(controller, onNodeDoubleTap: (_) => doubleTaps++),
    );
    await tester.pump();
    final point =
        tester.getTopLeft(find.byKey(const ValueKey('node-card-one'))) +
        const Offset(20, 12);

    final first = await tester.startGesture(
      point,
      kind: PointerDeviceKind.mouse,
    );
    await first.up();
    await tester.pump(const Duration(milliseconds: 80));
    final second = await tester.startGesture(
      point,
      kind: PointerDeviceKind.mouse,
    );
    await second.moveBy(const Offset(3, 0));
    await second.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(doubleTaps, 1);
    expect(
      controller.getNode('one')!.position.value.offset,
      const Offset(100, 100),
    );
    expect(controller.mode.value, FlowInteractionMode.idle);
  });

  testWidgets('a drag after one tap does not activate a double tap', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    var doubleTaps = 0;
    await tester.pumpWidget(
      _canvas(controller, onNodeDoubleTap: (_) => doubleTaps++),
    );
    await tester.pump();
    final point =
        tester.getTopLeft(find.byKey(const ValueKey('node-card-one'))) +
        const Offset(20, 12);

    final first = await tester.startGesture(
      point,
      kind: PointerDeviceKind.mouse,
    );
    await first.up();
    await tester.pump(const Duration(milliseconds: 80));
    final drag = await tester.startGesture(
      point,
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(3, 0));
    await tester.pump();
    await drag.moveBy(const Offset(40, 24));
    await tester.pump();
    await drag.moveBy(const Offset(20, 12));
    await drag.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(doubleTaps, 0);
    expect(
      controller.getNode('one')!.position.value.offset,
      isNot(const Offset(100, 100)),
    );
    expect(controller.mode.value, FlowInteractionMode.idle);
  });

  testWidgets('a drag after Shift tap keeps the additive selection', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.addNode(
      FlowNode<String>(
        id: 'other',
        type: 'card',
        data: 'Other',
        position: const GraphPosition(Offset(350, 100)),
      ),
    );
    controller.select(['other']);
    await tester.pumpWidget(_canvas(controller, onNodeDoubleTap: (_) {}));
    await tester.pump();
    final point =
        tester.getTopLeft(find.byKey(const ValueKey('node-card-one'))) +
        const Offset(20, 12);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    final first = await tester.startGesture(
      point,
      kind: PointerDeviceKind.mouse,
    );
    await first.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump(const Duration(milliseconds: 80));
    final drag = await tester.startGesture(
      point,
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(40, 24));
    await tester.pump();
    await drag.moveBy(const Offset(20, 12));
    await drag.up();
    await tester.pump();

    expect(controller.selection.value, {'other', 'one'});
    expect(
      controller.getNode('one')!.position.value.offset,
      isNot(const Offset(100, 100)),
    );
    expect(
      controller.getNode('other')!.position.value.offset,
      isNot(const Offset(350, 100)),
    );
  });

  testWidgets('holding primary mouse button does not open context menu', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    var contextRequests = 0;
    await tester.pumpWidget(
      _canvas(controller, onNodeContextMenu: (_, _) => contextRequests++),
    );
    await tester.pump();
    final point =
        tester.getTopLeft(find.byKey(const ValueKey('node-card-one'))) +
        const Offset(20, 12);

    final mouse = await tester.startGesture(
      point,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 600));
    await mouse.moveBy(const Offset(40, 24));
    await tester.pump();
    await mouse.moveBy(const Offset(20, 12));
    await mouse.up();
    await tester.pump();

    expect(contextRequests, 0);
    expect(
      controller.getNode('one')!.position.value.offset,
      isNot(const Offset(100, 100)),
    );
  });

  testWidgets('drag does not activate a node', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    var taps = 0;
    var doubleTaps = 0;
    var contextRequests = 0;
    await tester.pumpWidget(
      _canvas(
        controller,
        onNodeTap: (_) => taps++,
        onNodeDoubleTap: (_) => doubleTaps++,
        onNodeContextMenu: (_, _) => contextRequests++,
      ),
    );
    await tester.pump();
    final point =
        tester.getTopLeft(find.byKey(const ValueKey('node-card-one'))) +
        const Offset(20, 12);
    final drag = await tester.startGesture(
      point,
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(70, 40));
    await tester.pump();
    await drag.moveBy(const Offset(30, 20));
    await tester.pump();
    await drag.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      controller.getNode('one')!.position.value.offset,
      isNot(const Offset(100, 100)),
    );
    expect(taps, 0);
    expect(doubleTaps, 0);
    expect(contextRequests, 0);
    expect(controller.mode.value, FlowInteractionMode.idle);
  });
}
