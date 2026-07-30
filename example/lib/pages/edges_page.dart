import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:node_flow/node_flow.dart';

import '../demo_node.dart';

/// Phase 3-4 demo: animated bezier edges, branch handles with TRUE/FALSE
/// labels, a dangling edge with its amber badge, click-to-select edges, and
/// per-edge accent colors driven from the toolbar.
class EdgesPage extends StatefulWidget {
  const EdgesPage({super.key});

  @override
  State<EdgesPage> createState() => _EdgesPageState();
}

class _EdgesPageState extends State<EdgesPage> {
  late final FlowController<DemoNode, Object?> _controller;

  static const _green = Color(0xFF3FB950);
  static const _red = Color(0xFFE5534B);
  static const _teal = Color(0xFF17A398);

  /// The wires from `input` through the TRUE branch — what an app would light
  /// up as a traversed path.
  static const _truePath = <String>['e-input-condition', 'e-true'];

  bool _pathLit = false;

  @override
  void initState() {
    super.initState();
    _controller = FlowController<DemoNode, Object?>()
      ..onEdgesDeleted = (ids) => debugPrint('Deleted edges: $ids');

    _controller.addNode(
      FlowNode<DemoNode>(
        id: 'input',
        type: 'demo',
        data: const DemoNode('Input', Color(0xFF2D6CDF)),
        position: const GraphPosition(Offset(-460, -40)),
        ports: const <FlowPort>[
          FlowPort(id: 'out', side: PortSide.right, kind: PortKind.output),
        ],
      ),
    );
    _controller.addNode(
      FlowNode<DemoNode>(
        id: 'condition',
        type: 'demo',
        data: const DemoNode('Condition', Color(0xFF8E44AD)),
        position: const GraphPosition(Offset(-80, -40)),
        ports: const <FlowPort>[
          FlowPort(id: 'in', side: PortSide.left, kind: PortKind.input),
          FlowPort(
            id: 'true',
            side: PortSide.right,
            kind: PortKind.output,
            visual: PortVisual.branch,
            label: 'true',
            accent: _green,
          ),
          FlowPort(
            id: 'false',
            side: PortSide.right,
            kind: PortKind.output,
            visual: PortVisual.branch,
            label: 'false',
            accent: _red,
          ),
        ],
      ),
    );
    _controller.addNode(
      FlowNode<DemoNode>(
        id: 'accept',
        type: 'demo',
        data: const DemoNode('Accept', Color(0xFF17A398)),
        position: const GraphPosition(Offset(340, -180)),
        ports: const <FlowPort>[
          FlowPort(id: 'in', side: PortSide.left, kind: PortKind.input),
        ],
      ),
    );
    _controller.addNode(
      FlowNode<DemoNode>(
        id: 'reject',
        type: 'demo',
        data: const DemoNode('Reject', Color(0xFFC0392B)),
        position: const GraphPosition(Offset(340, 120)),
        ports: const <FlowPort>[
          FlowPort(id: 'in', side: PortSide.left, kind: PortKind.input),
        ],
      ),
    );
    _controller.addNode(
      FlowNode<DemoNode>(
        id: 'sink',
        type: 'demo',
        data: const DemoNode('Detached sink', Color(0xFF444455)),
        position: const GraphPosition(Offset(-80, 220)),
        ports: const <FlowPort>[
          FlowPort(id: 'in', side: PortSide.left, kind: PortKind.input),
        ],
      ),
    );

    _controller.addEdge(
      FlowEdge<Object?>(
        id: 'e-input-condition',
        sourceNodeId: 'input',
        sourcePortId: 'out',
        targetNodeId: 'condition',
        targetPortId: 'in',
      ),
    );
    _controller.addEdge(
      FlowEdge<Object?>(
        id: 'e-true',
        sourceNodeId: 'condition',
        sourcePortId: 'true',
        targetNodeId: 'accept',
        targetPortId: 'in',
      ),
    );
    _controller.addEdge(
      FlowEdge<Object?>(
        id: 'e-false',
        sourceNodeId: 'condition',
        sourcePortId: 'false',
        targetNodeId: 'reject',
        targetPortId: 'in',
      ),
    );
    // A dangling edge: it resolves to real ports but is flagged unresolved, so
    // it shows the amber badge at its midpoint.
    _controller.addEdge(
      FlowEdge<Object?>(
        id: 'e-dangling',
        sourceNodeId: 'input',
        sourcePortId: 'out',
        targetNodeId: 'sink',
        targetPortId: 'in',
        dangling: true,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Accents are an app-owned highlight channel: they paint over the theme's
  /// edge color and leave click-to-select free for the user (select a lit wire
  /// and it still paints selected).
  void _togglePath() {
    setState(() => _pathLit = !_pathLit);
    if (_pathLit) {
      for (final id in _truePath) {
        _controller.setEdgeAccent(id, _teal);
      }
    } else {
      _controller.clearEdgeAccents();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('03 · Edges'),
        actions: <Widget>[
          IconButton(
            tooltip: _pathLit ? 'Clear edge accents' : 'Accent the TRUE path',
            onPressed: _togglePath,
            icon: Icon(_pathLit ? Icons.route : Icons.route_outlined),
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
          CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.delete):
                  _controller.deleteSelection,
              const SingleActivator(LogicalKeyboardKey.backspace):
                  _controller.deleteSelection,
            },
            child: Focus(
              autofocus: true,
              child: NodeFlow<DemoNode, Object?>(
                controller: _controller,
                minimap: true,
                nodeBuilder: (context, node) => DemoNodeCard(node: node),
              ),
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
        'Animated bezier edges · TRUE/FALSE branch handles · click a wire to '
        'select it, then Delete to remove it · the amber "!" marks a dangling '
        'edge · the route button accents the TRUE path (selection still wins) '
        '· the minimap (bottom-right) pans on click/drag',
        style: TextStyle(color: Color(0xDDFFFFFF), fontSize: 12),
      ),
    );
  }
}
