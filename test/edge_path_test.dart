import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:node_flow/node_flow.dart';

// Verifies the ported edge-path math: React-Flow bezier control points, the
// rounded-orthogonal smoothstep shape, and segment hit-rect coverage.

bool _covers(List<Rect> rects, Offset p) => rects.any((r) => r.contains(p));

void main() {
  group('bezier control points', () {
    test('curvature default constant is 0.5', () {
      expect(kDefaultEdgeCurvature, 0.5);
    });

    test('offset = |distance| * curvature when it exceeds the extension', () {
      // source (0,0) facing right, target (200,0) facing left.
      // |dx| = 200, 200 * 0.5 = 100 > portExtension(20) -> offset 100.
      final geo = FlowEdgeStyle.bezier.geometry(
        const Offset(0, 0),
        PortSide.right,
        const Offset(200, 0),
        PortSide.left,
      );
      final segment = geo.segments.single as CubicSegment;
      expect(segment.controlPoint1, const Offset(100, 0));
      expect(segment.controlPoint2, const Offset(100, 0));
      expect(segment.end, const Offset(200, 0));
    });

    test('portExtension is the floor for short spans', () {
      // |dx| = 10, 10 * 0.5 = 5 < portExtension(20) -> offset 20.
      final geo = FlowEdgeStyle.bezier.geometry(
        const Offset(0, 0),
        PortSide.right,
        const Offset(10, 0),
        PortSide.left,
      );
      final segment = geo.segments.single as CubicSegment;
      expect(segment.controlPoint1, const Offset(20, 0));
      expect(segment.controlPoint2, const Offset(-10, 0));
    });

    test('vertical ports offset along the Y axis', () {
      // source (0,0) facing bottom, target (0,200) facing top.
      final geo = FlowEdgeStyle.bezier.geometry(
        const Offset(0, 0),
        PortSide.bottom,
        const Offset(0, 200),
        PortSide.top,
      );
      final segment = geo.segments.single as CubicSegment;
      expect(segment.controlPoint1, const Offset(0, 100));
      expect(segment.controlPoint2, const Offset(0, 100));
    });
  });

  group('smoothstep', () {
    test('produces a rounded orthogonal path spanning both endpoints', () {
      final geo = FlowEdgeStyle.smoothstep.geometry(
        const Offset(0, 0),
        PortSide.right,
        const Offset(200, 100),
        PortSide.left,
      );

      // Starts at the source, ends at the target.
      expect(geo.start, const Offset(0, 0));
      expect(geo.segments.last.end, const Offset(200, 100));

      // Rounded corners are emitted as quadratic segments.
      final quads = geo.segments.whereType<QuadraticSegment>().length;
      expect(quads, greaterThan(0));

      // The path's bounds cover the full span (rounded corners stay inside).
      final bounds = geo.toPath().getBounds();
      expect(bounds.left, closeTo(0, 0.001));
      expect(bounds.top, closeTo(0, 0.001));
      expect(bounds.right, closeTo(200, 0.001));
      expect(bounds.bottom, closeTo(100, 0.001));
    });
  });

  group('straight', () {
    test('emits three straight segments with port extensions', () {
      final geo = FlowEdgeStyle.straight.geometry(
        const Offset(0, 0),
        PortSide.right,
        const Offset(100, 50),
        PortSide.left,
      );
      expect(geo.segments, hasLength(3));
      expect(geo.segments[0].end, const Offset(20, 0));
      expect(geo.segments[1].end, const Offset(80, 50));
      expect(geo.segments[2].end, const Offset(100, 50));
    });
  });

  group('hit-test rects', () {
    test('cover points on a straight path and exclude far points', () {
      final geo = FlowEdgeStyle.straight.geometry(
        const Offset(0, 0),
        PortSide.right,
        const Offset(100, 0),
        PortSide.left,
      );
      final rects = geo.hitTestRects(6);

      expect(_covers(rects, const Offset(50, 0)), isTrue);
      expect(_covers(rects, const Offset(0, 0)), isTrue);
      expect(_covers(rects, const Offset(100, 0)), isTrue);
      expect(_covers(rects, const Offset(50, 40)), isFalse);
      expect(_covers(rects, const Offset(200, 0)), isFalse);
    });

    test('cover a point near a bezier curve and exclude far points', () {
      final geo = FlowEdgeStyle.bezier.geometry(
        const Offset(0, 0),
        PortSide.right,
        const Offset(200, 0),
        PortSide.left,
      );
      final rects = geo.hitTestRects(8);

      // The curve runs along y = 0; its midpoint is ~ (100, 0).
      expect(_covers(rects, const Offset(100, 0)), isTrue);
      expect(_covers(rects, const Offset(100, 80)), isFalse);
    });

    test('cover same-side bezier overshoot beyond the endpoint chord', () {
      final geo = FlowEdgeStyle.bezier.geometry(
        const Offset(0, 0),
        PortSide.right,
        const Offset(400, 0),
        PortSide.right,
      );
      final rects = geo.hitTestRects(9);

      // The default control points are (200, 0) and (600, 0). At t = 0.8,
      // the cubic is at x = 454.4, beyond the endpoint at x = 400.
      expect(_covers(rects, const Offset(454.4, 0)), isTrue);
    });
  });
}
