import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:client/data/models/supplier_payables.dart';
import 'package:client/data/models/supplier_returns.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

/// One payment as the dialog collected it, before the viewmodel turns it into
/// the wire body (a 2 dp money string and an ISO date).
class SupplierPaymentRequest {
  const SupplierPaymentRequest({
    required this.amount,
    required this.method,
    this.reference = '',
    this.chequeNumber,
    this.chequeBank,
    this.chequeDate,
    this.creditNoteId,
  });

  final double amount;
  final SupplierPaymentMethod method;
  final String reference;
  final String? chequeNumber;
  final String? chequeBank;
  final DateTime? chequeDate;

  /// The note a `CREDIT` payment spends; null for every other method.
  final int? creditNoteId;
}

/// Record a payment against one bill (Phase 5 F2, decision 18).
///
/// Three behaviours are wire contracts, not taste:
/// * a partial payment is normal — [SupplierBill.canPay] decides whether the
///   bill is offered at all, and the AMOUNT is whatever the clerk typed;
/// * a cheque needs its number, bank and date, because the server refuses it
///   otherwise (`INVALID_SUPPLIER_PAYMENT`) and there is no later clear step to
///   fill them in;
/// * the two server refusals (`OVERPAYMENT`, `BILL_PAID`) arrive as a sentence
///   naming the bill and the balance, so the dialog keeps the form open and
///   shows that sentence instead of closing on a failure.
///
/// [onSubmit] returns `null` when the payment was recorded, or the sentence to
/// show. It is awaited, so the button is disabled for exactly as long as the
/// request runs and a second tap cannot post twice.
class SupplierPayDialog extends StatefulWidget {
  const SupplierPayDialog({
    super.key,
    required this.bill,
    required this.onSubmit,
    this.creditNotes = const [],
  });

  final SupplierBill bill;
  final Future<String?> Function(SupplierPaymentRequest request) onSubmit;

  /// This supplier's OPEN credit notes — what an "Apply credit" click may spend.
  /// Empty means the shop holds no credit with this supplier, and the choice is
  /// not offered at all rather than offered and refused.
  final List<SupplierCreditNote> creditNotes;

  @override
  State<SupplierPayDialog> createState() => _SupplierPayDialogState();
}

class _SupplierPayDialogState extends State<SupplierPayDialog> {
  final _formKey = GlobalKey<FormState>();

  late final _amount = TextEditingController(
    // Plain and parseable: no peso sign, no grouping. A clerk edits this number.
    text: widget.bill.balanceAmount.toStringAsFixed(2),
  );
  final _reference = TextEditingController();
  final _chequeNumber = TextEditingController();
  final _chequeBank = TextEditingController();
  final _chequeDateText = TextEditingController();

  SupplierPaymentMethod _method = SupplierPaymentMethod.cash;
  DateTime? _chequeDate;
  String? _refusal;
  bool _submitting = false;

  /// Applying a credit note instead of paying money: the two are exclusive, so
  /// one flag decides which half of the form is shown.
  bool _applyCredit = false;
  SupplierCreditNote? _note;

  /// The notes that still have money on them. A spent note cannot settle
  /// anything, so it is never offered.
  List<SupplierCreditNote> get _openNotes => [
    for (final note in widget.creditNotes)
      if (note.isOpen) note,
  ];

  /// The most this bill can take from [_note]: the note's own remainder and the
  /// bill's balance, whichever runs out first. The SERVER enforces the same cap
  /// (`CREDIT_EXCEEDS_REMAINING` / `OVERPAYMENT`); this only saves a round trip.
  double get _creditCap {
    final note = _note;
    if (note == null) return widget.bill.balanceAmount;
    return note.remainingAmount < widget.bill.balanceAmount
        ? note.remainingAmount
        : widget.bill.balanceAmount;
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _chequeNumber.dispose();
    _chequeBank.dispose();
    _chequeDateText.dispose();
    super.dispose();
  }

