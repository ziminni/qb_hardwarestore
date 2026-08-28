import 'package:flutter/material.dart';

class POSDashboard extends StatefulWidget {
  const POSDashboard({super.key});

  @override
  State<POSDashboard> createState() => _POSDashboardState();
}

class _POSDashboardState extends State<POSDashboard> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Row(children: [Text("POS Dashboard - Welcome")]));
  }
}
