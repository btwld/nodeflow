import 'dart:ui' show Color;

/// Which edge of a node a port is anchored to.
enum PortSide { left, right, top, bottom }

/// Whether a port receives connections ([input]) or emits them ([output]).
enum PortKind { input, output }

/// The built-in visual style of a port handle.
enum PortVisual {
  /// A simple filled circle.
  circle,

  /// A branch-style connector (e.g. for flow-control fan-out).
  branch,
}

/// A connection point on a node.
final class FlowPort {
  const FlowPort({
    required this.id,
    required this.side,
    required this.kind,
    this.visual = PortVisual.circle,
    this.label,
    this.accent,
  });

  /// Identifier, unique within the owning node.
  final String id;

  /// Which node edge this port anchors to.
  final PortSide side;

  /// Input or output.
  final PortKind kind;

  /// The built-in visual style of the handle.
  final PortVisual visual;

  /// Optional label, rendered by the built-in branch handle.
  final String? label;

  /// Optional handle accent color override.
  final Color? accent;
}
