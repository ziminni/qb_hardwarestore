import 'package:client/data/models/supplier.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

/// A purchase order's status as the shared [StatusBadge]: always the words, with
/// the colour as the hint beside them.
///
/// Kept as the purchase module's own wrapper because the mapping from the five
/// server statuses to a tone belongs here, not in the shared widget.
class PurchasesStatusBadge extends StatelessWidget {
  const PurchasesStatusBadge({super.key, required this.status});

  final PurchaseStatus status;

  static StatusTone toneFor(PurchaseStatus status) => switch (status) {
    PurchaseStatus.draft => StatusTone.neutral,
    PurchaseStatus.ordered => StatusTone.info,
    PurchaseStatus.partial => StatusTone.warning,
    PurchaseStatus.complete => StatusTone.success,
    PurchaseStatus.cancelled => StatusTone.error,
  };

  @override
  Widget build(BuildContext context) =>
      StatusBadge(label: status.label, tone: toneFor(status));
}
