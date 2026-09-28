import 'package:flutter/material.dart';
import 'package:node_flow/node_flow.dart';

import '../demo_node.dart';

/// Six editable nodes with selection, snapping, status updates, and navigation.
class EditingPage extends StatefulWidget {
  const EditingPage({super.key});

  @override
  State<EditingPage> createState() => _EditingPageState();
}

class _EditingPageState extends State<EditingPage> {
  late final FlowController<DemoNode, Object?> _controller;

  static const List<(String, Color, Offset)> _seed = <(String, Color, Offset)>[
    ('Alpha', Color(0xFF2D6CDF), Offset(-360, -160)),
    ('Bravo', Color(0xFF8E44AD), Offset(-40, -160)),
    ('Charlie', Color(0xFF17A398), Offset(280, -160)),
    ('Delta', Color(0xFFD9822B), Offset(-360, 120)),
    ('Echo', Color(0xFFC0392B), Offset(-40, 120)),
    ('Foxtrot', Color(0xFF2C7A5B), Offset(280, 120)),
  ];

  @override
  void initState() {
    super.initState();
    _controller = FlowController<DemoNode, Object?>();
    for (final (title, color, offset) in _seed) {
      _controller.addNode(
        FlowNode<DemoNode>(
          id: title.toLowerCase(),
          type: 'demo',
          data: DemoNode(title, color, status: DemoStatus.idle),
          position: GraphPosition(offset),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showNodeDetails(FlowNode<DemoNode> node) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(node.data.title),
        content: Text('Node ID: ${node.id}'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('02 · Editing'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Focus Alpha',
            onPressed: () => _controller.centerOnNode('alpha'),
            icon: const Icon(Icons.center_focus_strong),
          ),
          IconButton(
            tooltip: 'Toggle Alpha status',
            onPressed: () => _controller.updateNodeData(
              'alpha',
              (data) => DemoNode(
                data.title,
                data.color,
                status: data.status == DemoStatus.running
                    ? DemoStatus.idle
                    : DemoStatus.running,
              ),
            ),
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Select all',
            onPressed: _controller.selectAll,
            icon: const Icon(Icons.select_all),
          ),
          IconButton(
            tooltip: 'Delete selection',
            onPressed: _controller.deleteSelection,
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: 'Fit to view',
            onPressed: () => _controller.fitView(padding: 0.2),
            icon: const Icon(Icons.fit_screen),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          NodeFlow<DemoNode, Object?>(
            controller: _controller,
            onNodeDoubleTap: _showNodeDetails,
            onNodeContextMenu: (node, _) => _showNodeDetails(node),
            nodeBuilder: (context, node) => DemoNodeCard(
              key: ValueKey<String>('node-${node.id}'),
              node: node,
            ),
          ),
          const Positioned(left: 12, bottom: 12, child: _HintCard()),
        ],
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xCC1B1B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: const Text(
        'Drag a node (snaps on release) · click to select · shift-click to '
        'multi-select · double-click or right-click for details · shift-drag '
        'empty space to marquee',
        style: TextStyle(color: Color(0xDDFFFFFF), fontSize: 12),
      ),
    );
  }
}
