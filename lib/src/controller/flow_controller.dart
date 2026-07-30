import 'dart:math' as math;
import 'dart:ui' show Color, Size;

import 'package:flutter/foundation.dart';

import '../models/connection.dart';
import '../models/coordinates.dart';
import '../models/flow_edge.dart';
import '../models/flow_node.dart';
import '../models/flow_port.dart';
import '../models/flow_viewport.dart';
import 'alignment_snap.dart';
import 'interaction_state.dart';

/// The state and behavior hub for a [NodeFlow] canvas.
///
/// Holds the node/edge graph, the camera ([viewport]), selection, and
/// interaction mode. Widgets subscribe to the fine-grained [ValueNotifier]s
/// (per-node position/selection, [viewport], [structureVersion], [selection],
/// [marqueeRect], [mode]) so that only the smallest affected subtree rebuilds.
///
/// Type parameters:
/// - [T]: application payload carried by each [FlowNode].
/// - [E]: application payload carried by each [FlowEdge].
class FlowController<T, E> extends ChangeNotifier {
  FlowController({
    this.minZoom = 0.2,
    this.maxZoom = 4.0,
    this.snapGrid = 20.0,
    FlowViewport initialViewport = const FlowViewport(),
  }) : viewport = ValueNotifier(initialViewport);

  /// Minimum zoom factor.
  final double minZoom;

  /// Maximum zoom factor.
  final double maxZoom;

  /// Grid quantum (graph units) that positions snap to on drag commit.
  final double snapGrid;

  // Ordered so that insertion order is a stable tie-breaker for z-sorting.
  final Map<String, FlowNode<T>> _nodes = <String, FlowNode<T>>{};
  final Map<String, FlowEdge<E>> _edges = <String, FlowEdge<E>>{};

  /// The camera: screen-pixel pan (x, y) plus a zoom factor.
  final ValueNotifier<FlowViewport> viewport;

  /// Bumped whenever the node/edge set changes; drives the render node layer.
  final ValueNotifier<int> structureVersion = ValueNotifier<int>(0);

  /// The current pointer-interaction mode.
  final ValueNotifier<FlowInteractionMode> mode =
      ValueNotifier<FlowInteractionMode>(FlowInteractionMode.idle);

  /// The set of currently selected node ids (unmodifiable).
  final ValueNotifier<Set<String>> selection = ValueNotifier<Set<String>>(
    const <String>{},
  );

  /// The active marquee rectangle in graph coordinates, or `null`.
  final ValueNotifier<GraphRect?> marqueeRect = ValueNotifier<GraphRect?>(null);

  /// The ids of the nodes currently being dragged. Edges incident to these are
  /// painted on the "active" edge layer so a drag repaints only those edges.
  final ValueNotifier<Set<String>> draggingNodeIds = ValueNotifier<Set<String>>(
    const <String>{},
  );

  /// Bumped whenever an edge's selection flag changes; drives the edge layers'
  /// repaint without touching [structureVersion] (which rebuilds nodes).
  final ValueNotifier<int> edgeSelectionVersion = ValueNotifier<int>(0);

  /// Bumped whenever an edge's [FlowEdge.accent] changes; drives the edge
  /// layers' repaint. Separate from [edgeSelectionVersion] so an app painting
  /// accents does not look like the user selecting edges.
  final ValueNotifier<int> edgeAccentVersion = ValueNotifier<int>(0);

  /// The in-flight drag-to-connect gesture, or `null`. The preview painter
  /// subscribes to this.
  final ValueNotifier<PendingConnection?> pendingConnection =
      ValueNotifier<PendingConnection?>(null);

  /// The alignment guides active for the in-flight node drag (empty when not
  /// dragging or nothing aligns). The guides painter subscribes to this.
  final ValueNotifier<List<FlowAlignmentGuide>> activeGuides =
      ValueNotifier<List<FlowAlignmentGuide>>(const []);

  /// Whether node drags detect alignment against other nodes (soft snap +
  /// painted guides). Off by default at the controller level so headless
  /// controller usage keeps exact deltas; [NodeFlow] turns it on via its
  /// `snapGuides` parameter.
  bool snapGuidesEnabled = false;

