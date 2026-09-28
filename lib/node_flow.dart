/// NodeFlow — a React-Flow-style node canvas for Flutter.
///
/// The canvas is domain-agnostic: node visuals come from the app through a
/// `nodeBuilder`, node data is generic, and serialization stays with the
/// caller. Rendering is layered (grid, edges, nodes, overlays) with
/// Flutter-native (`ChangeNotifier`/`ValueNotifier`) state.
library;

// Models
export 'src/models/connection.dart';
export 'src/models/coordinates.dart';
export 'src/models/flow_edge.dart';
export 'src/models/flow_node.dart';
export 'src/models/flow_port.dart';
export 'src/models/flow_viewport.dart';

// Controller
export 'src/controller/alignment_snap.dart';
export 'src/controller/flow_controller.dart';
export 'src/controller/interaction_state.dart';

// Edges (path math + public style seam)
export 'src/edges/edge_path.dart';
export 'src/edges/edge_style.dart';
export 'src/edges/path_segments.dart';

// Geometry
export 'src/geometry/port_anchor.dart';

// Rendering
export 'src/render/flow_canvas.dart';
export 'src/render/minimap.dart';

// Theme
export 'src/theme/flow_theme.dart';
