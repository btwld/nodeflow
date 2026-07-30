# Changelog

## 0.2.1

- Fixed alignment snapping pinning dragged nodes: the snap correction was fed
  back into the node position, so escaping a guide required a single fast
  pointer event larger than the threshold — slow, precise drags could never
  break free, and the swallowed travel left the node drifting away from the
  cursor. Node drags now track the raw pointer offset from drag start and
  compute snapping as a pure function of it: a guide holds while the raw
  position is within the threshold and releases exactly when it travels past,
  with the node always landing back under the cursor.
- The guide capture radius is now a constant *screen* distance: the new
  `FlowController.snapGuideThreshold` (default 8 logical pixels, mutable at
  runtime) is divided by the current zoom, so the magnet feels the same at
  every zoom level. Previously it was 6 graph units, which grew stronger the
  further you zoomed in. Note the graph-unit radius now grows when zoomed
  out (8 px at zoom 0.5 is 16 graph units), so drags can align — and commit
  off-grid — across slightly larger distances than before.
- `FlowController.cancelNodeDrag()` aborts an in-flight drag and restores the
  dragged nodes to their drag-start positions; the node gesture wires it to
  the recognizer's cancel callback, so a system takeover mid-drag no longer
  strands the drag session or the interaction mode.
- Mid-drag edge cases hardened: `replaceNode` and a mid-drag `commitMove`
  re-anchor the live drag (their positions stick instead of being reverted by
  the next pointer event), a node locked and unlocked mid-drag stays where it
  stopped instead of teleporting, releasing a drag on a node locked mid-drag
  commits instead of leaving the canvas stuck, and stale guides are cleared
  when snapping is disabled mid-drag.
- `FlowNode.boundsAt(origin)` returns the node's bounds at a hypothetical
  position; `resolveAlignmentSnap`'s default threshold is now 8.0 to match
  the controller's default.

## 0.2.0

- Per-edge accent colors: `FlowEdge.accent` (also settable in the constructor)
  paints one edge in its own color instead of `FlowTheme.edge`, so an app can
  highlight a traversed path, a failing branch, or a data type without
  borrowing selection for it.
- `FlowController.setEdgeAccent(id, color)` and
  `FlowController.clearEdgeAccents()` apply accents and repaint the edge layers
  through the new `FlowController.edgeAccentVersion` notifier, leaving the edge
  selection — and `edgeSelectionVersion` — untouched.
- Painting precedence is selected > accent > theme default: a selected edge
  still paints selected (and heavier) whatever its accent, and accents compose
  with the animated flowing dash unchanged.

## 0.1.1

- No functional changes. Infrastructure release: CI and automated publishing
  from GitHub Actions.

## 0.1.0

Initial release.

- `NodeFlow<T, E>` canvas widget: infinite pan/zoom viewport, dotted background
  grid, app-defined node visuals via `nodeBuilder`.
- `FlowController<T, E>`: nodes, edges, selection, marquee, viewport operations
  (`fitView`, `zoomTo`, `centerOnNode`), and callback seams for app-owned
  undo/persistence (`onMoveCommitted`, `onDeleted`, `onEdgesDeleted`).
- Node dragging with multi-selection, locked nodes, grid snap on commit, and
  Figma-style alignment snap guides.
- Ports and drag-to-connect with compatible-port detection, connection preview,
  and normalized `onConnect` requests.
- Edge styles: bezier, smoothstep, and straight, with optional animated
  flowing-dash rendering, hit-testing, and selection.
- Pannable minimap overlay with viewport indicator.
- Zero-dependency theming: explicit `FlowTheme`, `ThemeData` extension lookup,
  or built-in dark defaults.