  /// Last layout size reported by the canvas, used by viewport ops that are
  /// invoked without an explicit screen size.
  Size? lastKnownScreenSize;

  /// Invoked after a drag commit with the snapped positions of the nodes that
  /// moved. Wire this to the app's undo stack.
  void Function(Map<String, GraphPosition> committed)? onMoveCommitted;

  /// Invoked after [deleteSelection] with the removed node ids.
  void Function(Set<String> nodeIds)? onDeleted;

  /// Invoked after [deleteSelection] with the ids of the removed edges (the
  /// selected edges plus any edge removed because an endpoint node was
  /// deleted). Empty when no edge was removed; not called in that case.
  void Function(List<String> edgeIds)? onEdgesDeleted;

  // Nodes touched by the in-flight drag; snapped together on [commitMove].
  final Set<String> _activeMove = <String>{};

  // Anchor of the in-flight marquee, in graph coordinates.
  GraphPosition? _marqueeAnchor;

  // ---------------------------------------------------------------------------
  // Nodes
  // ---------------------------------------------------------------------------

  /// Adds [node]. Ignored if a node with the same id already exists.
  void addNode(FlowNode<T> node) {
    if (_nodes.containsKey(node.id)) return;
    _nodes[node.id] = node;
    _bumpStructure();
  }

  /// Replaces the immutable content of an existing node without disturbing
  /// controller-owned interaction state. Selection, z-order, measured size,
  /// an active move, drag membership, and incident edges all survive.
  ///
  /// Returns `false` when [node.id] is not present. The caller remains
  /// responsible for disposing any resources held by the old node's generic
  /// [FlowNode.data] value; this controller only owns [FlowNode.dispose].
  bool replaceNode(FlowNode<T> node) {
    final existing = _nodes[node.id];
    if (existing == null) return false;
    node.selected.value = existing.selected.value;
    node.measuredSize.value = existing.measuredSize.value;
    node.zIndex.value = existing.zIndex.value;
    _nodes[node.id] = node;
    existing.dispose();
    _bumpStructure();
    return true;
  }

  /// Removes the node with [id] and every edge incident to it.
  void removeNode(String id) {
    final node = _nodes.remove(id);
    if (node == null) return;

    _edges.removeWhere((_, edge) {
      final incident = edge.sourceNodeId == id || edge.targetNodeId == id;
      if (incident) edge.dispose();
      return incident;
    });

    _activeMove.remove(id);
    if (selection.value.contains(id)) {
      final next = <String>{...selection.value}..remove(id);
      selection.value = Set<String>.unmodifiable(next);
    }
    node.dispose();
    _bumpStructure();
  }

  /// Returns the node with [id], or `null`.
  FlowNode<T>? getNode(String id) => _nodes[id];

  /// All nodes in ascending z-order (render order), insertion order as the
  /// stable tie-breaker.
  List<FlowNode<T>> get nodes {
    final entries = _nodes.values.toList(growable: false);
    final indexed = <(int, FlowNode<T>)>[
      for (var i = 0; i < entries.length; i++) (i, entries[i]),
    ];
    indexed.sort((a, b) {
      final byZ = a.$2.zIndex.value.compareTo(b.$2.zIndex.value);
      return byZ != 0 ? byZ : a.$1.compareTo(b.$1);
    });
    return <FlowNode<T>>[for (final e in indexed) e.$2];
  }

  /// Moves the node with [id] by [delta]. If the node is part of the current
  /// selection, the whole selection moves together. Live drag is free-form
  /// except for alignment snapping (when [snapGuidesEnabled]); grid snapping
  /// is applied only on [commitMove]. Locked nodes are skipped.
  void moveNodeBy(String id, GraphOffset delta) {
    final node = _nodes[id];
    if (node == null) return;

    final ids = selection.value.contains(id) ? selection.value : <String>{id};
    final moving = <FlowNode<T>>[
      for (final nid in ids)
        if (_nodes[nid] case final FlowNode<T> n when !n.locked) n,
    ];
    if (moving.isEmpty) return;

    var applied = delta;
    // Alignment detection is skipped for large selections — the guides are a
    // precision affordance, not a bulk-layout tool — and against locked-in
    // O(moving × others) cost.
    if (snapGuidesEnabled && moving.length <= 10) {
      var union = moving.first.bounds.translate(delta);
      for (final n in moving.skip(1)) {
        union = union.expandToInclude(n.bounds.translate(delta));
      }
      final movingIds = {for (final n in moving) n.id};
      final result = resolveAlignmentSnap(
        movingBounds: union,
        delta: delta,
        others: [
          for (final n in _nodes.values)
            if (!movingIds.contains(n.id)) n.bounds,
        ],
      );
      applied = result.delta;
      if (!_sameGuides(activeGuides.value, result.guides)) {
        activeGuides.value = result.guides;
      }
    }

    for (final n in moving) {
      n.position.value = n.position.value.translate(applied);
      _activeMove.add(n.id);
    }
  }

