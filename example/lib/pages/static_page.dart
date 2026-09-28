import 'package:flutter/material.dart';
import 'package:node_flow/node_flow.dart';

import '../demo_node.dart';

/// A three-node graph with camera controls for pan, zoom, and fit.
class StaticPage extends StatefulWidget {
  const StaticPage({super.key});

  @override
  State<StaticPage> createState() => _StaticPageState();
}

class _StaticPageState extends State<StaticPage> {
  late final FlowController<DemoNode, Object?> _controller;

  @override
  void initState() {
    super.initState();
    _controller = FlowController<DemoNode, Object?>();
    _controller.addNode(
      FlowNode<DemoNode>(
        id: 'input',
        type: 'demo',
        data: const DemoNode('Input', Color(0xFF2D6CDF)),
        position: const GraphPosition(Offset(-360, -80)),
      ),
    );
    _controller.addNode(
      FlowNode<DemoNode>(
        id: 'transform',
        type: 'demo',
        data: const DemoNode('Transform', Color(0xFF8E44AD)),
        position: const GraphPosition(Offset(40, 120)),
      ),
    );
    _controller.addNode(
      FlowNode<DemoNode>(
        id: 'output',
        type: 'demo',
        data: const DemoNode('Output', Color(0xFF17A398)),
        position: const GraphPosition(Offset(420, -40)),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('01 · Static camera'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Zoom out',
            onPressed: _controller.zoomOut,
            icon: const Icon(Icons.zoom_out),
          ),
          IconButton(
            tooltip: 'Zoom in',
            onPressed: _controller.zoomIn,
            icon: const Icon(Icons.zoom_in),
          ),
          IconButton(
            tooltip: 'Fit to view',
            onPressed: () => _controller.fitView(padding: 0.2),
            icon: const Icon(Icons.fit_screen),
          ),
        ],
      ),
      body: NodeFlow<DemoNode, Object?>(
        controller: _controller,
        nodeBuilder: (context, node) =>
            DemoNodeCard(key: ValueKey<String>('node-${node.id}'), node: node),
      ),
    );
  }
}