  Future<void> _pickChequeDate() async {
    final now = appClock.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _chequeDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: now.add(const Duration(days: 365)),
      currentDate: now,
    );
    if (picked == null) return;
    setState(() {
      _chequeDate = picked;
      _chequeDateText.text = formatDate(picked);
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    final applying = _applyCredit && _note != null;
    setState(() {
      _submitting = true;
      _refusal = null;
    });
    final error = await widget.onSubmit(
      SupplierPaymentRequest(
        amount: double.parse(_amount.text.trim()),
        // A credit is a settlement, not a tender: it never carries a reference
        // or a cheque's three facts.
        method: applying ? SupplierPaymentMethod.credit : _method,
        reference: applying ? '' : _reference.text.trim(),
        chequeNumber: !applying && _method.needsChequeDetails
            ? _chequeNumber.text.trim()
            : null,
        chequeBank: !applying && _method.needsChequeDetails
            ? _chequeBank.text.trim()
            : null,
        chequeDate: !applying && _method.needsChequeDetails
            ? _chequeDate
            : null,
        creditNoteId: applying ? _note!.id : null,
      ),
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _submitting = false;
      _refusal = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    return AppDialog(
      icon: Icons.payments_outlined,
      title: 'Record payment',
      subtitle: 'Bill #${bill.id} · ${bill.supplierName}',
      headerTrailing: StatusBadge(
        label: bill.status.label,
        tone: _statusTone(bill),
      ),
      width: 560,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const DialogSectionLabel('This bill'),
            DetailRow(label: 'Due', value: formatDate(bill.dueDate)),
            DetailRow(label: 'Bill total', value: formatPeso(bill.totalAmount)),
            DetailRow(
              label: 'Left to pay',
              value: formatPeso(bill.balanceAmount),
              valueColor: AppDialogColors.balance,
            ),
            const SizedBox(height: AppSpacing.xl),
            const DialogSectionLabel('Payment'),
            TextFormField(
              key: const ValueKey('pay-amount'),
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '₱ ',
                helperText: _applyCredit
                    ? 'Capped at what the note and the bill allow.'
                    : 'A partial payment is allowed.',
              ),
              validator: (value) {
                final parsed = double.tryParse(value?.trim() ?? '');
                if (parsed == null) return 'Enter an amount.';
                if (parsed <= 0) return 'Above zero.';
                // The server refuses this too; saying it here saves the clerk a
                // round trip and names the note's own limit.
                if (_applyCredit &&
                    _note != null &&
                    parsed > _creditCap + 0.005) {
                  return '${_note!.number} has ${formatPeso(_creditCap)} left.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            // Only offered when there is credit to spend: a choice that can only
            // answer "nothing available" is a dead end, not an option.
            if (_openNotes.isNotEmpty)
              SwitchListTile(
                key: const ValueKey('pay-apply-credit'),
                value: _applyCredit,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Apply supplier credit'),
                subtitle: Text(
                  _openNotes.length == 1
                      ? '1 credit note can settle this bill'
                      : '${_openNotes.length} credit notes can settle this '
                            'bill',
                ),
                onChanged: (value) => setState(() {
                  _applyCredit = value;
                  _note = null;
                  _refusal = null;
                }),
              ),
            if (_applyCredit) ...[
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<SupplierCreditNote>(
                key: const ValueKey('pay-credit-note'),
                isExpanded: true,
                initialValue: _note,
                decoration: const InputDecoration(labelText: 'Credit note'),
                items: [
                  for (final note in _openNotes)
                    DropdownMenuItem(
                      value: note,
                      child: Text(
                        '${note.number} · ${formatPeso(note.remainingAmount)} '
                        'left',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (note) => setState(() {
                  _note = note;
                  // The cap is the whole point: prefill what this bill can take.
                  if (note != null) {
                    _amount.text = _creditCap.toStringAsFixed(2);
                  }
                }),
                validator: (note) =>
                    note == null ? 'Pick the credit note to apply.' : null,
              ),
            ] else ...[
              DropdownButtonFormField<SupplierPaymentMethod>(
                key: const ValueKey('pay-method'),
                isExpanded: true,
                initialValue: _method,
                decoration: const InputDecoration(labelText: 'Method'),
                // An explicit list, not `values`: a CREDIT payment spends a
                // credit note through its own flow, never the till (Phase 8).
                items: [
                  for (final method in SupplierPaymentMethod.selectable)
                    DropdownMenuItem(value: method, child: Text(method.label)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _method = value);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const ValueKey('pay-reference'),
                controller: _reference,
                decoration: const InputDecoration(
                  labelText: 'Reference (optional)',
                  helperText: 'Voucher, bank reference or note.',
                ),
              ),
              if (_method.needsChequeDetails) ...[
                const SizedBox(height: AppSpacing.lg),
                const DialogSectionLabel('Cheque'),
                TextFormField(
                  key: const ValueKey('pay-cheque-number'),
                  controller: _chequeNumber,
                  decoration: const InputDecoration(labelText: 'Cheque number'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'A cheque needs its number.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const ValueKey('pay-cheque-bank'),
                  controller: _chequeBank,
                  decoration: const InputDecoration(labelText: 'Bank'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'A cheque needs its bank.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const ValueKey('pay-cheque-date'),
                  controller: _chequeDateText,
                  readOnly: true,
                  onTap: _pickChequeDate,
                  decoration: const InputDecoration(
                    labelText: 'Cheque date',
                    suffixIcon: Icon(Icons.event_outlined),
                  ),
                  validator: (_) =>
                      _chequeDate == null ? 'A cheque needs its date.' : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                const InfoBanner(
                  message:
                      'A supplier cheque is issued to the supplier now. A '
                      'manager clears or bounces it once the bank answers.',
                ),
              ],
            ],
            if (_refusal case final refusal?) ...[
              const SizedBox(height: AppSpacing.lg),
              ErrorBanner(message: refusal),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: const Text('Record payment'),
        ),
      ],
    );
  }

  static StatusTone _statusTone(SupplierBill bill) {
    if (bill.isOverdue) return StatusTone.error;
    return switch (bill.status) {
      SupplierBillStatus.paid => StatusTone.success,
      SupplierBillStatus.partial => StatusTone.warning,
      SupplierBillStatus.unpaid => StatusTone.neutral,
    };
  }
}

/// One colour, named, so the "left to pay" figure is the same ink everywhere.
class AppDialogColors {
  const AppDialogColors._();

  static const Color balance = Color(0xFF8A2B2B);
}
