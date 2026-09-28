import 'package:flutter/material.dart';
import 'package:node_flow/node_flow.dart';

/// A deterministic host for browser rendering and controller-binding checks.
class LifecycleFixture extends StatefulWidget {
  const LifecycleFixture({super.key});

  @override
  State<LifecycleFixture> createState() => LifecycleFixtureState();
}

class FixtureNodeData {
  FixtureNodeData(this.label, {double width = 100, double height = 60})
    : size = ValueNotifier<Size>(Size(width, height));

  final String label;
  final ValueNotifier<Size> size;
}

class LifecycleFixtureState extends State<LifecycleFixture> {
  late final FlowController<FixtureNodeData, Object?> controllerA;
  late final FlowController<FixtureNodeData, Object?> controllerB;
  late FlowController<FixtureNodeData, Object?> activeController;
  final List<FixtureNodeData> _ownedData = <FixtureNodeData>[];

  FlowNode<FixtureNodeData> _node(
    String id,
    Offset position, {
    double width = 100,
    double height = 60,
  }) {
    final data = FixtureNodeData(id, width: width, height: height);
    _ownedData.add(data);
    return FlowNode<FixtureNodeData>(
      id: id,
      type: 'fixture',
      data: data,
      position: GraphPosition(position),
      size: Size(width, height),
      ports: switch (id) {
        'left' => const <FlowPort>[
          FlowPort(id: 'out', side: PortSide.right, kind: PortKind.output),
        ],
        'right' => const <FlowPort>[
          FlowPort(id: 'in', side: PortSide.left, kind: PortKind.input),
        ],
        _ => const <FlowPort>[],
      },
    );
  }

  void _addOuterNodes(FlowController<FixtureNodeData, Object?> controller) {
    controller
      ..addNode(_node('left', const Offset(0, 0)))
      ..addNode(_node('right', const Offset(600, 200)));
  }

  @override
  void initState() {
    super.initState();
    controllerA = FlowController<FixtureNodeData, Object?>();
    controllerB = FlowController<FixtureNodeData, Object?>();
    _addOuterNodes(controllerA);
    _addOuterNodes(controllerB);
    controllerA.addEdge(
      FlowEdge<Object?>(
        id: 'fixture-edge',
        sourceNodeId: 'left',
        sourcePortId: 'out',
        targetNodeId: 'right',
        targetPortId: 'in',
      ),
    );
    controllerB.addNode(_node('b-interior', const Offset(420, 110)));
    activeController = controllerA;
  }

  @override
  void dispose() {
    controllerA.dispose();
    controllerB.dispose();
    for (final data in _ownedData) {
      data.size.dispose();
    }
    super.dispose();
  }

  void addInterior() =>
      controllerA.addNode(_node('interior', const Offset(260, 90)));

  void moveInterior() {
    controllerA.getNode('interior')!.position.value = const GraphPosition(
      Offset(310, 90),
    );
  }

  void replaceInterior() =>
      controllerA.replaceNode(_node('interior', const Offset(350, 100)));

  void resizeInterior() {
    final data = controllerA.getNode('interior')!.data;
    data.size.value = const Size(160, 85);
  }

  void removeInterior() => controllerA.removeNode('interior');

  void mutateDetached() =>
      controllerA.addNode(_node('detached-change', const Offset(180, 100)));

  void accentEdge() =>
      controllerA.setEdgeAccent('fixture-edge', const Color(0xFFFFAC33));

  void moveEdgeTarget() {
    controllerA.getNode('right')!.position.value = const GraphPosition(
      Offset(600, 340),
    );
  }

  void deleteEdge() => controllerA.removeEdge('fixture-edge');

  void showController(FlowController<FixtureNodeData, Object?> controller) {
    setState(() => activeController = controller);
  }

  /// Rebuilds the standalone minimap after NodeFlow reports its viewport size.
  void refreshProjection() => setState(() {});

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: <Widget>[
          Wrap(
            children: <Widget>[
              TextButton(
                key: const ValueKey<String>('fixture-add'),
                onPressed: addInterior,
                child: const Text('Add interior'),
              ),
              TextButton(
                key: const ValueKey<String>('fixture-move'),
                onPressed: moveInterior,
                child: const Text('Move interior'),
              ),
              TextButton(
                key: const ValueKey<String>('fixture-replace'),
                onPressed: replaceInterior,
                child: const Text('Replace interior'),
              ),
              TextButton(
                key: const ValueKey<String>('fixture-resize'),
                onPressed: resizeInterior,
                child: const Text('Resize interior'),
              ),
              TextButton(
                key: const ValueKey<String>('fixture-remove'),
                onPressed: removeInterior,
                child: const Text('Remove interior'),
              ),
              TextButton(
                key: const ValueKey<String>('fixture-b'),
                onPressed: () => showController(controllerB),
                child: const Text('Controller B'),
              ),
              TextButton(
                key: const ValueKey<String>('fixture-a'),
                onPressed: () => showController(controllerA),
                child: const Text('Controller A'),
              ),
              TextButton(
                key: const ValueKey<String>('fixture-detached'),
                onPressed: mutateDetached,
                child: const Text('Mutate detached'),
              ),
              TextButton(
                key: const ValueKey<String>('fixture-accent-edge'),
                onPressed: accentEdge,
                child: const Text('Accent edge'),
              ),
              TextButton(
                key: const ValueKey<String>('fixture-move-edge-target'),
                onPressed: moveEdgeTarget,
                child: const Text('Move edge target'),
              ),
              TextButton(
                key: const ValueKey<String>('fixture-delete-edge'),
                onPressed: deleteEdge,
                child: const Text('Delete edge'),
              ),
            ],
          ),
          Expanded(
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: NodeFlow<FixtureNodeData, Object?>(
                    controller: activeController,
                    fitViewOnLoad: false,
                    animateEdges: false,
                    edgeStyle: FlowEdgeStyle.straight,
                    minimap: false,
                    theme: const FlowTheme.dark(),
                    nodeBuilder: (context, node) =>
                        ValueListenableBuilder<Size>(
                          valueListenable: node.data.size,
                          builder: (context, size, _) => Container(
                            key: ValueKey<String>('fixture-node-${node.id}'),
                            width: size.width,
                            height: size.height,
                            color: const Color(0xFF4C74B8),
                            alignment: Alignment.center,
                            child: Text(node.data.label),
                          ),
                        ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Minimap<FixtureNodeData, Object?>(
                    controller: activeController,
                    theme: const FlowTheme.dark(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
