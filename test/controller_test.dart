import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:node_flow/node_flow.dart';

FlowNode<String> node(String id, double x, double y, {Size? size}) => FlowNode(
  id: id,
  type: 'test',
  data: id,
  position: GraphPosition(Offset(x, y)),
  size: size ?? const Size(200, 100),
);

FlowEdge<String> edge(String id, String from, String to) => FlowEdge(
  id: id,
  sourceNodeId: from,
  sourcePortId: 'out',
  targetNodeId: to,
  targetPortId: 'in',
);

void main() {
  group('nodes', () {
    test('addNode / getNode / nodes ordering', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);

      c.addNode(node('a', 0, 0));
      c.addNode(node('b', 10, 10));

      expect(c.getNode('a'), isNotNull);
      expect(c.nodes.map((n) => n.id), <String>['a', 'b']);
    });

    test('duplicate id is ignored', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));
      c.addNode(node('a', 99, 99));
      expect(c.nodes, hasLength(1));
      expect(c.getNode('a')!.position.value.dx, 0);
    });

    test('removeNode removes incident edges', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));
      c.addNode(node('b', 100, 0));
      c.addEdge(edge('e1', 'a', 'b'));
      c.addEdge(edge('e2', 'b', 'a'));

      c.removeNode('a');

      expect(c.getNode('a'), isNull);
      expect(c.getNode('b'), isNotNull);
      expect(c.edges, isEmpty);
    });

    test('replaceNode preserves controller-owned interaction state', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));
      c.addNode(node('b', 100, 0));
      c.addEdge(edge('e1', 'a', 'b'));
      c.select(const ['a']);
      c.beginNodeDrag('a');
      c.moveNodeBy('a', const GraphOffset(Offset(13, 17)));

      final replacement = FlowNode<String>(
        id: 'a',
        type: 'replacement',
        data: 'new-data',
        position: c.getNode('a')!.position.value,
      );
      expect(c.replaceNode(replacement), isTrue);

      expect(c.getNode('a'), same(replacement));
      expect(c.selection.value, contains('a'));
      expect(c.draggingNodeIds.value, contains('a'));
      expect(c.edges.map((edge) => edge.id), ['e1']);

      Map<String, GraphPosition>? committed;
      c.onMoveCommitted = (moves) => committed = moves;
      c.endNodeDrag();
      expect(committed, contains('a'));
      expect(c.getNode('a')!.position.value.offset, const Offset(20, 20));
    });

    test('nodes render in ascending z-order with insertion tie-break', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));
      c.addNode(node('b', 0, 0));
      c.addNode(node('c', 0, 0));

      // Same z-index -> insertion order.
      expect(c.nodes.map((n) => n.id), <String>['a', 'b', 'c']);

      c.getNode('a')!.zIndex.value = 5;
      expect(c.nodes.map((n) => n.id), <String>['b', 'c', 'a']);
    });
  });

  group('move + snap', () {
    test('moveNodeBy moves a single unselected node', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));

      c.moveNodeBy('a', const GraphOffset(Offset(10, 15)));

      expect(c.getNode('a')!.position.value.offset, const Offset(10, 15));
    });

    test('moveNodeBy moves the whole selection when the node is selected', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));
      c.addNode(node('b', 100, 0));
      c.select(<String>['a', 'b']);

      c.moveNodeBy('a', const GraphOffset(Offset(5, 7)));

      expect(c.getNode('a')!.position.value.offset, const Offset(5, 7));
      expect(c.getNode('b')!.position.value.offset, const Offset(105, 7));
    });

    test('moveNodeBy skips locked nodes', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      final locked = node('a', 0, 0)..locked = true;
      c.addNode(locked);
      c.moveNodeBy('a', const GraphOffset(Offset(10, 10)));
      expect(c.getNode('a')!.position.value.offset, Offset.zero);
    });

    test('commitMove snaps to the 20-grid and fires onMoveCommitted', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));

      Map<String, GraphPosition>? committed;
      c.onMoveCommitted = (m) => committed = m;

      c.moveNodeBy('a', const GraphOffset(Offset(33, 48)));
      // Live drag is free: not snapped yet.
      expect(c.getNode('a')!.position.value.offset, const Offset(33, 48));

      c.commitMove();

      expect(c.getNode('a')!.position.value.offset, const Offset(40, 40));
      expect(committed, isNotNull);
      expect(committed!['a']!.offset, const Offset(40, 40));
    });

    test('commitMove snaps every node in a multi-selection drag', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));
      c.addNode(node('b', 100, 0));
      c.select(<String>['a', 'b']);

      Map<String, GraphPosition>? committed;
      c.onMoveCommitted = (m) => committed = m;

      c.moveNodeBy('a', const GraphOffset(Offset(8, 12)));
      c.commitMove();

      // a: (8,12) -> (0,20 rounded from .6) ; b: (108,12) -> (100,20)
      expect(c.getNode('a')!.position.value.offset, const Offset(0, 20));
      expect(c.getNode('b')!.position.value.offset, const Offset(100, 20));
      expect(committed!.keys, unorderedEquals(<String>['a', 'b']));
    });

    test('commitMove with no active drag is a no-op', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      var fired = false;
      c.onMoveCommitted = (_) => fired = true;
      c.commitMove();
      expect(fired, isFalse);
    });
  });

  group('selection', () {
    test('select replaces; additive unions', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));
      c.addNode(node('b', 0, 0));
      c.addNode(node('c', 0, 0));

      c.select(<String>['a']);
      expect(c.selection.value, unorderedEquals(<String>['a']));
      expect(c.getNode('a')!.selected.value, isTrue);

      c.select(<String>['b'], additive: true);
      expect(c.selection.value, unorderedEquals(<String>['a', 'b']));

      c.select(<String>['c']);
      expect(c.selection.value, unorderedEquals(<String>['c']));
      expect(c.getNode('a')!.selected.value, isFalse);
      expect(c.getNode('c')!.selected.value, isTrue);
    });

    test('toggle adds and removes', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));
      c.toggle('a');
      expect(c.isSelected('a'), isTrue);
      c.toggle('a');
      expect(c.isSelected('a'), isFalse);
    });

    test('selectAll and clearSelection', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));
      c.addNode(node('b', 0, 0));

      c.selectAll();
      expect(c.selection.value, unorderedEquals(<String>['a', 'b']));

      c.clearSelection();
      expect(c.selection.value, isEmpty);
      expect(c.getNode('a')!.selected.value, isFalse);
    });

    test('deleteSelection removes nodes + edges and fires onDeleted', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));
      c.addNode(node('b', 100, 0));
      c.addEdge(edge('e1', 'a', 'b'));
      c.select(<String>['a']);

      Set<String>? deleted;
      c.onDeleted = (ids) => deleted = ids;

      c.deleteSelection();

      expect(c.getNode('a'), isNull);
      expect(c.getNode('b'), isNotNull);
      expect(c.edges, isEmpty);
      expect(c.selection.value, isEmpty);
      expect(deleted, unorderedEquals(<String>['a']));
    });

    test('unknown ids are ignored by select/toggle', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.select(<String>['ghost']);
      c.toggle('ghost');
      expect(c.selection.value, isEmpty);
    });

    test(
      'deleteSelection removes selected edges and invokes onEdgesDeleted',
      () {
        final c = FlowController<String, String>();
        addTearDown(c.dispose);
        c.addNode(node('a', 0, 0));
        c.addNode(node('b', 100, 0));
        c.addEdge(edge('e1', 'a', 'b'));
        c.addEdge(edge('e2', 'b', 'a'));
        c.selectEdge('e1');

        List<String>? deletedEdges;
        Set<String>? deletedNodes;
        c.onEdgesDeleted = (ids) => deletedEdges = ids;
        c.onDeleted = (ids) => deletedNodes = ids;

        c.deleteSelection();

        // The selected edge is gone; the unselected edge and both nodes remain.
        expect(c.getEdge('e1'), isNull);
        expect(c.getEdge('e2'), isNotNull);
        expect(c.getNode('a'), isNotNull);
        expect(c.getNode('b'), isNotNull);
        expect(deletedEdges, <String>['e1']);
        // No node was selected, so onDeleted must not fire.
        expect(deletedNodes, isNull);
      },
    );

    test('deleteSelection reports edges dropped with a deleted node', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));
      c.addNode(node('b', 100, 0));
      c.addEdge(edge('e1', 'a', 'b'));
      c.select(<String>['a']);
      c.selectEdge('e1'); // also explicitly selected

      final removed = <String>[];
      c.onEdgesDeleted = (ids) => removed.addAll(ids);

      c.deleteSelection();

      expect(c.getNode('a'), isNull);
      expect(c.edges, isEmpty);
      // Incident + explicitly-selected collapse to a single id (deduped).
      expect(removed, <String>['e1']);
    });

    test('deleteSelection with nothing selected is a no-op', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));
      c.addEdge(edge('e', 'a', 'a'));

      var edgesFired = false;
      var nodesFired = false;
      c.onEdgesDeleted = (_) => edgesFired = true;
      c.onDeleted = (_) => nodesFired = true;

      c.deleteSelection();

      expect(c.getNode('a'), isNotNull);
      expect(c.getEdge('e'), isNotNull);
      expect(edgesFired, isFalse);
      expect(nodesFired, isFalse);
    });
  });

  group('edge accents', () {
    const teal = Color(0xFF17A398);
    const red = Color(0xFFC0392B);

    test('an edge starts with no accent, and the constructor can seed one', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));
      c.addNode(node('b', 100, 0));
      c.addEdge(edge('e1', 'a', 'b'));
      c.addEdge(
        FlowEdge<String>(
          id: 'e2',
          sourceNodeId: 'b',
          sourcePortId: 'out',
          targetNodeId: 'a',
          targetPortId: 'in',
          accent: teal,
        ),
      );

      expect(c.getEdge('e1')!.accent, isNull);
      expect(c.getEdge('e2')!.accent, teal);
    });

    test('setEdgeAccent sets the color and bumps edgeAccentVersion', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));
      c.addNode(node('b', 100, 0));
      c.addEdge(edge('e1', 'a', 'b'));

      var notified = 0;
      c.edgeAccentVersion.addListener(() => notified += 1);

      c.setEdgeAccent('e1', teal);

      expect(c.getEdge('e1')!.accent, teal);
      expect(notified, 1);

      // A different color notifies again; the same one does not.
      c.setEdgeAccent('e1', red);
      expect(notified, 2);
      c.setEdgeAccent('e1', red);
      expect(notified, 2);
    });

    test('setEdgeAccent(null) clears one edge', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));
      c.addNode(node('b', 100, 0));
      c.addEdge(edge('e1', 'a', 'b'));
      c.setEdgeAccent('e1', teal);

      var notified = 0;
      c.edgeAccentVersion.addListener(() => notified += 1);

      c.setEdgeAccent('e1', null);

      expect(c.getEdge('e1')!.accent, isNull);
      expect(notified, 1);
      // Already clear: no second notification.
      c.setEdgeAccent('e1', null);
      expect(notified, 1);
    });

    test('unknown ids are ignored', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      var notified = 0;
      c.edgeAccentVersion.addListener(() => notified += 1);

      c.setEdgeAccent('ghost', teal);

      expect(notified, 0);
    });

    test('clearEdgeAccents clears every edge and notifies once', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));
      c.addNode(node('b', 100, 0));
      c.addEdge(edge('e1', 'a', 'b'));
      c.addEdge(edge('e2', 'b', 'a'));
      c.setEdgeAccent('e1', teal);
      c.setEdgeAccent('e2', red);

      var notified = 0;
      c.edgeAccentVersion.addListener(() => notified += 1);

      c.clearEdgeAccents();

      expect(c.edges.map((e) => e.accent), everyElement(isNull));
      expect(notified, 1);
      // Nothing left to clear: no-op.
      c.clearEdgeAccents();
      expect(notified, 1);
    });

    test('accents and selection are independent channels', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0));
      c.addNode(node('b', 100, 0));
      c.addEdge(edge('e1', 'a', 'b'));

      final selectionAtStart = c.edgeSelectionVersion.value;
      c.setEdgeAccent('e1', teal);
      expect(c.getEdge('e1')!.selected.value, isFalse);
      expect(
        c.edgeSelectionVersion.value,
        selectionAtStart,
        reason: 'painting an accent must not look like a selection change',
      );

      final accentAtStart = c.edgeAccentVersion.value;
      c.selectEdge('e1');
      expect(
        c.getEdge('e1')!.accent,
        teal,
        reason: 'selection kept the accent',
      );
      expect(c.edgeAccentVersion.value, accentAtStart);

      // And each clear leaves the other channel alone.
      c.clearEdgeSelection();
      expect(c.getEdge('e1')!.accent, teal);
      c.setEdgeAccent('e1', teal); // no-op
      c.clearEdgeAccents();
      expect(c.getEdge('e1')!.selected.value, isFalse);
    });
  });

  group('structureVersion', () {
    test('bumps on node and edge add/remove', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      final start = c.structureVersion.value;

      c.addNode(node('a', 0, 0));
      c.addNode(node('b', 0, 0));
      c.addEdge(edge('e', 'a', 'b'));
      c.removeEdge('e');
      c.removeNode('a');

      expect(c.structureVersion.value, greaterThan(start));
    });
  });

  group('viewport', () {
    test('zoomTo clamps to [minZoom, maxZoom]', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);

      c.zoomTo(100, screenSize: const Size(800, 600));
      expect(c.viewport.value.zoom, 4.0);

      c.zoomTo(0.001, screenSize: const Size(800, 600));
      expect(c.viewport.value.zoom, 0.2);
    });

    test('zoomTo keeps the focal point fixed', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      const focal = ScreenPosition(Offset(400, 300));

      final worldBefore = c.viewport.value.toGraph(focal);
      c.zoomTo(2, focalPoint: focal);
      final worldAfter = c.viewport.value.toGraph(focal);

      expect(worldAfter.dx, closeTo(worldBefore.dx, 1e-9));
      expect(worldAfter.dy, closeTo(worldBefore.dy, 1e-9));
      expect(c.viewport.value.zoom, 2);
    });

    test('fitView centers node bounds at the computed zoom', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      // Single node bounds (0,0,200,100), center (100,50).
      c.addNode(node('a', 0, 0, size: const Size(200, 100)));

      // 1000x1000 screen, 20% padding -> 600 available each axis.
      // scaleX = 600/200 = 3, scaleY = 600/100 = 6 -> zoom 3 (maxZoom high).
      c.fitView(screenSize: const Size(1000, 1000), padding: 0.2, maxZoom: 10);

      final vp = c.viewport.value;
      expect(vp.zoom, 3);
      expect(vp.x, 1000 / 2 - 100 * 3); // 200
      expect(vp.y, 1000 / 2 - 50 * 3); // 350
    });

    test('fitView clamps to the maxZoom argument', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0, size: const Size(200, 100)));

      c.fitView(screenSize: const Size(1000, 1000), padding: 0.2, maxZoom: 1);

      final vp = c.viewport.value;
      expect(vp.zoom, 1);
      expect(vp.x, 500 - 100); // 400
      expect(vp.y, 500 - 50); // 450
    });

    test('fitView is a no-op with no nodes', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.fitView(screenSize: const Size(1000, 1000));
      expect(c.viewport.value, const FlowViewport());
    });

    test('centerOnNode centers without changing zoom', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 100, 100, size: const Size(200, 100)));
      c.setViewport(const FlowViewport(zoom: 2));

      c.centerOnNode('a', const Size(800, 600));

      final vp = c.viewport.value;
      // node center = (200, 150).
      expect(vp.zoom, 2);
      expect(vp.x, 400 - 200 * 2); // 0
      expect(vp.y, 300 - 150 * 2); // 0
    });

    test('screenToGraph / graphToScreen round-trip', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.setViewport(const FlowViewport(x: 33, y: -12, zoom: 1.75));

      const p = GraphPosition(Offset(240, -60));
      final back = c.screenToGraph(c.graphToScreen(p));

      expect(back.dx, closeTo(p.dx, 1e-9));
      expect(back.dy, closeTo(p.dy, 1e-9));
    });

    test('zoomIn / zoomOut apply a 1.2 factor', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.setViewport(const FlowViewport(zoom: 1));

      c.zoomIn(screenSize: const Size(800, 600));
      expect(c.viewport.value.zoom, closeTo(1.2, 1e-9));

      c.zoomOut(screenSize: const Size(800, 600));
      expect(c.viewport.value.zoom, closeTo(1.0, 1e-9));
    });
  });

  group('marquee', () {
    test('updateMarquee selects intersecting nodes live', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      c.addNode(node('a', 0, 0, size: const Size(50, 50)));
      c.addNode(node('b', 500, 500, size: const Size(50, 50)));

      c.beginMarquee(const GraphPosition(Offset(-10, -10)));
      c.updateMarquee(const GraphPosition(Offset(100, 100)));

      expect(c.selection.value, unorderedEquals(<String>['a']));
      expect(c.marqueeRect.value, isNotNull);

      c.endMarquee();
      expect(c.marqueeRect.value, isNull);
      expect(c.mode.value, FlowInteractionMode.idle);
      // Selection persists after the marquee ends.
      expect(c.selection.value, unorderedEquals(<String>['a']));
    });
  });
}
