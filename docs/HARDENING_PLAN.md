# NodeFlow Dart and Flutter hardening plan

This plan keeps NodeFlow a small Flutter canvas package. It does not turn the
package into an application architecture, add a state-management framework, or
introduce repository/data layers that do not belong in this package.

The design target is a set of deep modules with clear ownership:

- **FlowController** owns graph membership, user interaction state, viewport
  invariants, and graph mutations.
- **FlowNode / FlowEdge / FlowPort** carry graph data and narrowly observable
  visual state.
- **NodeFlow** adapts Flutter pointer, keyboard, layout, and transform events to
  the controller.
- **Edge geometry** owns path construction and hit testing from the same
  geometry representation.
- **Painters** consume controller/model state. They do not decide graph state.
- The application owns persistence, serialization, undo/redo, and application
  payloads.

## Constraints

1. Keep the runtime dependency set at Flutter SDK only unless a dependency
   solves a demonstrated problem that cannot be handled cleanly in-package.
2. Preserve Flutter 3.41.0 as the minimum supported Flutter version until a
   deliberate compatibility change is released.
3. Keep rendering invalidation fine-grained. Do not replace the current
   notifier design with whole-canvas rebuilds.
4. Do not split FlowController only because it is large. Extract a module only
   when doing so creates a real seam with higher locality and leverage.
5. Prefer public-seam tests through FlowController and mounted NodeFlow.
6. Treat controllers passed to NodeFlow as borrowed resources. NodeFlow may
   subscribe and unsubscribe, but must not dispose them.
7. Keep app callbacks outside controller invariants. Internal cleanup must
   complete even if an app callback throws.

## Phase 1 — lifecycle correctness

Status: implemented in the hardening branch.

### Controller replacement

- Detach viewport and structure listeners from the old controller in
  `didUpdateWidget`.
- Attach the replacement controller.
- Resynchronize the Flutter `TransformationController` from the replacement
  controller.
- Reset widget-owned pointer bookkeeping.
- Keep the controller borrowed; disposal remains the application's job.

### Interaction termination

Every interaction must have an end state for success, cancellation, and error.

- Pointer cancellation terminates marquee interaction.
- Connection cleanup runs in `finally` when `onConnect` throws.
- Node-drag cleanup runs in `finally` when `onMoveCommitted` throws.
- Cleanup operations remain safe when called after an already-ended gesture.

### Regression seams

Test these through mounted NodeFlow and FlowController:

- controller A -> controller B -> controller A replacement,
- disposal after controller replacement,
- pointer-cancelled marquee,
- throwing connection callback,
- throwing move-commit callback.

## Phase 2 — state ownership and invariants

Status: implemented for non-breaking 0.2.x behavior.

### Selection

The controller's selected-ID set is authoritative for controller operations.

- A node created with `selected: true` is normalized into controller
  selection when added.
- Replacement nodes inherit controller-owned interaction state.
- Documentation tells callers to use controller selection operations after a
  node has been attached.

A future breaking release can make node selection observation read-only to
remove the remaining possibility of direct external writes creating divergent
state.

### Node replacement

Replacing a node with the identical instance is a no-op. The controller must
never dispose an object and then retain that same object as live graph state.

### Viewport

The following invariants hold at controller entry points:

- `minZoom` is finite and greater than zero.
- `maxZoom` is finite and greater than or equal to `minZoom`.
- viewport pan coordinates are finite.
- viewport zoom is finite and greater than zero.
- a valid zoom outside the supported range is clamped.
- `fitView` cannot construct an invalid clamp range when its requested
  maximum is below the controller minimum.

## Phase 3 — rendering invalidation

Status: implemented in the hardening branch.

Painters must listen to the state used to produce their pixels.

### Edge layers

- Structural graph changes invalidate the edge layer.
- The static edge layer listens to geometry for non-dragging nodes.
- The active edge layer listens to geometry for all nodes because an active
  edge can terminate at a non-dragging node.
- The split remains useful: moving a dragged node does not force the static
  edge layer to repaint when edge animation is disabled.

### Minimap

- Recompute and repaint when node position or measured size changes.
- Keep selection and viewport listeners because both affect minimap pixels.
- Do not subscribe to edge selection: the minimap does not render edge
  selection.

## Phase 4 — geometry correctness

Status: implemented for the known cubic overshoot defect.

Drawing and hit testing stay behind the same edge-geometry seam.

The cubic hit-test sampler must account for two independent dimensions:

1. perpendicular deviation away from the endpoint chord;
2. longitudinal overshoot beyond either endpoint along the chord.

Same-side ports can create the second case even when perpendicular deviation is
zero. Regression coverage includes a right-to-right cubic whose visible curve
extends beyond its target endpoint.

Future geometry work should add property-based or table-driven fixtures for:

