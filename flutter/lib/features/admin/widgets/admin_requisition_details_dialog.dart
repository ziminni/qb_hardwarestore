import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/features/admin/widgets/admin_requisition_token_panel.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

/// The whole of one requisition: the goods it asks for, what has already gone
/// out, and the release token once an approval has minted one.
///
/// The queue is a one-line table, so this is where the second half of each row
/// lives. It is read only: the only write on the queue is Approve or Reject,
/// which stay on the row so there is exactly one path to each.
Future<void> showAdminRequisitionDetails(
  BuildContext context, {
  required Requisition row,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: AppPanel(
          title: row.reqNumber,
          trailing: _statusBadge(row),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  row.projectName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  row.projectCustomerName,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Requested by ${row.requestedByName}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _lines(row),
                if (row.token != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AdminRequisitionTokenPanel(
                    token: row.token!,
                    // D17: a released token is spent. The panel stays so the
                    // token can be checked, and says it can no longer release.
                    used: row.status == RequisitionStatus.released,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// The shared pill, toned the same way as the queue's status column.
Widget _statusBadge(Requisition row) => StatusBadge(
  label:
      row.status == RequisitionStatus.unknown && row.rawStatus.trim().isNotEmpty
      ? row.rawStatus.trim()
      : row.status.label,
  tone: switch (row.status) {
    RequisitionStatus.submitted => StatusTone.warning,
    RequisitionStatus.approved => StatusTone.info,
    RequisitionStatus.released => StatusTone.success,
    RequisitionStatus.rejected => StatusTone.error,
    RequisitionStatus.draft || RequisitionStatus.unknown => StatusTone.neutral,
  },
);

/// The requested lines, with how much of each has been released.
///
/// A long requisition scrolls inside the dialog instead of pushing the token
/// and the Close button off the screen.
Widget _lines(Requisition row) {
  if (row.items.isEmpty) {
    return const Text(
      'No item lines on this requisition.',
      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
    );
  }
  return ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 260),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Expanded(child: _LineHead('Item')),
              SizedBox(width: 64, child: _LineHead('Asked', numeric: true)),
              SizedBox(width: 88, child: _LineHead('Released', numeric: true)),
            ],
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            height: 1,
            color: AppColors.border,
          ),
          for (final item in row.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.variantName,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: _LineValue(formatQuantity(item.quantity)),
                  ),
                  SizedBox(
                    width: 88,
                    child: _LineValue(
                      // D18: an untouched line says why it reads zero instead
                      // of showing a dash.
                      item.releasedQty == 0
                          ? 'None'
                          : formatQuantity(item.releasedQty),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _LineHead extends StatelessWidget {
  const _LineHead(this.label, {this.numeric = false});

  final String label;
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: numeric ? TextAlign.right : TextAlign.left,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _LineValue extends StatelessWidget {
  const _LineValue(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      textAlign: TextAlign.right,
      style: const TextStyle(
        fontSize: 14,
        color: AppColors.textPrimary,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}
