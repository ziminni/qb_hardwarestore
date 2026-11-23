import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/supplier_payables.dart';
import 'package:client/data/models/supplier_returns.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:file_selector/file_selector.dart';
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
    this.creditNotes = const [],
    this.onAttachProof,
  });

  final SupplierBill bill;
  final bool canPay;

  /// The notes read for this screen, so a `CREDIT` row can name the note it
  /// spent. A row whose note is not here still reads, by its own id.
  final List<SupplierCreditNote> creditNotes;

  /// Optional callback to attach or update proof on an existing payment row.
  final Future<String?> Function(SupplierPayment payment, String proofAttachment)?
  onAttachProof;

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
            value: bill.dueDate == null
                ? 'No due date'
                : formatDate(bill.dueDate!),
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
            for (final payment in bill.payments) _payment(context, payment),
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

  Future<void> _promptAttachProof(
    BuildContext context,
    SupplierPayment payment,
  ) async {
    final handler = onAttachProof;
    if (handler == null) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _AttachPaymentProofDialog(payment: payment, onSave: handler),
    );
    if (saved == true && context.mounted) {
      Navigator.pop(context, false);
    }
  }

  Widget _payment(BuildContext context, SupplierPayment payment) {
    final facts = [
      payment.methodLabel,
      // A credit row's whole point: no money left the till, a note did.
      if (payment.creditNoteId case final noteId?)
        'Credit note ${_noteNumber(noteId)}',
      if (payment.reference.isNotEmpty) 'Ref ${payment.reference}',
      if (payment.chequeNumber != null) 'Cheque ${payment.chequeNumber}',
      if (payment.chequeBank != null) payment.chequeBank!,
      if (payment.chequeDate != null) formatDate(payment.chequeDate!),
      if (payment.decisionReason.isNotEmpty) 'Reason ${payment.decisionReason}',
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  facts,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // A payment carries its OWN status: a supplier cheque is issued
                    // until a manager decides it, whatever the bill says.
                    if (payment.statusLabel.isNotEmpty)
                      StatusBadge(
                        label: payment.statusLabel,
                        tone: _paymentTone(payment.status),
                      ),
                    if (payment.method != SupplierPaymentMethod.credit)
                      payment.hasProof
                          ? StatusBadge(
                              label: 'Proof: ${payment.proofAttachment}',
                              tone: StatusTone.success,
                            )
                          : const StatusBadge(
                              label: 'No proof attached',
                              tone: StatusTone.warning,
                            ),
                    if (canPay &&
                        onAttachProof != null &&
                        payment.method != SupplierPaymentMethod.credit)
                      TextButton.icon(
                        key: ValueKey('attach-proof-${payment.id}'),
                        onPressed: () => _promptAttachProof(context, payment),
                        icon: const Icon(Icons.attach_file, size: 15),
                        label: Text(
                          payment.hasProof ? 'Update proof' : 'Attach proof',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ],
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

  /// `CN-YYYYMMDD-NNNN` when the note was read with this screen, its id when it
  /// was not: a row must never print a blank where the money's source belongs.
  String _noteNumber(int noteId) {
    for (final note in creditNotes) {
      if (note.id == noteId) return note.number;
    }
    return '#$noteId';
  }

  static StatusTone _paymentTone(SupplierPaymentStatus? status) =>
      switch (status) {
        SupplierPaymentStatus.issued => StatusTone.warning,
        SupplierPaymentStatus.cleared => StatusTone.success,
        SupplierPaymentStatus.bounced => StatusTone.error,
        null => StatusTone.neutral,
      };

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

class _AttachPaymentProofDialog extends StatefulWidget {
  const _AttachPaymentProofDialog({
    required this.payment,
    required this.onSave,
  });

  final SupplierPayment payment;
  final Future<String?> Function(SupplierPayment payment, String proofAttachment)
  onSave;

  @override
  State<_AttachPaymentProofDialog> createState() =>
      _AttachPaymentProofDialogState();
}

class _AttachPaymentProofDialogState extends State<_AttachPaymentProofDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.payment.proofAttachment,
  );
  String? _errorText;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final payment = widget.payment;
    return AlertDialog(
      title: Text(
        payment.hasProof ? 'Update payment proof' : 'Attach payment proof',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: ValueKey('proof-input-${payment.id}'),
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Receipt / slip filename or reference',
                  hintText: 'e.g. deposit-slip-001.jpg or OR#12345',
                  errorText: _errorText,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: ValueKey('proof-pick-file-${payment.id}'),
                  onPressed: _saving
                      ? null
                      : () async {
                          const group = XTypeGroup(
                            label: 'Receipts & images',
                            extensions: <String>[
                              'jpg',
                              'jpeg',
                              'png',
                              'pdf',
                              'webp',
                            ],
                          );
                          final file = await openFile(
                            acceptedTypeGroups: <XTypeGroup>[group],
                          );
                          if (file != null && mounted) {
                            setState(() {
                              _controller.text = file.name;
                              _errorText = null;
                            });
                          }
                        },
                  icon: const Icon(Icons.attach_file, size: 18),
                  label: const Text('Choose file'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: ValueKey('proof-save-${payment.id}'),
          onPressed: _saving
              ? null
              : () async {
                  final text = _controller.text.trim();
                  if (text.isEmpty) {
                    setState(() {
                      _errorText = 'Enter a proof reference or choose a file.';
                    });
                    return;
                  }
                  setState(() {
                    _saving = true;
                    _errorText = null;
                  });
                  final err = await widget.onSave(payment, text);
                  if (!context.mounted) return;
                  if (err != null) {
                    setState(() {
                      _saving = false;
                      _errorText = err;
                    });
                    return;
                  }
                  Navigator.pop(context, true);
                },
          child: const Text('Save proof'),
        ),
      ],
    );
  }
}