- all 16 source/target side pairs,
- short and near-coincident endpoints,
- reversed/backward connections,
- high curvature,
- large zoom and small zoom,
- hit-test tolerance near curve extrema.

## Phase 5 — measurement and initial viewport

Status: implemented in the hardening branch.

Node size reporting is deferred until after layout. Initial fitting therefore
must run after that reporting pass, not before it.

- The first post-frame callback schedules the initial fit for the following
  frame.
- An explicit frame is requested because registering a post-frame callback does
  not itself schedule one.
- The fit is tied to the controller that was present during initialization.
- Deferred size reports check that their render object is still attached and
  that the reported measurement is still current.

The canvas does not become permanently auto-fitting. User pan/zoom remains
authoritative after initial setup.

## Phase 6 — public contract cleanup

Status: documentation corrected in the hardening branch; breaking cleanup is
deferred.

### `onConnect`

In 0.2.x, the callback's boolean return remains for compatibility but is not
consumed by the canvas. Acceptance is represented by the application adding an
edge to the controller.

For the next breaking release, choose one interface and remove the ambiguity:

- preferred: `void Function(FlowConnectionRequest)`, because the app owns
  graph mutation; or
- make the boolean meaningful and define exactly what the canvas does on
  acceptance.

Do not keep a boolean that has no observable contract indefinitely.

### Edge labels

`FlowEdge.label` is application metadata today. The built-in painter does not
render it. Documentation now says so.

Before adding built-in labels, define:

- placement along each edge style,
- zoom behavior,
- collision/overflow behavior,
- hit testing,
- accessibility semantics,
- customization interface.

### Dangling edges

A missing endpoint cannot currently produce edge geometry. The `dangling`
flag therefore means “show a warning badge on an otherwise resolvable edge.”
Documentation now matches that behavior.

If unresolved-edge visualization is added later, model the fallback endpoint
explicitly rather than inventing coordinates inside the painter.

## Phase 7 — Dart API simplification candidates for 0.3

These changes are intentionally not mixed into a compatibility hardening patch.

### Read-only observation surfaces

Consider exposing read-only `ValueListenable` views for state that callers
should observe but not mutate directly:

- selection,
- mode,
- dragging node IDs,
- pending connection,
- edge/node selected state.

Keep mutations as named controller operations. This makes invariants easier to
enforce and narrows the public interface.

### Callback grouping

Review callback fields such as `onMoveCommitted`, `onDeleted`, and
`onEdgesDeleted`. Keep them separate if callers commonly use them
independently. Only introduce a grouped event type if real call sites need
atomic graph-change reporting.

### Controller extraction

Do not create shallow pass-through classes. Consider extraction only if one of
these areas develops an independently useful interface and multiple callers:

- graph indexing/query,
- interaction session state machine,
- edge geometry/cache.

The deletion test applies: removing an extracted module should force its
complexity back into several callers. If deletion only removes forwarding code,
the extraction is too shallow.

## Phase 8 — accessibility and input

Status: follow-up.

Define a keyboard and semantics contract before implementing isolated shortcuts.

Questions to answer:

- How does a node receive focus?
- How does keyboard selection coexist with text fields inside app-built nodes?
- What are the non-pointer operations for moving nodes and creating
  connections?
- What semantics describe a port and an edge?
- Should animated edges respect reduced-motion preferences?

Implement this as a coherent interaction design rather than scattered key
handlers.

## Phase 9 — performance

Status: measure before changing architecture.

Create representative benchmarks for at least:

- 100 nodes / 150 edges,
- 500 nodes / 1,000 edges,
- 1,000 nodes / 2,000 edges.

Measure:

- idle animated-edge cost,
- pan/zoom frame time,
- single-node drag,
- multi-node drag,
- minimap enabled/disabled,
- structure updates.

Only then consider:

- viewport culling,
- adjacency indexes,
- cached edge geometry,
- painter recording/caching.

Any optimization must preserve off-screen interaction semantics, size
measurement, focus, and active-drag correctness.

## Phase 10 — CI and release gates

Status: example validation added in the hardening branch.

Required pull-request gates:

1. `dart format --output=none --set-exit-if-changed lib test example/lib`
2. root `flutter analyze`
3. example `flutter analyze`
4. root tests on Flutter 3.41.0
5. root tests on latest stable Flutter
6. example tests on Flutter 3.41.0
7. example tests on latest stable Flutter

Before publishing:

- run package tests,
- run `flutter pub publish --dry-run`,
- verify the release tag matches `pubspec.yaml`,
- keep the documented OIDC workaround only while the upstream pub.dev issue
  still requires it.

## Exit criteria for this hardening branch

The branch can leave draft status when:

- all root and example analysis checks pass,
- root and example tests pass on both supported Flutter tracks,
- no temporary branch-only workflow remains,
- the diff has been reviewed for accidental public breaking changes,
- the changelog describes the observable changes,
- the remaining 0.3 candidates are documented rather than partially
  implemented.
