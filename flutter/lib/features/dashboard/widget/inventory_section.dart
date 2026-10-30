import 'package:client/shared/widgets/section_card.dart';
import 'package:flutter/material.dart';

class InventorySection extends StatelessWidget {
  const InventorySection({
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
    return SectionCard(
      title: title,
      actionLabel: actionLabel,
      onAction: onAction,
      child: child,
    );
  }
}
