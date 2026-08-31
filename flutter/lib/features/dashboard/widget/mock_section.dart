import 'package:flutter/material.dart';

class MockSection extends StatelessWidget {
  const MockSection({
    super.key,
    required this.title,
    required this.child,
    this.actionLabel,
  });

  final String title;
  final Widget child;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (actionLabel != null)
                TextButton(onPressed: () {}, child: Text(actionLabel!)),
            ],
          ),
          const Divider(),
          child,
        ],
      ),
    );
  }
}
