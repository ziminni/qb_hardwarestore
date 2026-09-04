import 'package:flutter/material.dart';

class SalesSection extends StatelessWidget {
  const SalesSection({
    super.key,
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

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
                TextButton(
                  onPressed: onAction ?? () {},
                  child: Text(actionLabel!),
                ),
            ],
          ),
          const Divider(),
          child,
        ],
      ),
    );
  }
}
