import 'package:flutter/widgets.dart';

import '../interaction/non_trackpad_pan_gesture_recognizer.dart';
import '../models/flow_port.dart';
import '../theme/flow_theme.dart';

/// A single interactive port handle, stacked over a node at its port anchor.
///
/// Renders a [PortVisual.circle] dot or a [PortVisual.branch] dot with an
/// always-visible uppercase label. Reports hover via [onHoverChanged] and
/// starts a drag-to-connect gesture through the drag callbacks (which receive
/// global pointer positions so the canvas can map them into its own space).
/// Trackpad gestures bubble to the canvas for panning.
class PortHandle extends StatefulWidget {
  const PortHandle({
    super.key,
    required this.port,
    required this.theme,
    required this.onHoverChanged,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    this.highlighted = false,
  });

  /// The port this handle represents.
  final FlowPort port;

  /// Resolved painter/theme values.
  final FlowTheme theme;

  /// Called with `true` on pointer enter and `false` on exit.
  final ValueChanged<bool> onHoverChanged;

  /// Called when a connection drag begins, with the global pointer position.
  final void Function(Offset globalPosition) onDragStart;

  /// Called on each connection-drag move, with the global pointer position.
  final void Function(Offset globalPosition) onDragUpdate;

  /// Called when the connection drag ends, with the global pointer position.
  final void Function(Offset globalPosition) onDragEnd;

  /// Called when the gesture is cancelled before a normal drag end.
  final VoidCallback onDragCancel;

  /// Whether this handle is the current drop target and should be emphasized.
  final bool highlighted;

  @override
  State<PortHandle> createState() => _PortHandleState();
}

class _PortHandleState extends State<PortHandle> {
  bool _hovered = false;
  Offset _lastGlobal = Offset.zero;

  bool get _emphasized => _hovered || widget.highlighted;

  Color get _accent => widget.port.accent ?? widget.theme.selectionStroke;

  double get _size => widget.port.visual == PortVisual.branch
      ? widget.theme.branchHandleSize
      : widget.theme.handleSize;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
    widget.onHoverChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final dot = _Dot(
      size: _size,
      fill: widget.theme.nodeHandleFill,
      border: widget.port.visual == PortVisual.branch
          ? _accent
          : (_emphasized ? _accent : widget.theme.nodeHandleBorder),
      borderWidth: widget.port.visual == PortVisual.branch || _emphasized
          ? 2
          : 1,
    );

    final Widget content = widget.port.visual == PortVisual.branch
        ? _BranchWithLabel(
            size: _size,
            side: widget.port.side,
            label: (widget.port.label ?? '').toUpperCase(),
            accent: _accent,
            dot: dot,
          )
        : dot;

    return MouseRegion(
      cursor: SystemMouseCursors.precise,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          NonTrackpadPanGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                NonTrackpadPanGestureRecognizer
              >(NonTrackpadPanGestureRecognizer.new, (
                NonTrackpadPanGestureRecognizer recognizer,
              ) {
                recognizer.onStart = (DragStartDetails d) {
                  _lastGlobal = d.globalPosition;
                  widget.onDragStart(d.globalPosition);
                };
                recognizer.onUpdate = (DragUpdateDetails d) {
                  _lastGlobal = d.globalPosition;
                  widget.onDragUpdate(d.globalPosition);
                };
                // DragEndDetails does not reliably carry the pointer position,
                // so use the last one seen during the drag.
                recognizer.onEnd = (DragEndDetails d) {
                  widget.onDragEnd(_lastGlobal);
                };
                recognizer.onCancel = widget.onDragCancel;
              }),
        },
        child: content,
      ),
    );
  }
}

/// The circular dot shared by both visuals.
///
/// The hover ring is applied by the caller flipping [border]/[borderWidth] on
/// hover: hover is owned by [PortHandle]'s own `MouseRegion`, which coexists
/// with the drag-to-connect [RawGestureDetector], so the dot itself stays a
/// plain decorated box and never handles the pointer.
class _Dot extends StatelessWidget {
  const _Dot({
    required this.size,
    required this.fill,
    required this.border,
    required this.borderWidth,
  });

  final double size;
  final Color fill;
  final Color border;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: borderWidth),
      ),
    );
  }
}

/// A branch dot plus its uppercase label, placed on the port's outboard side.
class _BranchWithLabel extends StatelessWidget {
  const _BranchWithLabel({
    required this.size,
    required this.side,
    required this.label,
    required this.accent,
    required this.dot,
  });

  final double size;
  final PortSide side;
  final String label;
  final Color accent;
  final Widget dot;

  @override
  Widget build(BuildContext context) {
    // The dot sizes the stack; the label overflows toward the outboard side and
    // never intercepts pointers.
    final labelWidget = IgnorePointer(
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          color: accent,
          fontSize: 9,
          height: 1,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );

    // The label is a bare Text anchored on the outboard side. A [Positioned]
    // with a single anchor gives it loose constraints, so it sizes to its
    // content (no wrapping) without any box that tries to fill infinite width.
    // The vertical/horizontal nudge approximates centering on the dot; the dot
    // still sizes the surrounding stack.
    const gap = 4.0;
    final half = size / 2;
    const halfLabelHeight = 6.0; // ~half the 9px line box
    const halfLabelGuess = 12.0; // rough half-width for top/bottom centering
    final positionedLabel = switch (side) {
      PortSide.left => Positioned(
        right: size + gap,
        top: half - halfLabelHeight,
        child: labelWidget,
      ),
      PortSide.right => Positioned(
        left: size + gap,
        top: half - halfLabelHeight,
        child: labelWidget,
      ),
      PortSide.top => Positioned(
        bottom: size + gap,
        left: half - halfLabelGuess,
        child: labelWidget,
      ),
      PortSide.bottom => Positioned(
        top: size + gap,
        left: half - halfLabelGuess,
        child: labelWidget,
      ),
    };

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[dot, positionedLabel],
    );
  }
}
