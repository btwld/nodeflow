import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

/// A directed connection between two node ports.
///
/// Edges are pure data in phases 1-2; rendering arrives in phase 3. Only the
/// [selected] flag is reactive; the other mutable visual state ([accent]) is
/// repainted through the owning controller's version notifiers.
final class FlowEdge<E> {
  FlowEdge({
    required this.id,
    required this.sourceNodeId,
    required this.sourcePortId,
    required this.targetNodeId,
    required this.targetPortId,
    this.data,
    bool selected = false,
    this.dangling = false,
    this.label,
    this.accent,
  }) : selected = ValueNotifier(selected);

  /// Unique identifier within the owning controller.
  final String id;

  /// Id of the node the edge starts from.
  final String sourceNodeId;

  /// Id of the source port on [sourceNodeId].
  final String sourcePortId;

  /// Id of the node the edge ends at.
  final String targetNodeId;

  /// Id of the target port on [targetNodeId].
  final String targetPortId;

  /// Optional application payload.
  final E? data;

  /// Whether the edge is part of the current selection.
  final ValueNotifier<bool> selected;

  /// Whether the edge is dangling (an endpoint is missing/unresolved).
  final bool dangling;

  /// Optional label rendered along the edge (phase 3).
  final String? label;

  /// Optional stroke color override, painted instead of [FlowTheme.edge].
  ///
  /// An app-owned highlight channel that is independent of selection — light
  /// up a traversed path, a validation error, a data type — leaving
  /// click-to-select as the user's own affordance. [selected] still wins:
  /// a selected edge paints as selected whatever its accent.
  ///
  /// Mutable, and *not* a [ValueNotifier]: the edge layers repaint from
  /// [FlowController.edgeAccentVersion], exactly as they do for selection, so
  /// a per-edge notifier would have no listener. Assign through
  /// [FlowController.setEdgeAccent] so that bump happens.
  Color? accent;

  /// Releases the edge's notifier. Called by the controller.
  void dispose() {
    selected.dispose();
  }
}
