import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/supplier_payables.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

/// One bill, read-only, with the payment history the ledger keeps.
///
/// Every figure here is the SERVER's snapshot (B2): the VAT rate and the terms
/// were the ones in force when the goods arrived, so nothing is recomputed.
///
/// [canPay] is the role gate, not a state: a Stock Manager may read a bill and
/// may not pay it (the server refuses the POST for that role). A bill that is
/// already settled offers no Pay either, because `BILL_PAID` is the only answer
/// it could give.
class SupplierBillDetailsDialog extends StatelessWidget {
  const SupplierBillDetailsDialog({
    super.key,
    required this.bill,
    this.canPay = false,
  });

  final SupplierBill bill;
  final bool canPay;

  String get _terms =>
      bill.termsDays == 0 ? 'Due on receipt' : '${bill.termsDays} days';

  String get _vatLabel =>
      bill.vatRate == 0 ? 'VAT' : 'VAT (${_percent(bill.vatRate)}%)';

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.receipt_long_outlined,
      title: 'Bill #${bill.id}',
      subtitle: bill.supplierName.isEmpty ? 'Supplier bill' : bill.supplierName,
      headerTrailing: _BillStatusBadge(bill: bill),
      width: 720,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const DialogSectionLabel('The bill'),
          DetailRow(
            label: 'Goods received',
            value: formatDate(bill.receivedDate),
          ),
          DetailRow(label: 'Terms', value: _terms),
          DetailRow(
            label: 'Due',
            value: formatDate(bill.dueDate),
            valueColor: bill.isOverdue ? AppColors.errorText : null,
          ),
          DetailRow(
            label: 'Purchase order',
            value: bill.purchaseOrderId == null
                ? 'No order on file'
                : 'PO-${bill.purchaseOrderId}',
          ),
          const SizedBox(height: AppSpacing.xl),
          const DialogSectionLabel('Money'),
          DetailRow(label: 'Gross', value: formatPeso(bill.grossAmount)),
          DetailRow(label: 'Discount', value: formatPeso(bill.discountAmount)),
          DetailRow(label: 'Net', value: formatPeso(bill.netAmount)),
          DetailRow(label: 'VATable', value: formatPeso(bill.vatableAmount)),
          // A zero rate means the shop is not VAT registered: say so instead of
          // printing a bare ₱0.00 that reads as a mistake.
          DetailRow(
            label: _vatLabel,
            value: bill.vatRate == 0
                ? 'Not VAT registered'
                : formatPeso(bill.vatAmount),
          ),
          DetailRow(label: 'Total', value: formatPeso(bill.totalAmount)),
          DetailRow(label: 'Paid', value: formatPeso(bill.paidAmount)),
          DetailRow(
            label: 'Balance',
            value: formatPeso(bill.balanceAmount),
            valueColor: AppColors.errorText,
          ),
          const SizedBox(height: AppSpacing.xl),
          DialogSectionLabel(
            'Payment history',
            trailing: Text(
              bill.payments.length == 1
                  ? '1 payment'
                  : '${formatCount(bill.payments.length)} payments',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          if (bill.payments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'No payment yet. The balance above is what the shop still owes.',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            for (final payment in bill.payments) _payment(payment),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (canPay && bill.canPay)
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Record payment'),
          ),
      ],
    );
  }

  Widget _payment(SupplierPayment payment) {
    final facts = [
      payment.methodLabel,
      if (payment.reference.isNotEmpty) 'Ref ${payment.reference}',
      if (payment.chequeNumber != null) 'Cheque ${payment.chequeNumber}',
      if (payment.chequeBank != null) payment.chequeBank!,
      if (payment.chequeDate != null) formatDate(payment.chequeDate!),
      if (payment.paidByName.isNotEmpty) 'By ${payment.paidByName}',
      if (payment.paidOn != null) formatDate(payment.paidOn!),
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.surfaceMuted)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              facts,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            formatPeso(payment.amount),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  static String _percent(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}

/// The bill's own status as a pill: overdue first, because a late bill is the
/// one that needs acting on whatever its payment state says.
class _BillStatusBadge extends StatelessWidget {
  const _BillStatusBadge({required this.bill});

  final SupplierBill bill;

  @override
  Widget build(BuildContext context) {
    if (bill.isOverdue) {
      return const StatusBadge(label: 'Overdue', tone: StatusTone.error);
    }
    return switch (bill.status) {
      SupplierBillStatus.paid => const StatusBadge(
        label: 'Paid',
        tone: StatusTone.success,
      ),
      SupplierBillStatus.partial => const StatusBadge(
        label: 'Partially paid',
        tone: StatusTone.warning,
      ),
      SupplierBillStatus.unpaid => const StatusBadge(
        label: 'Unpaid',
        tone: StatusTone.neutral,
      ),
    };
  }
}
