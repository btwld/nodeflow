# Changelog

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
