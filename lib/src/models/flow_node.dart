import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Size;

import 'coordinates.dart';
import 'flow_port.dart';

/// A single node in the flow graph.
///
/// A node carries app-defined [data] of type [T] and renders through the
/// canvas' `nodeBuilder`. Mutable visual state (position, measured size,
/// selection, stacking order) is held in [ValueNotifier]s so the canvas can
/// rebuild the smallest possible subtree when any of them change.
final class FlowNode<T> {
  /// Creates a node at [position].
  ///
  /// [size] seeds [measuredSize] until the rendered child reports its real
  /// laid-out size; it defaults to a 256-wide card.
  FlowNode({
    required this.id,
    required this.type,
    required this.data,
    required GraphPosition position,
    Size size = const Size(256, 100),
    this.ports = const [],
    int zIndex = 0,
    bool selected = false,
    this.locked = false,
  }) : position = ValueNotifier(position),
       measuredSize = ValueNotifier(size),
       selected = ValueNotifier(selected),
       zIndex = ValueNotifier(zIndex);

  /// Unique identifier within the owning controller.
  final String id;

  /// Application-defined type discriminator (routes the `nodeBuilder`).
  final String type;

  /// Application payload.
  final T data;

  /// Connection points (rendered in phase 3).
  final List<FlowPort> ports;

  /// Top-left position in graph coordinates.
  final ValueNotifier<GraphPosition> position;

  /// The child's last laid-out size, reported by the canvas after layout.
  final ValueNotifier<Size> measuredSize;

  /// Whether this node is part of the current selection.
  final ValueNotifier<bool> selected;

  /// Stacking order; higher paints on top.
  final ValueNotifier<int> zIndex;

  /// When `true` the node cannot be dragged via the UI. Programmatic moves
  /// still apply.
  bool locked;

  /// Input ports (in declaration order).
  Iterable<FlowPort> get inputs => ports.where((p) => p.kind == PortKind.input);

  /// Output ports (in declaration order).
  Iterable<FlowPort> get outputs =>
      ports.where((p) => p.kind == PortKind.output);

  /// The node's bounds in graph coordinates (position + measured size).
  GraphRect get bounds => boundsAt(position.value);

  /// The bounds the node would have at [origin] with its current measured
  /// size. Used by drag snapping to probe a candidate position without
  /// mutating [position].
  GraphRect boundsAt(GraphPosition origin) => GraphRect.fromLTWH(
    origin.dx,
    origin.dy,
    measuredSize.value.width,
    measuredSize.value.height,
  );

  /// Releases the node's notifiers. Called by the controller.
  void dispose() {
    position.dispose();
    measuredSize.dispose();
    selected.dispose();
    zIndex.dispose();
  }
}
