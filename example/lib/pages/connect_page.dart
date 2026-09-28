import 'package:flutter/material.dart';
import 'package:node_flow/node_flow.dart';

import '../demo_node.dart';

/// Phase 5 demo: drag from a port handle to another to create edges. The app
/// owns the model: [onConnect] validates the request (rejecting a second edge
/// into an already-connected input) and adds the edge itself. Identical
/// connections are deduped by the canvas and never reach the callback.
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  late final FlowController<DemoNode, Object?> _controller;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final ValueNotifier<FlowPortAnchor?> _hovered =
      ValueNotifier<FlowPortAnchor?>(null);

  int _edgeSeq = 0;

  @override
  void initState() {
    super.initState();
    _controller = FlowController<DemoNode, Object?>();

    _controller.addNode(
      FlowNode<DemoNode>(
        id: 'source-a',
        type: 'demo',
        data: const DemoNode('Source A', Color(0xFF2D6CDF)),
        position: const GraphPosition(Offset(-420, -160)),
        ports: const <FlowPort>[
          FlowPort(id: 'out', side: PortSide.right, kind: PortKind.output),
        ],
      ),
    );
    _controller.addNode(
      FlowNode<DemoNode>(
        id: 'source-b',
        type: 'demo',
        data: const DemoNode('Source B', Color(0xFF8E44AD)),
        position: const GraphPosition(Offset(-420, 80)),
        ports: const <FlowPort>[
          FlowPort(id: 'out', side: PortSide.right, kind: PortKind.output),
        ],
      ),
    );
    _controller.addNode(
      FlowNode<DemoNode>(
        id: 'target',
        type: 'demo',
        data: const DemoNode('Target (single input)', Color(0xFF17A398)),
        position: const GraphPosition(Offset(60, -40)),
        ports: const <FlowPort>[
          FlowPort(id: 'in', side: PortSide.left, kind: PortKind.input),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _hovered.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool _onConnect(FlowConnectionRequest request) {
    final inputTaken = _controller.edges.any(
      (e) =>
          e.targetNodeId == request.targetNodeId &&
          e.targetPortId == request.targetPortId,
    );
    if (inputTaken) {
      _messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            duration: Duration(milliseconds: 1400),
            content: Text('That input is already connected — rejected.'),
          ),
        );
      return false;
    }

    _controller.addEdge(
      FlowEdge<Object?>(
        id: 'edge-${_edgeSeq++}',
        sourceNodeId: request.sourceNodeId,
        sourcePortId: request.sourcePortId,
        targetNodeId: request.targetNodeId,
        targetPortId: request.targetPortId,
      ),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('04 · Connect'),
          actions: <Widget>[
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
              onConnect: _onConnect,
              onPortHover: (anchor) => _hovered.value = anchor,
              nodeBuilder: (context, node) => DemoNodeCard(
                key: ValueKey<String>('node-${node.id}'),
                node: node,
              ),
            ),
            _HoverLabel(hovered: _hovered),
            const Positioned(left: 12, bottom: 12, child: _HintCard()),
          ],
        ),
      ),
    );
  }
}

/// Renders a tiny label beside the hovered port, positioned from the anchor
/// screen rect the canvas reports.
class _HoverLabel extends StatelessWidget {
  const _HoverLabel({required this.hovered});

  final ValueNotifier<FlowPortAnchor?> hovered;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FlowPortAnchor?>(
      valueListenable: hovered,
      builder: (context, anchor, _) {
        if (anchor == null) return const SizedBox.shrink();
        final center = anchor.anchorScreenRect.center;
        return Positioned(
          left: center.dx + 12,
          top: center.dy - 12,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xF01B1B22),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0x333EB8C9)),
              ),
              child: Text(
                '${anchor.nodeId} · ${anchor.port.id} '
                '(${anchor.port.kind.name})',
                style: const TextStyle(color: Color(0xEEFFFFFF), fontSize: 11),
              ),
            ),
          ),
        );
      },
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
        'Drag from a right (output) handle to the left (input) handle to '
        'connect · the target accepts one input · dragging the same pair twice '
        'is deduped',
        style: TextStyle(color: Color(0xDDFFFFFF), fontSize: 12),
      ),
    );
  }
}
