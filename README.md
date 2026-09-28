# NodeFlow

[![pub package](https://img.shields.io/pub/v/node_flow.svg)](https://pub.dev/packages/node_flow)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A [React Flow](https://reactflow.dev)-style node editor canvas for Flutter.
Build workflow editors, pipelines, mind maps, and node-based tools with
app-defined node widgets on an infinite pan/zoom canvas — with zero
dependencies beyond the Flutter SDK.

## Features

- **Infinite canvas** — pan/zoom viewport (`InteractiveViewer`-backed) with
  trackpad/mouse disambiguation, `fitView`, `zoomTo`, and `centerOnNode`.
- **App-defined nodes** — every node is rendered by your `nodeBuilder`; node
  payloads are generic (`FlowNode<T>`), and the canvas auto-measures each
  node's laid-out size.
- **Dragging & selection** — single and multi-node drag, locked nodes, grid
  snap on commit, click/toggle/select-all, and shift-drag marquee selection.
- **Alignment snap guides** — Figma-style soft snapping against other nodes
  with dashed guide lines while dragging; the capture radius is a constant
  screen distance (`FlowController.snapGuideThreshold`, 8px) at every zoom.
- **Ports & connections** — input/output ports on any node side, drag-to-connect
  with compatible-port detection, a live connection preview, and normalized
  `onConnect` requests and optional application validation during hover/drop
  (the canvas never mutates your graph).
- **Edges** — bezier, smoothstep, or straight routing with React-Flow-compatible
  path math, optional animated flowing dash, hit-testing, selection,
  per-edge accent colors, and warning badges on resolvable marked edges.
- **Minimap** — pannable overview with a viewport indicator.
- **Zero-dependency theming** — pass a `FlowTheme`, register one as a
  `ThemeExtension`, or use the built-in dark palette.

The canvas is deliberately unopinionated about persistence and history:
serialization and undo/redo stay in your app, wired through controller
callbacks (`onMoveCommitted`, `onDeleted`, `onEdgesDeleted`).

## Getting started

```yaml
dependencies:
  node_flow: ^0.2.1
```

## Usage

```dart
import 'package:node_flow/node_flow.dart';
import 'package:flutter/material.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final FlowController<String, void> controller;

  @override
  void initState() {
    super.initState();
    controller = FlowController<String, void>();
    _setUpGraph();
  }

  void _setUpGraph() {
    controller.addNode(FlowNode(
      id: 'a',
      type: 'card',
      data: 'Hello',
      position: const GraphPosition(Offset(80, 120)),
      ports: const [
        FlowPort(id: 'out', side: PortSide.right, kind: PortKind.output),
      ],
    ));
    controller.addNode(FlowNode(
      id: 'b',
      type: 'card',
      data: 'World',
      position: const GraphPosition(Offset(420, 200)),
      ports: const [
        FlowPort(id: 'in', side: PortSide.left, kind: PortKind.input),
      ],
    ));
    controller.addEdge(FlowEdge(
      id: 'a:out-b:in',
      sourceNodeId: 'a',
      sourcePortId: 'out',
      targetNodeId: 'b',
      targetPortId: 'in',
    ));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NodeFlow<String, void>(
      controller: controller,
      nodeBuilder: (context, node) => SizedBox(
        width: 200,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(node.data),
          ),
        ),
      ),
      onConnect: (request) {
        controller.addEdge(FlowEdge(
          id: '${request.sourceNodeId}:${request.sourcePortId}-'
              '${request.targetNodeId}:${request.targetPortId}',
          sourceNodeId: request.sourceNodeId,
          sourcePortId: request.sourcePortId,
          targetNodeId: request.targetNodeId,
          targetPortId: request.targetPortId,
        ));
        return true;
      },
    );
  }
}
```

See [`example/`](example/) for a runnable demo covering static graphs, editing,
edge styles, and drag-to-connect.

## Connection validation

Pass an optional `isValidConnection` predicate to reject a proposed edge while
it is being dragged. It receives the same output-to-input-normalized request as
`onConnect`. The canvas checks port direction, self-connections, and duplicate
port pairs first; invalid targets are not highlighted and never reach
`onConnect`. It checks again at drop time in case application state changed.

```dart
NodeFlow<String, void>(
  controller: controller,
  nodeBuilder: (context, node) => Text(node.data),
  isValidConnection: (request) => !controller.edges.any(
    (edge) => edge.targetNodeId == request.targetNodeId &&
        edge.targetPortId == request.targetPortId,
  ),
  onConnect: (request) {
    // Recheck application rules before writing if state can change here.
    if (controller.edges.any((edge) =>
        edge.targetNodeId == request.targetNodeId &&
        edge.targetPortId == request.targetPortId)) return false;
    controller.addEdge(FlowEdge<void>(
      id: '${request.sourceNodeId}:${request.sourcePortId}-'
          '${request.targetNodeId}:${request.targetPortId}',
      sourceNodeId: request.sourceNodeId,
      sourcePortId: request.sourcePortId,
      targetNodeId: request.targetNodeId,
      targetPortId: request.targetPortId,
    ));
    return true;
  },
);
```

This single-input rule is just an example. Your application decides type,
cardinality, and cycle policy. The predicate should be synchronous and must not
mutate the graph. Direct `controller.addEdge` calls are unaffected. The
`onConnect` boolean return is retained for 0.2.x compatibility and does not
control whether the canvas adds an edge; your callback owns that operation.

## Node data and navigation

Application status belongs in your node data. For example, with a
`FlowController<JobData, void>` whose immutable `JobData` provides `copyWith`:

```dart
controller.updateNodeData(
  'job-1',
  (data) => data.copyWith(status: JobStatus.running),
);
```

Render that status with your own badge, progress indicator, or buttons in
`nodeBuilder`. The update rebuilds the node while preserving its position,
selection, ports, lock state, and connections. It returns `false` for an unknown
node ID. The updater must return a new value without mutating the controller
or previous data. As with `replaceNode`, the old node's notifiers are disposed;
release application-owned resources separately when necessary.

Once the canvas is laid out, navigate to a node without measuring the canvas:

```dart
controller.centerOnNode('job-1');
```

This immediately centers the node at the current zoom. Headless callers can
still pass a size: `controller.centerOnNode('job-1', const Size(800, 600))`.
Before a canvas size is known, or if the node is missing, centering does nothing.
`fitView()` fits the whole graph; `zoomTo()` changes the zoom. Animated navigation
is not currently provided. Try **Focus Alpha** and **Toggle Alpha status** on the
[editing demo](example/lib/pages/editing_page.dart) for a runnable example.

## Edge accents

Edges paint in `FlowTheme.edge`. Give one its own color when the app needs to
say something about it — a traversed path, a failing branch, a data type —
without borrowing selection, which belongs to the user:

```dart
controller.setEdgeAccent('a-b', const Color(0xFF17A398));
controller.clearEdgeAccents(); // back to the theme color
```

`FlowEdge(accent: ...)` seeds the color up front instead. Selection still wins:
a selected edge paints in `FlowTheme.edgeSelected` whatever its accent, so the
two channels never fight.

## Theming

Resolution order: explicit widget parameter → `ThemeExtension` → dark defaults.

```dart
// 1. Explicit:
NodeFlow(controller: controller, nodeBuilder: ..., theme: myFlowTheme);

// 2. Via your app ThemeData:
MaterialApp(
  theme: ThemeData(
    extensions: [
      const FlowTheme.dark().copyWith(
        background: Color(0xFF0B1020),
        edge: Colors.tealAccent,
      ),
    ],
  ),
  ...
);

// 3. Nothing — built-in dark palette.
```

## License

[MIT](LICENSE)
