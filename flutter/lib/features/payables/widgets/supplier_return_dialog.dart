import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/data/models/supplier_returns.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';

/// One quantity as the form collected it: the receipt LINE the goods came off,
/// and the amount in THAT line's package unit (a BAG line answers in bags).
///
/// A record rather than a class because it crosses the widget/viewmodel line in
/// both directions and the viewmodel can name the same shape without importing a
/// widget: the compiler still refuses a mismatch, and there is no third type to
/// drift from these two.
typedef SupplierReturnQty = ({int receiptLineId, double qty});

/// What one receipt can still give back — or the sentence to show when that
/// could not be read.
typedef SupplierReturnableLoad = ({
  List<SupplierReturnableLine> lines,
  String? error,
});

/// A return and the credit note it minted, or the server's refusal in its own
/// words (which is what the clerk has to act on).
typedef SupplierReturnOutcome = ({SupplierReturn? recorded, String? refusal});

/// The deliveries of one purchase order that have been processed into stock —
/// the only ones a return can draw from, because a receipt nobody processed
/// created no batches to take goods off.
typedef SupplierReceiptsLoad = ({
  List<GoodsReceiptRecord> receipts,
  String? error,
});

/// Everything the return flow needs from the viewmodel, in one object so a
/// dialog is wired by passing one thing rather than three callbacks.
class SupplierReturnFlow {
  const SupplierReturnFlow({
    required this.loadReceipts,
    required this.loadReturnable,
    required this.submit,
  });

  /// The order's processed deliveries.
  final Future<SupplierReceiptsLoad> Function() loadReceipts;

  /// What one receipt can still give back.
  final Future<SupplierReturnableLoad> Function(int receiptId) loadReturnable;

  /// Writes the return. Never throws for a refusal: the viewmodel turns the
  /// server's sentence into [SupplierReturnOutcome.refusal].
  final Future<SupplierReturnOutcome> Function(SupplierReturnRequest request)
  submit;
}

/// A return as the dialog collected it, before it becomes the wire body.
class SupplierReturnRequest {
  const SupplierReturnRequest({
    required this.receiptId,
    required this.reason,
    required this.lines,
  });

  final int receiptId;
  final String reason;

  /// Only the lines a clerk actually typed a quantity for.
  final List<SupplierReturnQty> lines;
}

/// Return goods from ONE purchase order delivery (Phase 8 F2, decision 20).
///
/// Four facts shape the form, and none of them is taste:
/// * the return is taken off a DELIVERY, never off "the variant": the server
///   allocates from that receipt's own batches, so the first choice is the
///   receipt, not the product;
/// * every quantity is in the receipt line's package unit, because that is the
///   unit the clerk counted when the truck was unloaded and the unit
///   `POST /supplier-returns/` accepts;
/// * a line with nothing left (sold down, or already returned) is not offered —
///   asking for a zero the server refuses only teaches the clerk to guess;
/// * a refusal arrives as the server's own sentence and the form STAYS OPEN
///   with every typed value, because a return that is retyped from scratch is
///   how the same goods get returned twice.
///
/// The answer is shown, not swallowed: the credit note's number, what the
/// source bill absorbed and what is left on the supplier's account.
class SupplierReturnDialog extends StatefulWidget {
  const SupplierReturnDialog({
    super.key,
    required this.receipts,
    required this.purchaseOrderId,
    required this.supplierName,
    required this.flow,
  });

  /// The order's processed deliveries, newest first — at least one.
  final List<GoodsReceiptRecord> receipts;
  final int purchaseOrderId;
  final String supplierName;
  final SupplierReturnFlow flow;

  @override
  State<SupplierReturnDialog> createState() => _SupplierReturnDialogState();
}

