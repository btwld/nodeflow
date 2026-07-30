import '../models/coordinates.dart';

/// An active alignment guide while dragging: a line in graph coordinates at
/// [position] — vertical (x = position, spanning y in `[start, end]`) when
/// [vertical], horizontal otherwise.
final class FlowAlignmentGuide {
  const FlowAlignmentGuide({
    required this.vertical,
    required this.position,
    required this.start,
    required this.end,
  });

  final bool vertical;
  final double position;
  final double start;
  final double end;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FlowAlignmentGuide &&
        other.vertical == vertical &&
        other.position == position &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(vertical, position, start, end);

  @override
  String toString() =>
      'FlowAlignmentGuide(${vertical ? 'x' : 'y'}: $position, '
      '$start..$end)';
}

/// The outcome of alignment detection for one drag step: the (possibly
/// snap-adjusted) delta to apply and the guides to paint.
final class AlignmentSnapResult {
  const AlignmentSnapResult({required this.delta, required this.guides});

  final GraphOffset delta;
  final List<FlowAlignmentGuide> guides;
}

const _guidePadding = 16.0;

/// Detects alignment of [movingBounds] (the dragged selection's bounds AFTER
/// applying the raw [delta]) against [others]: each of the moving edges and
/// centers (left/centerX/right, top/centerY/bottom) is compared per axis and
/// the closest match within [threshold] graph units wins. The returned delta
/// carries the softly-snapped adjustment; the guides span both rects.
///
/// [FlowController] does not use the default [threshold]: it passes
/// `snapGuideThreshold / zoom` so the capture radius is a constant *screen*
/// distance at every zoom level.
AlignmentSnapResult resolveAlignmentSnap({
  required GraphRect movingBounds,
  required GraphOffset delta,
  required Iterable<GraphRect> others,
  double threshold = 8.0,
}) {
  // Strict `<` below makes the FIRST candidate win ties, giving a stable
  // left/center/right (top/center/bottom) priority when several edges align
  // at once (equal-width rects align all three simultaneously).
  double? adjustX;
  double guideX = 0;
  GraphRect? matchX;
  var bestX = threshold + 1e-9;

  double? adjustY;
  double guideY = 0;
  GraphRect? matchY;
  var bestY = threshold + 1e-9;

  final movingXs = [
    movingBounds.left,
    movingBounds.center.dx,
    movingBounds.right,
  ];
  final movingYs = [
    movingBounds.top,
    movingBounds.center.dy,
    movingBounds.bottom,
  ];

  for (final other in others) {
    final otherXs = [other.left, other.center.dx, other.right];
    final otherYs = [other.top, other.center.dy, other.bottom];
    for (final mx in movingXs) {
      for (final ox in otherXs) {
        final distance = (ox - mx).abs();
        if (distance < bestX) {
          bestX = distance;
          adjustX = ox - mx;
          guideX = ox;
          matchX = other;
        }
      }
    }
    for (final my in movingYs) {
      for (final oy in otherYs) {
        final distance = (oy - my).abs();
        if (distance < bestY) {
          bestY = distance;
          adjustY = oy - my;
          guideY = oy;
          matchY = other;
        }
      }
    }
  }

  final guides = <FlowAlignmentGuide>[];
  if (adjustX != null && matchX != null) {
    final top = movingBounds.top < matchX.top ? movingBounds.top : matchX.top;
    final bottom = movingBounds.bottom > matchX.bottom
        ? movingBounds.bottom
        : matchX.bottom;
    guides.add(
      FlowAlignmentGuide(
        vertical: true,
        position: guideX,
        start: top - _guidePadding,
        end: bottom + _guidePadding,
      ),
    );
  }
  if (adjustY != null && matchY != null) {
    final left = movingBounds.left < matchY.left
        ? movingBounds.left
        : matchY.left;
    final right = movingBounds.right > matchY.right
        ? movingBounds.right
        : matchY.right;
    guides.add(
      FlowAlignmentGuide(
        vertical: false,
        position: guideY,
        start: left - _guidePadding,
        end: right + _guidePadding,
      ),
    );
  }

  return AlignmentSnapResult(
    delta: GraphOffset.fromXY(
      delta.dx + (adjustX ?? 0),
      delta.dy + (adjustY ?? 0),
    ),
    guides: guides,
  );
}
