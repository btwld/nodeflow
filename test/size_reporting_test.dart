import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:node_flow/node_flow.dart';

void main() {
  testWidgets('measuredSize reflects an intrinsic-height child after layout', (
    tester,
  ) async {
    final c = FlowController<String, String>();
    addTearDown(c.dispose);
    // Seed with a deliberately wrong size; the child should override it.
    c.addNode(
      FlowNode<String>(
        id: 'a',
        type: 'card',
        data: 'a',
        position: const GraphPosition(Offset(0, 0)),
        size: const Size(1, 1),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: NodeFlow<String, String>(
              controller: c,
              fitViewOnLoad: false,
              minimap: false,
              // Fixed width, height determined by intrinsic content.
              nodeBuilder: (context, node) => const SizedBox(
                width: 256,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(height: 40),
                    SizedBox(height: 24),
                    SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Width is fixed at 256; height is the sum of the column children (80).
    expect(c.getNode('a')!.measuredSize.value, const Size(256, 80));
  });
}
