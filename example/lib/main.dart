import 'package:flutter/material.dart';

import 'pages/connect_page.dart';
import 'pages/edges_page.dart';
import 'pages/editing_page.dart';
import 'pages/static_page.dart';

void main() => runApp(const NodeFlowExampleApp());

class NodeFlowExampleApp extends StatelessWidget {
  const NodeFlowExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'node_flow examples',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(
        useMaterial3: true,
      ).copyWith(scaffoldBackgroundColor: const Color(0xFF101013)),
      home: const _HomePage(),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('node_flow')),
      body: ListView(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.center_focus_strong),
            title: const Text('01 · Static camera'),
            subtitle: const Text('Three nodes · pan / zoom / fit'),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const StaticPage())),
          ),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('02 · Editing'),
            subtitle: const Text('Drag · select · marquee · delete'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const EditingPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.timeline),
            title: const Text('03 · Edges'),
            subtitle: const Text('Animated bezier · branches · dangling badge'),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const EdgesPage())),
          ),
          ListTile(
            leading: const Icon(Icons.cable),
            title: const Text('04 · Connect'),
            subtitle: const Text('Drag-to-connect · validation · dedupe'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ConnectPage()),
            ),
          ),
        ],
      ),
    );
  }
}
