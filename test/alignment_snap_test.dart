import 'package:flutter_test/flutter_test.dart';
import 'package:node_flow/node_flow.dart';

void main() {
  group('resolveAlignmentSnap', () {
    test('snaps to a left-edge alignment within the threshold', () {
      final result = resolveAlignmentSnap(
        movingBounds: GraphRect.fromLTWH(104, 300, 100, 50),
        delta: GraphOffset.fromXY(10, 0),
        others: [GraphRect.fromLTWH(100, 0, 100, 50)],
      );

      // left(104) aligns to other's left(100): adjust dx by -4.
      expect(result.delta.dx, 10 - 4);
      expect(result.delta.dy, 0);
      final guide = result.guides.singleWhere((g) => g.vertical);
      expect(guide.position, 100);
      // Spans both rects (padded).
      expect(guide.start, lessThan(0));
      expect(guide.end, greaterThan(350));
    });

    test('snaps centers on both axes simultaneously', () {
      final result = resolveAlignmentSnap(
        movingBounds: GraphRect.fromLTWH(203, 102, 100, 100),
        delta: GraphOffset.zero,
        others: [GraphRect.fromLTWH(200, 100, 100, 100)],
      );

      expect(result.delta.dx, -3);
      expect(result.delta.dy, -2);
      expect(result.guides, hasLength(2));
      expect(result.guides.where((g) => g.vertical), hasLength(1));
      expect(result.guides.where((g) => !g.vertical), hasLength(1));
    });

    test('outside the threshold nothing snaps', () {
      final result = resolveAlignmentSnap(
        movingBounds: GraphRect.fromLTWH(110, 300, 100, 50),
        delta: GraphOffset.fromXY(5, 5),
        others: [GraphRect.fromLTWH(100, 0, 100, 50)],
        threshold: 6,
      );

      expect(result.delta.dx, 5);
      expect(result.delta.dy, 5);
      expect(result.guides, isEmpty);
    });

    test('picks the closest alignment among several candidates', () {
      final result = resolveAlignmentSnap(
        movingBounds: GraphRect.fromLTWH(100, 0, 100, 50),
        delta: GraphOffset.zero,
        others: [
          GraphRect.fromLTWH(105, 200, 100, 50), // left 5 away
          GraphRect.fromLTWH(102, 400, 100, 50), // left 2 away — closest
        ],
      );

      final guide = result.guides.singleWhere((g) => g.vertical);
      expect(guide.position, 102);
      expect(result.delta.dx, 2);
    });
  });

  group('FlowController alignment guides', () {
    test('moveNodeBy soft-snaps and publishes guides when enabled', () {
      final controller = FlowController<void, void>()..snapGuidesEnabled = true;
      addTearDown(controller.dispose);

      controller.addNode(
        FlowNode<void>(
          id: 'anchor',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(0, 0),
        ),
      );
      controller.addNode(
        FlowNode<void>(
          id: 'moving',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(4, 300),
        ),
      );

      // Raw delta keeps left at x=4, within the 8px threshold of the
      // anchor's left (0).
      controller.moveNodeBy('moving', GraphOffset.zero);

      expect(controller.activeGuides.value, isNotEmpty);
      expect(controller.getNode('moving')!.position.value.dx, 0);

      // Commit preserves the aligned position (alignment wins over grid) and
      // clears the guides.
      controller.commitMove();
      expect(controller.activeGuides.value, isEmpty);
      expect(controller.getNode('moving')!.position.value.dx, 0);
    });

    test('a slow drag escapes a guide after cumulative travel', () {
      final controller = FlowController<void, void>()..snapGuidesEnabled = true;
      addTearDown(controller.dispose);

      controller.addNode(
        FlowNode<void>(
          id: 'anchor',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(0, 0),
        ),
      );
      controller.addNode(
        FlowNode<void>(
          id: 'moving',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(4, 300),
        ),
      );

      controller.beginNodeDrag('moving');

      // First event: raw x = 5, within the 8px threshold — held on the guide.
      controller.moveNodeBy('moving', GraphOffset.fromXY(1, 0));
      expect(controller.getNode('moving')!.position.value.dx, 0);
      expect(controller.activeGuides.value, isNotEmpty);

      // Three more 1-unit events: raw x = 8, still held. Under the old
      // delta-feedback behavior these would be cancelled forever.
      for (var i = 0; i < 3; i += 1) {
        controller.moveNodeBy('moving', GraphOffset.fromXY(1, 0));
      }
      expect(controller.getNode('moving')!.position.value.dx, 0);

      // One more: raw x = 9, past the threshold — releases to exactly the
      // raw pointer position, with none of the held travel swallowed.
      controller.moveNodeBy('moving', GraphOffset.fromXY(1, 0));
      expect(controller.getNode('moving')!.position.value.dx, 9);
      expect(controller.activeGuides.value, isEmpty);
    });

    test('a long slow drag tracks the pointer exactly (no drift)', () {
      final controller = FlowController<void, void>()..snapGuidesEnabled = true;
      addTearDown(controller.dispose);

      controller.addNode(
        FlowNode<void>(
          id: 'anchor',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(0, 0),
        ),
      );
      controller.addNode(
        FlowNode<void>(
          id: 'moving',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(4, 300),
        ),
      );

      controller.beginNodeDrag('moving');
      for (var i = 0; i < 300; i += 1) {
        controller.moveNodeBy('moving', GraphOffset.fromXY(1, 0));
      }

      // start(4) + 300 raw units, every guide passed on the way released.
      expect(controller.getNode('moving')!.position.value.dx, 304);
      expect(controller.getNode('moving')!.position.value.dy, 300);
    });

    test('the capture radius is screen pixels: zoom halves it in graph '
        'units', () {
      final controller = FlowController<void, void>()..snapGuidesEnabled = true;
      addTearDown(controller.dispose);
      controller.setViewport(const FlowViewport(zoom: 2));

      controller.addNode(
        FlowNode<void>(
          id: 'anchor',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(0, 0),
        ),
      );
      controller.addNode(
        FlowNode<void>(
          id: 'moving',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(3, 300),
        ),
      );

      controller.beginNodeDrag('moving');

      // 8px / zoom 2 = 4 graph units: raw x = 3 is captured…
      controller.moveNodeBy('moving', GraphOffset.zero);
      expect(controller.getNode('moving')!.position.value.dx, 0);

      // …and raw x = 5 is already free (at zoom 1 it would still be held).
      controller.moveNodeBy('moving', GraphOffset.fromXY(2, 0));
      expect(controller.getNode('moving')!.position.value.dx, 5);
    });

    test('a multi-selection drag moves every node by the raw offset', () {
      final controller = FlowController<void, void>()..snapGuidesEnabled = true;
      addTearDown(controller.dispose);

      controller.addNode(
        FlowNode<void>(
          id: 'a',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(1000, 1000),
        ),
      );
      controller.addNode(
        FlowNode<void>(
          id: 'b',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(1200, 1300),
        ),
      );

      controller.select(const ['a', 'b']);
      controller.beginNodeDrag('a');
      for (var i = 0; i < 4; i += 1) {
        controller.moveNodeBy('a', GraphOffset.fromXY(3, 3));
      }

      expect(controller.getNode('a')!.position.value.dx, 1012);
      expect(controller.getNode('a')!.position.value.dy, 1012);
      expect(controller.getNode('b')!.position.value.dx, 1212);
      expect(controller.getNode('b')!.position.value.dy, 1312);
    });

    test('snapGuideThreshold is honored and runtime-tunable', () {
      final controller = FlowController<void, void>(snapGuideThreshold: 24)
        ..snapGuidesEnabled = true;
      addTearDown(controller.dispose);

      controller.addNode(
        FlowNode<void>(
          id: 'anchor',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(0, 0),
        ),
      );
      controller.addNode(
        FlowNode<void>(
          id: 'moving',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(20, 300),
        ),
      );

      controller.beginNodeDrag('moving');

      // 20 is inside the widened 24px radius (default 8 would not capture)…
      controller.moveNodeBy('moving', GraphOffset.zero);
      expect(controller.getNode('moving')!.position.value.dx, 0);

      // …and raw x = 25 is past it.
      controller.moveNodeBy('moving', GraphOffset.fromXY(5, 0));
      expect(controller.getNode('moving')!.position.value.dx, 25);
    });

    test('a marquee starting mid-drag does not re-pin the drag', () {
      final controller = FlowController<void, void>()..snapGuidesEnabled = true;
      addTearDown(controller.dispose);

      controller.addNode(
        FlowNode<void>(
          id: 'anchor',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(0, 0),
        ),
      );
      controller.addNode(
        FlowNode<void>(
          id: 'moving',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(4, 300),
        ),
      );

      controller.beginNodeDrag('moving');
      controller.moveNodeBy('moving', GraphOffset.fromXY(1, 0));
      expect(controller.getNode('moving')!.position.value.dx, 0);

      // A second pointer starts a marquee: the mode changes, but the drag
      // session must stay authoritative for the dragged node.
      controller.beginMarquee(GraphPosition.fromXY(600, 600));
      for (var i = 0; i < 8; i += 1) {
        controller.moveNodeBy('moving', GraphOffset.fromXY(1, 0));
      }

      // raw x = 4 + 9 = 13, past the 8px threshold — escaped, not pinned.
      expect(controller.getNode('moving')!.position.value.dx, 13);
    });

    test('a node locked and unlocked mid-drag does not teleport', () {
      final controller = FlowController<void, void>();
      addTearDown(controller.dispose);

      controller.addNode(
        FlowNode<void>(
          id: 'a',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(0, 0),
        ),
      );
      controller.addNode(
        FlowNode<void>(
          id: 'b',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(500, 0),
        ),
      );

      controller.select(const ['a', 'b']);
      controller.beginNodeDrag('a');
      controller.moveNodeBy('a', GraphOffset.fromXY(10, 0));
      expect(controller.getNode('b')!.position.value.dx, 510);

      controller.getNode('b')!.locked = true;
      for (var i = 0; i < 5; i += 1) {
        controller.moveNodeBy('a', GraphOffset.fromXY(10, 0));
      }
      expect(controller.getNode('a')!.position.value.dx, 60);
      expect(controller.getNode('b')!.position.value.dx, 510);

      // Unlocking resumes from where it stopped — no jump by the missed 50.
      controller.getNode('b')!.locked = false;
      controller.moveNodeBy('a', GraphOffset.fromXY(10, 0));
      expect(controller.getNode('b')!.position.value.dx, 520);
    });

    test('replaceNode mid-drag re-anchors: the new position wins', () {
      final controller = FlowController<void, void>();
      addTearDown(controller.dispose);

      controller.addNode(
        FlowNode<void>(
          id: 'a',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(0, 0),
        ),
      );

      controller.beginNodeDrag('a');
      controller.moveNodeBy('a', GraphOffset.fromXY(13, 17));
      expect(controller.getNode('a')!.position.value.dx, 13);

      controller.replaceNode(
        FlowNode<void>(
          id: 'a',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(500, 500),
        ),
      );
      controller.moveNodeBy('a', GraphOffset.fromXY(1, 0));

      expect(controller.getNode('a')!.position.value.dx, 501);
      expect(controller.getNode('a')!.position.value.dy, 500);
    });

    test('commitMove mid-drag sticks instead of reverting', () {
      final controller = FlowController<void, void>();
      addTearDown(controller.dispose);

      controller.addNode(
        FlowNode<void>(
          id: 'a',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(0, 0),
        ),
      );

      controller.beginNodeDrag('a');
      controller.moveNodeBy('a', GraphOffset.fromXY(13, 0));
      controller.commitMove();
      expect(controller.getNode('a')!.position.value.dx, 20);

      // The next events continue from the committed position.
      controller.moveNodeBy('a', GraphOffset.zero);
      expect(controller.getNode('a')!.position.value.dx, 20);
      controller.moveNodeBy('a', GraphOffset.fromXY(1, 0));
      expect(controller.getNode('a')!.position.value.dx, 21);
    });

    test('a second drag re-anchors from the committed position', () {
      final controller = FlowController<void, void>();
      addTearDown(controller.dispose);

      controller.addNode(
        FlowNode<void>(
          id: 'a',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(0, 0),
        ),
      );

      controller.beginNodeDrag('a');
      controller.moveNodeBy('a', GraphOffset.fromXY(13, 0));
      controller.endNodeDrag();
      expect(controller.getNode('a')!.position.value.dx, 20);

      controller.beginNodeDrag('a');
      controller.moveNodeBy('a', GraphOffset.fromXY(1, 0));
      expect(controller.getNode('a')!.position.value.dx, 21);
    });

    test('cancelNodeDrag restores drag-start positions, commits nothing', () {
      final controller = FlowController<void, void>();
      addTearDown(controller.dispose);

      var commits = 0;
      controller.onMoveCommitted = (_) => commits += 1;
      controller.addNode(
        FlowNode<void>(
          id: 'a',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(7, 9),
        ),
      );

      controller.beginNodeDrag('a');
      controller.moveNodeBy('a', GraphOffset.fromXY(30, 0));
      expect(controller.getNode('a')!.position.value.dx, 37);

      controller.cancelNodeDrag();
      expect(controller.getNode('a')!.position.value.dx, 7);
      expect(controller.getNode('a')!.position.value.dy, 9);
      expect(controller.mode.value, FlowInteractionMode.idle);
      expect(controller.draggingNodeIds.value, isEmpty);

      controller.commitMove();
      expect(commits, 0);
    });

    test('cancelNodeDrag without a session leaves another mode alone', () {
      final controller = FlowController<void, void>();
      addTearDown(controller.dispose);

      controller.beginMarquee(GraphPosition.fromXY(0, 0));
      final before = controller.mode.value;
      controller.cancelNodeDrag();
      expect(controller.mode.value, before);
    });

    test('disabling snapping mid-drag clears guides so commit grid-snaps', () {
      final controller = FlowController<void, void>()..snapGuidesEnabled = true;
      addTearDown(controller.dispose);

      controller.addNode(
        FlowNode<void>(
          id: 'anchor',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(0, 0),
        ),
      );
      controller.addNode(
        FlowNode<void>(
          id: 'moving',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(4, 300),
        ),
      );

      controller.beginNodeDrag('moving');
      controller.moveNodeBy('moving', GraphOffset.zero);
      expect(controller.activeGuides.value, isNotEmpty);

      controller.snapGuidesEnabled = false;
      controller.moveNodeBy('moving', GraphOffset.fromXY(37, 3));
      expect(controller.activeGuides.value, isEmpty);

      controller.endNodeDrag();
      // (41, 303) grid-snapped — a stale guide would have skipped the grid.
      expect(controller.getNode('moving')!.position.value.dx, 40);
      expect(controller.getNode('moving')!.position.value.dy, 300);
    });

    test('a zero zoom cannot inflate the capture radius', () {
      final controller = FlowController<void, void>()..snapGuidesEnabled = true;
      addTearDown(controller.dispose);
      controller.setViewport(const FlowViewport(zoom: 0));

      controller.addNode(
        FlowNode<void>(
          id: 'anchor',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(5000, 5000),
        ),
      );
      controller.addNode(
        FlowNode<void>(
          id: 'moving',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(0, 0),
        ),
      );

      controller.beginNodeDrag('moving');
      controller.moveNodeBy('moving', GraphOffset.fromXY(1, 0));

      // The threshold is floored at 8/minZoom, not Infinity — no teleport to
      // the distant anchor.
      expect(controller.getNode('moving')!.position.value.dx, 1);
    });

    test('disabled controller keeps exact deltas and no guides', () {
      final controller = FlowController<void, void>();
      addTearDown(controller.dispose);

      controller.addNode(
        FlowNode<void>(
          id: 'anchor',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(0, 0),
        ),
      );
      controller.addNode(
        FlowNode<void>(
          id: 'moving',
          type: 'n',
          data: null,
          position: GraphPosition.fromXY(4, 300),
        ),
      );

      controller.moveNodeBy('moving', GraphOffset.fromXY(1, 1));

      expect(controller.activeGuides.value, isEmpty);
      expect(controller.getNode('moving')!.position.value.dx, 5);
    });
  });
}
