import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderCustomPaint;
import 'package:flutter_test/flutter_test.dart';
import 'package:node_flow/src/render/edges_painter.dart';
import 'package:node_flow/node_flow.dart';

FlowNode<String> node(
  String id,
  double x,
  double y, {
  Size size = const Size(120, 60),
  List<FlowPort> ports = const <FlowPort>[],
}) => FlowNode<String>(
  id: id,
  type: 'test',
  data: id,
  position: GraphPosition(Offset(x, y)),
  size: size,
  ports: ports,
);

FlowEdge<String> edge(
  String id,
  String from,
  String to, {
  bool dangling = false,
  Color? accent,
}) => FlowEdge<String>(
  id: id,
  sourceNodeId: from,
  sourcePortId: 'out',
  targetNodeId: to,
  targetPortId: 'in',
  dangling: dangling,
  accent: accent,
);

const _outPort = FlowPort(
  id: 'out',
  side: PortSide.right,
  kind: PortKind.output,
);
const _inPort = FlowPort(id: 'in', side: PortSide.left, kind: PortKind.input);

Future<void> pumpCanvas(
  WidgetTester tester,
  FlowController<String, String> controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 800,
            height: 600,
            child: NodeFlow<String, String>(
              controller: controller,
              fitViewOnLoad: false,
              animateEdges: false,
              minimap: false,
              nodeBuilder: (context, n) => SizedBox(
                key: ValueKey<String>('card-${n.id}'),
                width: n.measuredSize.value.width,
                height: n.measuredSize.value.height,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('edges layer renders for connected nodes without crashing', (
    tester,
  ) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);
    c.addNode(node('a', 100, 100, ports: const <FlowPort>[_outPort]));
    c.addNode(node('b', 400, 100, ports: const <FlowPort>[_inPort]));
    c.addEdge(edge('e', 'a', 'b'));

    await pumpCanvas(tester, c);

    expect(find.byType(EdgesLayer<String, String>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('branch handles with labels render without crashing', (
    tester,
  ) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);
    c.addNode(
      node(
        'a',
        100,
        100,
        ports: const <FlowPort>[
          FlowPort(id: 'in', side: PortSide.left, kind: PortKind.input),
          FlowPort(
            id: 't',
            side: PortSide.right,
            kind: PortKind.output,
            visual: PortVisual.branch,
            label: 'true',
            accent: Color(0xFF3FB950),
          ),
          FlowPort(
            id: 'f',
            side: PortSide.right,
            kind: PortKind.output,
            visual: PortVisual.branch,
            label: 'false',
            accent: Color(0xFFE5534B),
          ),
        ],
      ),
    );

    await pumpCanvas(tester, c);

    expect(tester.takeException(), isNull);
    expect(find.text('TRUE'), findsOneWidget);
    expect(find.text('FALSE'), findsOneWidget);
  });

  testWidgets('tapping near an edge selects it', (tester) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);
    c.addNode(node('a', 100, 100, ports: const <FlowPort>[_outPort]));
    c.addNode(node('b', 400, 100, ports: const <FlowPort>[_inPort]));
    c.addEdge(edge('e', 'a', 'b'));

    await pumpCanvas(tester, c);

    expect(c.getEdge('e')!.selected.value, isFalse);

    // Source anchor (220,130) -> target anchor (400,130); the wire runs along
    // y = 130. Tap its midpoint in empty space between the two nodes.
    final canvasTopLeft = tester.getTopLeft(
      find.byType(NodeFlow<String, String>),
    );
    await tester.tapAt(canvasTopLeft + const Offset(310, 130));
    await tester.pump();

    expect(c.getEdge('e')!.selected.value, isTrue);
  });

  testWidgets('tapping empty space away from any edge clears edge selection', (
    tester,
  ) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);
    c.addNode(node('a', 100, 100, ports: const <FlowPort>[_outPort]));
    c.addNode(node('b', 400, 100, ports: const <FlowPort>[_inPort]));
    c.addEdge(edge('e', 'a', 'b'));

    await pumpCanvas(tester, c);
    c.selectEdge('e');
    expect(c.getEdge('e')!.selected.value, isTrue);

    final canvasTopLeft = tester.getTopLeft(
      find.byType(NodeFlow<String, String>),
    );
    await tester.tapAt(canvasTopLeft + const Offset(310, 300));
    await tester.pump();

    expect(c.getEdge('e')!.selected.value, isFalse);
  });

  group('dangling badge painter', () {
    test('paints an amber badge at the path midpoint', () async {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final path = Path()
        ..moveTo(0, 50)
        ..lineTo(100, 50); // midpoint (50, 50)

      paintDanglingBadge(canvas, path, const Color(0xFFF5B544));

      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      final bytes = await image.toByteData();
      addTearDown(image.dispose);

      // A pixel on the badge fill (left of the central "!" ink) is amber.
      const x = 44;
      const y = 50;
      final i = (y * 100 + x) * 4;
      expect(bytes!.getUint8(i), greaterThan(200)); // R of #F5B544 == 0xF5
      expect(bytes.getUint8(i + 3), greaterThan(200)); // opaque
    });
  });

  group('EdgesPainter.shouldRepaint', () {
    test('repaints when the style changes, not when identical', () {
      final c = FlowController<String, String>();
      addTearDown(c.dispose);
      const dash = AlwaysStoppedAnimation<double>(0);
      final dragging = <String>{};

      EdgesPainter<String, String> make(FlowEdgeStyle style) =>
          EdgesPainter<String, String>(
            controller: c,
            theme: const FlowTheme.dark(),
            style: style,
            dash: dash,
            dragging: dragging,
            includeDragging: false,
            repaint: c.viewport,
          );

      final base = make(FlowEdgeStyle.bezier);
      expect(base.shouldRepaint(make(FlowEdgeStyle.bezier)), isFalse);
      expect(base.shouldRepaint(make(FlowEdgeStyle.smoothstep)), isTrue);
    });
  });

  group('edge accent', () {
    const theme = FlowTheme.dark();
    const accent = Color(0xFFFF00FF);

    group('resolveEdgeStroke', () {
      test('falls back to the theme when the edge is plain', () {
        final stroke = resolveEdgeStroke(edge('e', 'a', 'b'), theme);
        expect(stroke.color, theme.edge);
      });

      test('uses the accent, at the ordinary stroke width', () {
        final plain = resolveEdgeStroke(edge('e', 'a', 'b'), theme);
        final accented = resolveEdgeStroke(
          edge('e', 'a', 'b', accent: accent),
          theme,
        );

        expect(accented.color, accent);
        expect(accented.width, plain.width);
      });

      test('selection wins over the accent', () {
        final e = edge('e', 'a', 'b', accent: accent);
        e.selected.value = true;

        final stroke = resolveEdgeStroke(e, theme);

        expect(stroke.color, theme.edgeSelected);
        expect(
          stroke.width,
          greaterThan(resolveEdgeStroke(edge('p', 'a', 'b'), theme).width),
        );
      });
    });

    test('an accented edge is painted in its accent color', () async {
      final c = _wiredController(accent: accent);
      addTearDown(c.dispose);

      final pixels = await _paintEdges(c);

      expect(_hasColor(pixels, accent), isTrue);
      expect(_hasColor(pixels, theme.edgeSelected), isFalse);
    });

    test('a plain edge paints no accent color', () async {
      final c = _wiredController();
      addTearDown(c.dispose);

      expect(_hasColor(await _paintEdges(c), accent), isFalse);
    });

    test('a selected edge paints as selected even when accented', () async {
      final c = _wiredController(accent: accent);
      addTearDown(c.dispose);
      c.selectEdge('e');

      final pixels = await _paintEdges(c);

      expect(_hasColor(pixels, theme.edgeSelected), isTrue);
      expect(_hasColor(pixels, accent), isFalse);
    });

    test('the accent composes with the dashed style unchanged', () async {
      final c = _wiredController(accent: accent);
      addTearDown(c.dispose);

      // Two different dash phases: the wire moves, its color does not.
      for (final phase in <double>[0, 0.5]) {
        expect(
          _hasColor(await _paintEdges(c, phase: phase), accent),
          isTrue,
          reason: 'accent lost at dash phase $phase',
        );
      }
    });

    testWidgets('changing an accent repaints the edge layer', (tester) async {
      final c = _wiredController();
      addTearDown(c.dispose);
      await pumpCanvas(tester, c);

      final layer = tester.renderObject<RenderCustomPaint>(
        find
            .descendant(
              of: find.byType(EdgesLayer<String, String>),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      expect(
        layer.debugNeedsPaint,
        isFalse,
        reason: 'the layer should be settled before the accent changes',
      );

      c.setEdgeAccent('e', accent);

      expect(
        layer.debugNeedsPaint,
        isTrue,
        reason: 'the edge layer must repaint when an accent changes',
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}

/// A controller with two ported nodes and the edge `e` between them: the source
/// anchor lands at (220, 130) and the target at (400, 130), so the wire runs
/// along y = 130 whatever the edge style.
FlowController<String, String> _wiredController({Color? accent}) {
  final c = FlowController<String, String>();
  c.addNode(node('a', 100, 100, ports: const <FlowPort>[_outPort]));
  c.addNode(node('b', 400, 100, ports: const <FlowPort>[_inPort]));
  c.addEdge(edge('e', 'a', 'b', accent: accent));
  return c;
}

/// Rasterizes [c]'s edges through [EdgesPainter] and returns the raw RGBA.
Future<ByteData> _paintEdges(
  FlowController<String, String> c, {
  double phase = 0,
  FlowTheme theme = const FlowTheme.dark(),
  Size size = const Size(500, 260),
}) async {
  final recorder = PictureRecorder();
  EdgesPainter<String, String>(
    controller: c,
    theme: theme,
    style: FlowEdgeStyle.bezier,
    dash: AlwaysStoppedAnimation<double>(phase),
    dragging: const <String>{},
    includeDragging: false,
    repaint: c.viewport,
  ).paint(Canvas(recorder), size);

  final image = await recorder.endRecording().toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  final bytes = await image.toByteData();
  image.dispose();
  return bytes!;
}

/// Whether any fully opaque pixel in [pixels] is exactly [color]. Sampling the
/// whole surface rather than one point keeps the assertion independent of where
/// the dash pattern happens to fall.
bool _hasColor(ByteData pixels, Color color) {
  final want = color.toARGB32() & 0x00FFFFFF;
  for (var i = 0; i < pixels.lengthInBytes; i += 4) {
    if (pixels.getUint8(i + 3) < 250) continue;
    final rgb =
        (pixels.getUint8(i) << 16) |
        (pixels.getUint8(i + 1) << 8) |
        pixels.getUint8(i + 2);
    if (rgb == want) return true;
  }
  return false;
}
