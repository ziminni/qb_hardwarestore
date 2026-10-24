import 'package:flutter/material.dart';

/// A titled card whose header may carry one action.
///
/// `onAction` is passed straight through, so a header with a label but no
/// callback renders the button **disabled** rather than enabled and inert
/// (Phase 3 Task 0). If a label has nothing behind it, delete the label.
class AdminUserSection extends StatelessWidget {
  const AdminUserSection({
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
                  onPressed: onAction,
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