  /// Snaps every node moved since the last commit to [snapGrid] and fires
  /// [onMoveCommitted] with their final positions. When alignment guides are
  /// active at commit time the aligned positions win over the grid (grid
  /// snapping would break the just-established alignment by up to half a
  /// grid cell).
  void commitMove() {
    final aligned = activeGuides.value.isNotEmpty;
    if (aligned) activeGuides.value = const [];
    if (_activeMove.isEmpty) return;
    final committed = <String, GraphPosition>{};
    for (final id in _activeMove) {
      final n = _nodes[id];
      if (n == null) continue;
      final snapped = aligned ? n.position.value : _snap(n.position.value);
      n.position.value = snapped;
      committed[id] = snapped;
    }
    _activeMove.clear();
    if (committed.isNotEmpty) onMoveCommitted?.call(committed);
  }

  static bool _sameGuides(
    List<FlowAlignmentGuide> a,
    List<FlowAlignmentGuide> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Selects [id] (if needed), raises it to the top, and enters
  /// [FlowInteractionMode.draggingNode]. Preserves a multi-selection the node
  /// already belongs to.
  void beginNodeDrag(String id) {
    final node = _nodes[id];
    if (node == null || node.locked) return;
    if (!selection.value.contains(id)) {
      _applySelection(<String>{id});
    }
    _bringToFront(id);
    final moving = <String>{
      for (final nid in selection.value)
        if (_nodes[nid]?.locked == false) nid,
    };
    draggingNodeIds.value = Set<String>.unmodifiable(moving);
    mode.value = FlowInteractionMode.draggingNode;
  }

  /// Commits the in-flight drag and returns to [FlowInteractionMode.idle].
  void endNodeDrag() {
    commitMove();
    if (draggingNodeIds.value.isNotEmpty) {
      draggingNodeIds.value = const <String>{};
    }
    mode.value = FlowInteractionMode.idle;
  }

  GraphPosition _snap(GraphPosition p) {
    if (snapGrid <= 0) return p;
    return GraphPosition.fromXY(
      (p.dx / snapGrid).round() * snapGrid,
      (p.dy / snapGrid).round() * snapGrid,
    );
  }

  void _bringToFront(String id) {
    final node = _nodes[id];
    if (node == null) return;
    var maxZ = node.zIndex.value;
    var othersMax = 0;
    for (final n in _nodes.values) {
      if (identical(n, node)) continue;
      othersMax = math.max(othersMax, n.zIndex.value);
    }
    maxZ = math.max(maxZ, othersMax);
    // Already strictly on top: nothing to do.
    if (node.zIndex.value > othersMax) return;
    node.zIndex.value = maxZ + 1;
    _bumpStructure();
  }

  // ---------------------------------------------------------------------------
  // Edges
  // ---------------------------------------------------------------------------

  /// Adds [edge]. Ignored if an edge with the same id already exists.
  void addEdge(FlowEdge<E> edge) {
    if (_edges.containsKey(edge.id)) return;
    _edges[edge.id] = edge;
    _bumpStructure();
  }

  /// Removes the edge with [id].
  void removeEdge(String id) {
    final edge = _edges.remove(id);
    if (edge == null) return;
    edge.dispose();
    _bumpStructure();
  }

  /// All edges in insertion order.
  List<FlowEdge<E>> get edges => _edges.values.toList(growable: false);

  /// Edges incident to [nodeId] (as source or target).
  List<FlowEdge<E>> edgesForNode(String nodeId) => <FlowEdge<E>>[
    for (final e in _edges.values)
      if (e.sourceNodeId == nodeId || e.targetNodeId == nodeId) e,
  ];

  /// Returns the edge with [id], or `null`.
  FlowEdge<E>? getEdge(String id) => _edges[id];

  /// Whether an edge already connects the given source/target port pair,
  /// regardless of id. Used to dedupe drag-to-connect requests.
  bool connectionExists(
    String sourceNodeId,
    String sourcePortId,
    String targetNodeId,
    String targetPortId,
  ) {
    for (final e in _edges.values) {
      if (e.sourceNodeId == sourceNodeId &&
          e.sourcePortId == sourcePortId &&
          e.targetNodeId == targetNodeId &&
          e.targetPortId == targetPortId) {
        return true;
      }
    }
    return false;
  }

  /// Selects the edge with [id]. When [additive] is `false` (the default) every
  /// other edge is deselected; when `true` the edge is added to the current
  /// edge selection. Unknown ids are ignored.
  void selectEdge(String id, {bool additive = false}) {
    final edge = _edges[id];
    if (edge == null) return;
    if (!additive) {
      for (final e in _edges.values) {
        if (!identical(e, edge) && e.selected.value) e.selected.value = false;
      }
    }
    edge.selected.value = true;
    _bumpEdgeSelection();
  }

  /// Deselects every edge.
  void clearEdgeSelection() {
    var changed = false;
    for (final e in _edges.values) {
      if (e.selected.value) {
        e.selected.value = false;
        changed = true;
      }
    }
    if (changed) _bumpEdgeSelection();
  }

  void _bumpEdgeSelection() {
    edgeSelectionVersion.value = edgeSelectionVersion.value + 1;
  }

  /// Sets the accent color of the edge with [id], or clears it with `null`.
  ///
  /// The accent is an app-owned highlight channel (a traversed path, a failing
  /// branch) that leaves selection to the user: an accented edge paints in
  /// [accent], a selected edge still paints selected. Unknown ids are ignored,
  /// and re-setting the color an edge already has does not notify.
  void setEdgeAccent(String id, Color? accent) {
    final edge = _edges[id];
    if (edge == null || edge.accent == accent) return;
    edge.accent = accent;
    _bumpEdgeAccent();
  }

  /// Clears every edge accent. Leaves the edge selection untouched.
  void clearEdgeAccents() {
    var changed = false;
    for (final e in _edges.values) {
      if (e.accent != null) {
        e.accent = null;
        changed = true;
      }
    }
    if (changed) _bumpEdgeAccent();
  }

  void _bumpEdgeAccent() {
    edgeAccentVersion.value = edgeAccentVersion.value + 1;
  }

  // ---------------------------------------------------------------------------
  // Connection dragging
  // ---------------------------------------------------------------------------

  /// Begins a drag-to-connect gesture from [port] on [nodeId], with the pointer
  /// currently at [point] (graph coordinates). Enters
  /// [FlowInteractionMode.draggingConnection].
  void beginConnection(String nodeId, FlowPort port, GraphPosition point) {
    pendingConnection.value = PendingConnection(
      sourceNodeId: nodeId,
      sourcePort: port,
      point: point,
    );
    mode.value = FlowInteractionMode.draggingConnection;
  }

  /// Updates the in-flight connection's pointer [point] and, optionally, the
  /// compatible target port currently under the pointer. Pass
  /// [targetNodeId]/[targetPort] as `null` to clear the highlight.
  void updateConnection(
    GraphPosition point, {
    String? targetNodeId,
    FlowPort? targetPort,
  }) {
    final current = pendingConnection.value;
    if (current == null) return;
    pendingConnection.value = current.copyWith(
      point: point,
      targetNodeId: targetNodeId,
      targetPort: targetPort,
      clearTarget: targetNodeId == null || targetPort == null,
    );
  }

  /// Ends the in-flight connection gesture and returns to
  /// [FlowInteractionMode.idle]. The caller decides whether an edge is created.
  void endConnection() {
    if (pendingConnection.value != null) pendingConnection.value = null;
    if (mode.value == FlowInteractionMode.draggingConnection) {
      mode.value = FlowInteractionMode.idle;
    }
  }

  // ---------------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------------

  /// Selects [ids]. When [additive] is `true` the ids are unioned with the
  /// existing selection; otherwise they replace it. Unknown ids are ignored.
  void select(Iterable<String> ids, {bool additive = false}) {
    final incoming = <String>{
      for (final id in ids)
        if (_nodes.containsKey(id)) id,
    };
    final next = additive
        ? <String>{...selection.value, ...incoming}
        : incoming;
    _applySelection(next);
  }

  /// Clears the selection.
  void clearSelection() => _applySelection(const <String>{});

  /// Toggles [id] in the selection.
  void toggle(String id) {
    if (!_nodes.containsKey(id)) return;
    final next = <String>{...selection.value};
    if (!next.remove(id)) next.add(id);
    _applySelection(next);
  }

  /// Selects every node.
  void selectAll() => _applySelection(_nodes.keys.toSet());

  /// Returns whether [id] is currently selected.
  bool isSelected(String id) => selection.value.contains(id);

  /// Removes the selected nodes and the selected edges. Deleting a node also
  /// removes its incident edges. Fires [onDeleted] with the removed node ids
  /// (only when at least one node was removed) and [onEdgesDeleted] with every
  /// removed edge id (selected edges plus edges dropped with a deleted node).
  void deleteSelection() {
    final nodeIds = selection.value.toSet();
    final selectedEdgeIds = <String>{
      for (final e in _edges.values)
        if (e.selected.value) e.id,
    };
    // Capture edges that will vanish with a deleted endpoint node before the
    // nodes (and thus those edges) are removed.
    final incidentEdgeIds = <String>{
      for (final id in nodeIds)
        for (final e in edgesForNode(id)) e.id,
    };
    if (nodeIds.isEmpty && selectedEdgeIds.isEmpty) return;

    for (final id in nodeIds) {
      removeNode(id); // also removes incident edges
    }
    for (final id in selectedEdgeIds) {
      removeEdge(id); // no-op for edges already removed with a node
    }

    if (nodeIds.isNotEmpty) onDeleted?.call(nodeIds);
    final removedEdges = <String>{...incidentEdgeIds, ...selectedEdgeIds};
    if (removedEdges.isNotEmpty) onEdgesDeleted?.call(removedEdges.toList());
  }

  void _applySelection(Set<String> next) {
    final previous = selection.value;
    for (final id in previous) {
      if (!next.contains(id)) _nodes[id]?.selected.value = false;
    }
    for (final id in next) {
      _nodes[id]?.selected.value = true;
    }
    selection.value = Set<String>.unmodifiable(next);
  }

  // ---------------------------------------------------------------------------
  // Marquee
  // ---------------------------------------------------------------------------

  /// Begins a marquee anchored at [start] (graph coordinates).
  void beginMarquee(GraphPosition start) {
    _marqueeAnchor = start;
    mode.value = FlowInteractionMode.marquee;
    marqueeRect.value = GraphRect.fromLTWH(start.dx, start.dy, 0, 0);
  }

  /// Extends the marquee to [current] and replaces the selection with every
  /// node whose bounds intersect the marquee.
  void updateMarquee(GraphPosition current) {
    final anchor = _marqueeAnchor;
    if (anchor == null) return;
    final rect = GraphRect.fromPoints(anchor, current);
    marqueeRect.value = rect;
    final hit = <String>{
      for (final node in _nodes.values)
        if (node.bounds.overlaps(rect)) node.id,
    };
    _applySelection(hit);
  }

  /// Ends the marquee, keeping the resulting selection.
  void endMarquee() {
    _marqueeAnchor = null;
    marqueeRect.value = null;
    mode.value = FlowInteractionMode.idle;
  }

  // ---------------------------------------------------------------------------
  // Viewport
  // ---------------------------------------------------------------------------

  /// Sets the camera directly. Pan/zoom sync from the canvas flows through here.
  void setViewport(FlowViewport next) {
    if (next != viewport.value) viewport.value = next;
  }

  /// Sets the absolute zoom, clamped to `[minZoom, maxZoom]`, keeping
  /// [focalPoint] (default: the screen center) fixed on screen.
  void zoomTo(double zoom, {ScreenPosition? focalPoint, Size? screenSize}) {
    final clamped = zoom.clamp(minZoom, maxZoom);
    final vp = viewport.value;
    final size = screenSize ?? lastKnownScreenSize;
    final focal =
        focalPoint ??
        (size != null
            ? ScreenPosition.fromXY(size.width / 2, size.height / 2)
            : ScreenPosition.zero);
    final world = vp.toGraph(focal);
    setViewport(
      FlowViewport(
        x: focal.dx - world.dx * clamped,
        y: focal.dy - world.dy * clamped,
        zoom: clamped,
      ),
    );
  }

  /// Zooms in by a factor of 1.2 about the screen center.
  void zoomIn({Size? screenSize}) =>
      zoomTo(viewport.value.zoom * 1.2, screenSize: screenSize);

  /// Zooms out by a factor of 1.2 about the screen center.
  void zoomOut({Size? screenSize}) =>
      zoomTo(viewport.value.zoom / 1.2, screenSize: screenSize);

  /// Fits all node bounds into view.
  ///
  /// [padding] is a fraction of each screen dimension reserved as margin on
  /// each side (0.2 == 20%). The resulting zoom is clamped to
  /// `[minZoom, min(maxZoom, this.maxZoom)]`. No-op when there are no nodes or
  /// no known screen size.
  void fitView({Size? screenSize, double padding = 0.2, double maxZoom = 1}) {
    final size = screenSize ?? lastKnownScreenSize;
    if (size == null || size.isEmpty) return;
    final bounds = nodesBounds;
    if (bounds == null || bounds.isEmpty) return;

    final availableWidth = size.width * (1 - 2 * padding);
    final availableHeight = size.height * (1 - 2 * padding);
    if (availableWidth <= 0 || availableHeight <= 0) return;

    final scaleX = availableWidth / bounds.width;
    final scaleY = availableHeight / bounds.height;
    final upperZoom = math.min(maxZoom, this.maxZoom);
    final zoom = math.min(scaleX, scaleY).clamp(minZoom, upperZoom);

    final center = bounds.center;
    setViewport(
      FlowViewport(
        x: size.width / 2 - center.dx * zoom,
        y: size.height / 2 - center.dy * zoom,
        zoom: zoom,
      ),
    );
  }

  /// Centers the viewport on the node with [id] without changing zoom.
  void centerOnNode(String id, Size screenSize) {
    final node = _nodes[id];
    if (node == null || screenSize.isEmpty) return;
    final center = node.bounds.center;
    final zoom = viewport.value.zoom;
    setViewport(
      FlowViewport(
        x: screenSize.width / 2 - center.dx * zoom,
        y: screenSize.height / 2 - center.dy * zoom,
        zoom: zoom,
      ),
    );
  }

  /// Converts a screen point to graph coordinates using the current camera.
  GraphPosition screenToGraph(ScreenPosition screenPoint) =>
      viewport.value.toGraph(screenPoint);

  /// Converts a graph point to screen coordinates using the current camera.
  ScreenPosition graphToScreen(GraphPosition graphPoint) =>
      viewport.value.toScreen(graphPoint);

  /// The union of every node's bounds, or `null` when there are no nodes.
  GraphRect? get nodesBounds {
    if (_nodes.isEmpty) return null;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final node in _nodes.values) {
      final b = node.bounds;
      minX = math.min(minX, b.left);
      minY = math.min(minY, b.top);
      maxX = math.max(maxX, b.right);
      maxY = math.max(maxY, b.bottom);
    }
    if (minX == double.infinity) return null;
    return GraphRect.fromLTWH(minX, minY, maxX - minX, maxY - minY);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  void _bumpStructure() {
    structureVersion.value = structureVersion.value + 1;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    for (final edge in _edges.values) {
      edge.dispose();
    }
    _nodes.clear();
    _edges.clear();
    viewport.dispose();
    structureVersion.dispose();
    mode.dispose();
    selection.dispose();
    marqueeRect.dispose();
    draggingNodeIds.dispose();
    edgeSelectionVersion.dispose();
    edgeAccentVersion.dispose();
    pendingConnection.dispose();
    activeGuides.dispose();
    super.dispose();
  }
}
