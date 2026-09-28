/// The canvas' current pointer-interaction mode.
///
/// The canvas gates the [InteractiveViewer]'s pan/zoom on this: panning is
/// allowed in [idle] and [panning], and suppressed while a node drag,
/// connection drag, or marquee is in progress.
enum FlowInteractionMode {
  /// No active pointer interaction.
  idle,

  /// The viewport is being panned/zoomed.
  panning,

  /// One or more nodes are being dragged.
  draggingNode,

  /// A connection is being drawn.
  draggingConnection,

  /// A marquee (rubber-band) selection is in progress.
  marquee,
}
