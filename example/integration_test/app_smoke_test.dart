import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:node_flow/node_flow.dart';
import 'package:node_flow_example/demo_node.dart';
import 'package:node_flow_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('all demo routes mount and return cleanly', (tester) async {
    await tester.pumpWidget(const NodeFlowExampleApp());

    for (final (route, nodeId) in <(String, String)>[
      ('static', 'input'),
      ('editing', 'alpha'),
      ('edges', 'condition'),
      ('connect', 'target'),
    ]) {
      await tester.tap(find.byKey(ValueKey<String>('route-$route')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));

      expect(find.byType(NodeFlow<DemoNode, Object?>), findsOneWidget);
      expect(find.byKey(ValueKey<String>('node-$nodeId')), findsOneWidget);
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.byKey(ValueKey<String>('route-$route')), findsOneWidget);
    }
  });
}