class _SupplierReturnDialogState extends State<SupplierReturnDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final Map<int, TextEditingController> _qty = {};

  late int _receiptId = widget.receipts.first.id;
  List<SupplierReturnableLine>? _lines;
  String? _linesError;
  bool _loadingLines = false;
  bool _submitting = false;
  String? _refusal;
  SupplierReturn? _recorded;

  @override
  void initState() {
    super.initState();
    _loadLines(_receiptId);
  }

  @override
  void dispose() {
    _reason.dispose();
    _disposeQty();
    super.dispose();
  }

  void _disposeQty() {
    for (final controller in _qty.values) {
      controller.dispose();
    }
    _qty.clear();
  }

  Future<void> _loadLines(int receiptId) async {
    // The old receipt's fields go with the old receipt: a line from delivery A
    // submitted under delivery B's id would take the wrong stock.
    _disposeQty();
    setState(() {
      _loadingLines = true;
      _lines = null;
      _linesError = null;
      _refusal = null;
    });
    final loaded = await widget.flow.loadReturnable(receiptId);
    // A clerk who picked another delivery while this was in flight gets that
    // one: a late answer must not overwrite the newer choice.
    if (!mounted || _receiptId != receiptId) return;
    for (final line in loaded.lines) {
      if (line.canReturn) _qty[line.receiptLineId] = TextEditingController();
    }
    setState(() {
      _loadingLines = false;
      _lines = loaded.lines;
      _linesError = loaded.error;
    });
  }

  double _qtyOf(SupplierReturnableLine line) =>
      double.tryParse(_qty[line.receiptLineId]?.text.trim() ?? '') ?? 0;

  Future<void> _submit() async {
    // Guarded twice: the button is disabled while a request runs, and this
    // early return covers a tap that started before the rebuild landed.
    if (_submitting) return;
    final lines = _lines;
    if (lines == null) return;

    setState(() => _refusal = null);
    if (!_formKey.currentState!.validate()) return;

    final wanted = <SupplierReturnQty>[
      for (final line in lines)
        if (_qtyOf(line) > 0)
          (receiptLineId: line.receiptLineId, qty: _qtyOf(line)),
    ];
    if (wanted.isEmpty) {
      setState(() => _refusal = 'Enter a quantity for at least one line.');
      return;
    }

    setState(() => _submitting = true);
    final outcome = await widget.flow.submit(
      SupplierReturnRequest(
        receiptId: _receiptId,
        reason: _reason.text.trim(),
        lines: wanted,
      ),
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _recorded = outcome.recorded;
      _refusal = outcome.recorded == null
          ? (outcome.refusal ?? 'The return was refused.')
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final recorded = _recorded;
    // A control that could only produce a refusal is not rendered: with nothing
    // returnable on the picked delivery (or while it is still loading, or when
    // it could not be read) there is no return to submit.
    final canSubmit = _lines?.any((line) => line.canReturn) ?? false;
    return AppDialog(
      icon: Icons.assignment_return_outlined,
      title: 'Return to supplier',
      subtitle: 'PO-${widget.purchaseOrderId} · ${widget.supplierName}',
      width: 720,
      content: recorded == null
          ? Form(key: _formKey, child: _form())
          : _result(recorded),
      actions: recorded != null
          ? [
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Close'),
              ),
            ]
          : [
              TextButton(
                onPressed: _submitting ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              if (canSubmit)
                FilledButton(
                  key: const ValueKey('return-submit'),
                  onPressed: _submitting ? null : _submit,
                  child: const Text('Record return'),
                ),
            ],
    );
  }

  Widget _form() {
    final lines = _lines;
    final returnable = [
      for (final line in lines ?? const <SupplierReturnableLine>[])
        if (line.canReturn) line,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const DialogSectionLabel('Delivery'),
        DropdownButtonFormField<int>(
          key: const ValueKey('return-receipt'),
          isExpanded: true,
          initialValue: _receiptId,
          decoration: const InputDecoration(labelText: 'Receipt'),
          items: [
            for (final receipt in widget.receipts)
              DropdownMenuItem(
                value: receipt.id,
                child: Text(
                  _receiptLabel(receipt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value == null || value == _receiptId) return;
            setState(() => _receiptId = value);
            _loadLines(value);
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        if (_loadingLines)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_linesError case final error?) ...[
          ErrorBanner(message: error, onRetry: () => _loadLines(_receiptId)),
        ] else if (lines != null && returnable.isEmpty)
          const InfoBanner(message: 'Nothing on this delivery can go back.')
        else ...[
          DialogSectionLabel(
            'Lines',
            trailing: Text(
              'Quantities in the delivery\'s own unit',
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          for (final line in returnable) _lineRow(line),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const ValueKey('return-reason'),
            controller: _reason,
            decoration: const InputDecoration(
              labelText: 'Reason',
              helperText: 'Why the goods are going back.',
            ),
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'Say why the goods are going back.'
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          const InfoBanner(
            message:
                'The stock leaves this delivery and the shop gets a numbered '
                'credit note. Anything the bill cannot absorb stays as credit.',
          ),
        ],
        if (_refusal case final refusal?) ...[
          const SizedBox(height: AppSpacing.lg),
          ErrorBanner(message: refusal),
        ],
      ],
    );
  }

  Widget _lineRow(SupplierReturnableLine line) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.variantName, style: AppTextStyles.labelLarge),
                const SizedBox(height: 2),
                Text(
                  'Returnable ${formatQuantity(line.returnable)} ${line.unit} '
                  'of ${formatQuantity(line.delivered)} delivered',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 136,
            child: TextFormField(
              key: ValueKey('return-qty-${line.receiptLineId}'),
              controller: _qty[line.receiptLineId],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Qty',
                suffixText: line.unit,
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                // Blank means "this line stays": only typed lines go back.
                if (text.isEmpty) return null;
                final parsed = double.tryParse(text);
                if (parsed == null) return 'Enter a number.';
                if (parsed < 0) return 'Enter zero or more.';
                if (parsed > line.returnable) {
                  return 'Only ${formatQuantity(line.returnable)} '
                      '${line.unit} can go back on this line.';
                }
                return null;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _result(SupplierReturn recorded) {
    final total = recorded.creditNoteTotal ?? 0;
    final remaining = recorded.creditNoteRemaining ?? 0;
    final applied = total - remaining;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const DialogSectionLabel('Credit note'),
        DetailRow(
          label: 'Number',
          value: recorded.creditNoteNumber ?? 'Not issued',
        ),
        DetailRow(label: 'Credited', value: formatPeso(total)),
        DetailRow(
          label: 'Applied to bill',
          value: _appliedLabel(recorded, applied),
        ),
        DetailRow(label: 'Left as credit', value: formatPeso(remaining)),
        const SizedBox(height: AppSpacing.xl),
        const InfoBanner(
          message:
              'The goods have left this delivery. Credit the bill could not '
              'absorb stays on the supplier\'s account until you apply it.',
        ),
      ],
    );
  }

  /// What the source bill took: a bill that was already settled takes nothing,
  /// and a receipt with no bill (or a zero-value one) leaves the whole note as
  /// supplier credit. Both are normal, so both are said in words.
  static String _appliedLabel(SupplierReturn recorded, double applied) {
    final billId = recorded.billId;
    if (billId == null) return 'No bill for this delivery';
    if (applied <= 0) return 'Bill #$billId · nothing left to settle';
    return 'Bill #$billId · ${formatPeso(applied)}';
  }

  /// `DR-1001 · Nov 12, 2026 · 2 lines` — the delivery as the clerk's own
  /// paper calls it. A receipt with no delivery number is named by its id
  /// rather than by an empty label.
  static String _receiptLabel(GoodsReceiptRecord receipt) {
    final number = receipt.deliveryReceiptNo.trim();
    final date = receipt.receiveDate;
    final lines = receipt.lines.length;
    return [
      number.isEmpty ? 'Receipt #${receipt.id}' : number,
      if (date != null) formatDate(date),
      '$lines ${lines == 1 ? 'line' : 'lines'}',
    ].join(' · ');
  }
}
