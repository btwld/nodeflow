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
  `onConnect` requests (the canvas never mutates your graph).
- **Edges** — bezier, smoothstep, or straight routing with React-Flow-compatible
  path math, optional animated flowing dash, hit-testing, selection, labels,
  per-edge accent colors, and dangling-edge badges.
- **Minimap** — pannable overview with a viewport indicator.
- **Zero-dependency theming** — pass a `FlowTheme`, register one as a
  `ThemeExtension`, or use the built-in dark palette.

The canvas is deliberately unopinionated about persistence and history:
serialization and undo/redo stay in your app, wired through controller
callbacks (`onMoveCommitted`, `onDeleted`, `onEdgesDeleted`).

## Getting started

```yaml
dependencies:
  node_flow: ^0.2.0
```

## Usage

```dart
import 'package:node_flow/node_flow.dart';
import 'package:flutter/material.dart';

final controller = FlowController<String, void>();

void setUpGraph() {
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
    id: 'a-b',
    sourceNodeId: 'a',
    sourcePortId: 'out',
    targetNodeId: 'b',
    targetPortId: 'in',
  ));
}

class EditorScreen extends StatelessWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return NodeFlow<String, void>(
      controller: controller,
      nodeBuilder: (context, node) => SizedBox(
        width: 200,
        child: Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(node.data),
        )),
      ),
      onConnect: (request) {
        controller.addEdge(FlowEdge(
          id: '${request.sourceNodeId}-${request.targetNodeId}',
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
