import 'package:client/core/format/format.dart';
import 'package:client/core/format/money_input.dart';
import 'package:client/data/models/delivery.dart';
import 'package:client/data/models/sale_discount.dart';
import 'package:client/data/models/store_settings.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/data/services/discount_approval_service.dart';
import 'package:client/features/pos/widgets/pos_discount_approval_dialog.dart';
import 'package:flutter/material.dart';

/// One tender of a sale: how it was paid, how much of it this method took, and the
/// facts a cheque has to carry (Phase 4 B2, decision 18).
///
/// A sale takes a LIST of these. The wire code is [TenderMethod.code]; a label never
/// reaches the server (C1).
class PosTender {
  const PosTender({
    required this.method,
    required this.amount,
    this.reference = '',
    this.chequeNumber = '',
    this.bank = '',
    this.chequeDate,
  });

  final TenderMethod method;
  final double amount;

  /// Reference the cashier can read back (a GCash number, a card approval code).
  final String reference;

  /// The three facts a cheque must carry. A pending cheque is not money yet: the
  /// server stores it PENDING and the amount stays owed until a manager clears it.
  final String chequeNumber;
  final String bank;
  final DateTime? chequeDate;

  bool get isCheque => method.isCheque;

  /// Sends this row as one entry of `payments[]`.
  Map<String, dynamic> toJson() => {
    'method': method.code,
    'amount_tendered': amount.toStringAsFixed(2),
    'reference_no': reference,
    if (isCheque) ...{
      'cheque_number': chequeNumber,
      'bank': bank,
      'cheque_date': _wireDate(chequeDate),
    },
  };

  static String _wireDate(DateTime? date) {
    if (date == null) return '';
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }
}

/// What the payment dialog hands back: the tenders it took, the discount it
/// applied, the manager's approval token when the discount needed one, and the
/// delivery details when the sale goes out.
class PosPaymentDetails {
  const PosPaymentDetails({
    required this.tenders,
    this.discount,
    this.discountApprovalToken,
    this.delivery,
  });

  /// Every tender against this sale, in the order the cashier entered them. The
  /// page posts them all: collapsing a split sale into one method would tell the
  /// server money arrived in a drawer it never reached.
  final List<PosTender> tenders;

  /// The discount to send, or null when the cashier gave none.
  final PosDiscount? discount;

  /// The manager's one-time token, or null when the discount was within the cap.
  final String? discountApprovalToken;

  /// The delivery the cashier described, or null when the customer carries the
  /// goods out. Its fee is a charge AFTER the discount and is never discounted.
  final DeliveryDraft? delivery;

  /// The first tender, kept for the single-tender callers.
  PosTender get primary => tenders.first;

  /// The first tender's method, for a one-tender sale.
  TenderMethod get method => primary.method;

  /// What the drawer received: every tender EXCEPT a pending cheque.
  ///
  /// This is what the sale is actually paid by, so it is what an utang is measured
  /// from. Counting a cheque here would claim a debt was settled by a piece of paper.
  double get paidNow => tenders
      .where((tender) => !tender.isCheque)
      .fold(0.0, (sum, tender) => sum + tender.amount);

  /// Cheques waiting on the bank, shown apart from [paidNow].
  double get pendingChequeTotal => tenders
      .where((tender) => tender.isCheque)
      .fold(0.0, (sum, tender) => sum + tender.amount);

  /// Every tender as tendered, cheques included. The wire `amount_tendered` sum.
  double get amountPaid =>
      tenders.fold(0.0, (sum, tender) => sum + tender.amount);
}

class PosPaymentDialog extends StatefulWidget {
  const PosPaymentDialog({
    super.key,
    required this.total,
    this.discountCapPercent = StoreSettings.defaultDiscountCapPercent,
    this.approvalService,
    this.customerIsNamed = true,
    this.lockedDeliveryFee,
    this.allowDiscount = true,
  });

  /// The cart's gross: what the sale is worth before any discount.
  final double total;

  /// The Admin's cap, read from store settings. A percent above it needs a manager's
  /// approval before the sale can be submitted.
  final double discountCapPercent;

  /// Injected by tests; the approval dialog builds the real one.
  final DiscountApprovalService? approvalService;

  /// False for the seeded walk-in customer. A cheque is refused then, because the
  /// pending amount would be owed by nobody (server: `CHEQUE_NEEDS_CUSTOMER`).
  final bool customerIsNamed;

  /// The delivery fee an order's fulfilment must charge, or null for an ordinary
  /// till sale (Phase 7 F2, decision 19).
  ///
  /// Non-null means the sale is the order's: the fee was agreed on its slip and
  /// is charged once, so it is SHOWN and never edited, and the Deliver section is
  /// not offered - the trip is not re-booked at the counter (the server refuses a
  /// `delivery` object on every fulfilment).
  final double? lockedDeliveryFee;

  /// False when the sale takes no new discount (an order's fulfilment: the
  /// approval was spent when the order was saved). Hiding the fields is the
  /// honest thing: a discount typed here would never reach the server, and the
  /// till would take less money than the sale asks for.
  final bool allowDiscount;

  @override
  State<PosPaymentDialog> createState() => _PosPaymentDialogState();
}

/// One editable row of the tender list.
class _TenderRow {
  _TenderRow({required this.method, String amount = ''})
    : amountController = TextEditingController(text: amount);

  TenderMethod method;
  final TextEditingController amountController;
  final TextEditingController reference = TextEditingController();
  final TextEditingController chequeNumber = TextEditingController();
  final TextEditingController bank = TextEditingController();
  DateTime? chequeDate;

  /// True until the cashier types an amount: while it is, the field follows what is
  /// still owed, so a discount does not leave the row at a stale total.
  bool followsRemaining = true;

  double get amount => double.tryParse(amountController.text.trim()) ?? 0;
  bool get isCheque => method.isCheque;

  void dispose() {
    amountController.dispose();
    reference.dispose();
    chequeNumber.dispose();
    bank.dispose();
  }
}

class _PosPaymentDialogState extends State<PosPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _discountValue = TextEditingController();
  final _discountReason = TextEditingController();
  final _deliveryAddress = TextEditingController();
  final _deliveryContact = TextEditingController();
  final _deliveryPhone = TextEditingController();
  final _deliveryFee = TextEditingController(text: '0.00');
  final List<_TenderRow> _rows = [_TenderRow(method: TenderMethod.cash)];

  /// True once the cashier says the goods go out (decision 18).
  bool _deliver = false;

  /// The day the goods go out. Defaults to tomorrow: a delivery is arranged
  /// ahead of the sale that paid for it, and today's date would claim the truck
  /// is already loaded.
  DateTime? _deliveryDate;

  /// Rows the cashier removed. Their controllers are disposed with the dialog, not
  /// with the rebuild that is still tearing their widgets down.
  final List<_TenderRow> _removedRows = [];
  DiscountKind _kind = DiscountKind.amount;

  /// The token a manager granted for the discount currently entered, if any. Held
  /// for THIS checkout only: a changed discount invalidates it.
  String? _approvalToken;
  double _approvedPercent = 0;

  /// Refusals the dialog itself can catch before a round trip.
  String? _tenderError;

  @override
  void initState() {
    super.initState();
    // What the sale ASKS FOR, which is not always the goods total: an order's
    // fulfilment carries the delivery fee agreed on its slip.
    _rows.first.amountController.text = _due.toStringAsFixed(2);
  }

  @override
  void dispose() {
    for (final row in [..._rows, ..._removedRows]) {
      row.dispose();
    }
    _discountValue.dispose();
    _discountReason.dispose();
    _deliveryAddress.dispose();
    _deliveryContact.dispose();
    _deliveryPhone.dispose();
    _deliveryFee.dispose();
    super.dispose();
  }

  PosDiscount? get _discount {
    final value = double.tryParse(_discountValue.text.trim()) ?? 0;
    if (value <= 0) return null;
    return PosDiscount(
      kind: _kind,
      value: value,
      reason: _discountReason.text.trim(),
    );
  }

  PosDiscountAmounts get _amounts =>
      PosDiscountAmounts.forDiscount(widget.total, _discount);

  /// The delivery charge as typed, or 0 while the sale is not a delivery.
  double get _fee =>
      _deliver ? (double.tryParse(_deliveryFee.text.trim()) ?? 0) : 0;

  /// What this sale charges for the trip: the order's agreed fee when the sale is
  /// a fulfilment, otherwise whatever the cashier described here.
  double get _deliveryCharge => widget.lockedDeliveryFee ?? _fee;

  /// What the customer owes: the GOODS net plus the delivery charge.
  ///
  /// The fee is added AFTER the discount and is never discounted (ENDPOINTS.md,
  /// *Delivery charge*), so a percentage taken off the goods cannot eat the
  /// trip. The server computes the same figure; this preview only has to match
  /// it so the tender rows ask for the right money.
  double get _due => _amounts.net + _deliveryCharge;

  /// What stopped the pending cheque from being taken, or null.
  String? get _chequeRefusal {
    final cheques = _rows.where((row) => row.isCheque).toList();
    if (cheques.isEmpty) return null;
    if (!widget.customerIsNamed) {
      return chequeRefusalSentence('CHEQUE_NEEDS_CUSTOMER');
    }
    final missing = <String>[];
    for (final row in cheques) {
      if (row.chequeNumber.text.trim().isEmpty) missing.add('cheque number');
      if (row.bank.text.trim().isEmpty) missing.add('bank');
      if (row.chequeDate == null) missing.add('cheque date');
    }
    if (missing.isNotEmpty) {
      return chequeRefusalSentence(
        'CHEQUE_DETAILS_REQUIRED',
        missing: missing.toSet().toList(),
      );
    }
    final owedNow = _remainingBeforeCheques;
    final chequeTotal = _pendingChequeTotal;
    if (chequeTotal > owedNow + 0.005) {
      return chequeRefusalSentence(
        'CHEQUE_EXCEEDS_BALANCE',
        chequeTotal: chequeTotal,
        owed: owedNow,
      );
    }
    return null;
  }

  /// What the drawer has taken so far, EXCLUDING pending cheques.
  double get _paidNow => _rows
      .where((row) => !row.isCheque)
      .fold(0.0, (sum, row) => sum + row.amount);

  double get _pendingChequeTotal => _rows
      .where((row) => row.isCheque)
      .fold(0.0, (sum, row) => sum + row.amount);

  double get _cashTotal => _rows
      .where((row) => !row.isCheque && row.method == TenderMethod.cash)
      .fold(0.0, (sum, row) => sum + row.amount);

  /// What the sale still asks the drawer for, before any cheque is taken.
  double get _remainingBeforeCheques =>
      (_due - _paidNow).clamp(0, double.infinity);

  /// Change is paid from the DRAWER only: cash above what is owed, never from a
  /// cheque the shop has not cashed.
  double get _change {
    final nonCashPaid = _rows
        .where((row) => !row.isCheque && row.method != TenderMethod.cash)
        .fold(0.0, (sum, row) => sum + row.amount);
    return (_cashTotal - (_due - nonCashPaid)).clamp(0, double.infinity);
  }

  /// The server's own refusal, caught before submit (QA High, Phase 4 close).
  ///
  /// A non-cash tender above what is owed asks the drawer for change it never took.
  /// The server refuses it (`PAYMENT_EXCEEDS_TOTAL`); saying so here spares the
  /// cashier a round trip, and the server stays the authority.
  String? get _nonCashOverpay {
    if (_change <= _cashTotal + 0.005) return null;
    return 'Change of ${formatPeso(_change)} is due but only '
        '${formatPeso(_cashTotal)} was taken in cash. Change is paid from the '
        'drawer: lower the card or GCash amount and take the rest in cash.';
  }

  void _onDiscountChanged() {
    _approvalToken = null;
    _approvedPercent = 0;
    setState(() {
      _syncFollowingRows();
      _tenderError = null;
    });
  }

  /// Keeps a row that the cashier has not typed in showing what is still owed.
  void _syncFollowingRows() {
    for (final row in _rows) {
      if (!row.followsRemaining || row.isCheque) continue;
      row.amountController.text = _remainingFor(row).toStringAsFixed(2);
    }
  }

  /// What [row] should show: what is still owed with the OTHER rows taken first.
  double _remainingFor(_TenderRow row) {
    var others = 0.0;
    for (final other in _rows) {
      if (identical(other, row)) continue;
      others += other.amount;
    }
    return (_due - others).clamp(0, double.infinity);
  }

  void _setDeliver(bool value) {
    setState(() {
      _deliver = value;
      if (value && _deliveryDate == null) {
        final now = DateTime.now();
        _deliveryDate = DateTime(now.year, now.month, now.day + 1);
      }
      if (!value) _tenderError = null;
      // The fee changes what the sale asks for, so a row the cashier has not
      // typed in follows it - otherwise the till would take the goods total and
      // leave the trip unpaid.
      _syncFollowingRows();
    });
  }

  Future<void> _pickDeliveryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deliveryDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null || !mounted) return;
    setState(() => _deliveryDate = picked);
  }

  void _addRow() {
    final row = _TenderRow(
      method: TenderMethod.cash,
      amount: _remainingBeforeCheques.toStringAsFixed(2),
    );
    setState(() {
      _rows.add(row);
      _tenderError = null;
    });
  }

  void _removeRow(_TenderRow row) {
    if (_rows.length == 1) return;
    setState(() {
      _rows.remove(row);
      _removedRows.add(row);
      _tenderError = null;
      _syncFollowingRows();
    });
  }

  void _setMethod(_TenderRow row, TenderMethod method) {
    setState(() {
      row.method = method;
      _tenderError = null;
      if (!row.isCheque && row.amountController.text.trim().isEmpty) {
        row.amountController.text = _remainingFor(row).toStringAsFixed(2);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final amounts = _amounts;
    final needsApproval = amounts.needsApproval(widget.discountCapPercent);
    return AlertDialog(
      title: const Text('Payment'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _summaryRow('Gross', formatPeso(amounts.gross)),
                _summaryRow(
                  'Discount',
                  amounts.discountAmount > 0
                      ? formatPeso(-amounts.discountAmount)
                      : 'None',
                ),
                // After the discount and before the total: the fee is added
                // AFTER the discount and never discounted (decision 18).
                if (widget.lockedDeliveryFee != null
                    ? _deliveryCharge > 0
                    : _deliver)
                  _summaryRow('Delivery charge', formatPeso(_deliveryCharge)),
                Text(
                  'Amount due: ${formatPeso(_due)}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                // A fulfilment's trip is already agreed on the order.
                if (widget.lockedDeliveryFee == null) _deliverySection(),
                if (widget.allowDiscount) ...[
                  const SizedBox(height: 16),
                  const Text('Apply a discount'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final kind in DiscountKind.values) ...[
                        ChoiceChip(
                          label: Text(
                            kind == DiscountKind.amount
                                ? '₱ Amount'
                                : '% Percent',
                          ),
                          selected: _kind == kind,
                          onSelected: (_) {
                            if (_kind == kind) return;
                            setState(() => _kind = kind);
                            _onDiscountChanged();
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('pos-discount-value'),
                          controller: _discountValue,
                          onChanged: (_) => _onDiscountChanged(),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: _kind == DiscountKind.amount
                                ? 'Discount amount'
                                : 'Discount percent',
                          ),
                          validator: (value) {
                            final text = (value ?? '').trim();
                            if (text.isEmpty) return null;
                            final parsed = double.tryParse(text);
                            if (parsed == null) return 'Enter a valid number';
                            if (parsed < 0) {
                              return 'A discount cannot be negative';
                            }
                            if (_kind == DiscountKind.percent && parsed > 100) {
                              return 'A discount cannot be more than 100 percent';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          key: const ValueKey('pos-discount-reason'),
                          controller: _discountReason,
                          onChanged: (_) => _onDiscountChanged(),
                          decoration: const InputDecoration(
                            labelText: 'Reason for the discount',
                          ),
                          validator: (value) {
                            if ((_discountValue.text.trim().isNotEmpty) &&
                                (value ?? '').trim().isEmpty) {
                              return 'A discount needs a reason';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  if (needsApproval) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Needs manager approval: ${amounts.percentOfGross.toStringAsFixed(2)}% '
                      'is above the ${widget.discountCapPercent.toStringAsFixed(2)}% cap.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(child: Text('Tenders')),
                    TextButton.icon(
                      key: const ValueKey('pos-add-tender'),
                      onPressed: _addRow,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add tender'),
                    ),
                  ],
                ),
                for (final row in _rows) _tenderRow(row),
                const SizedBox(height: 8),
                // Paid now and the pending cheque are two different facts: money in
                // the drawer, and paper the bank has not honoured yet.
                _summaryRow('Paid now', formatPeso(_paidNow), bold: false),
                if (_pendingChequeTotal > 0)
                  _textSummaryRow(
                    'Cheque pending (not counted as paid)',
                    formatPeso(_pendingChequeTotal),
                  ),
                _textSummaryRow(
                  'Change (cash only)',
                  formatPeso(_change),
                  bold: false,
                ),
                // What the drawer has NOT covered stays owed even when a cheque is
                // sitting on it: a pending cheque is not money, so the amount it
                // covers is utang until a manager clears it. This is why the test
                // is the money owed, not what is left after counting the cheque.
                if (_remainingBeforeCheques > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _pendingChequeTotal > 0
                          ? '${formatPeso(_remainingBeforeCheques)} will be left '
                                'unpaid. The cheque holds it open as utang until a '
                                'manager clears it.'
                          : '${formatPeso(_remainingBeforeCheques)} will be left '
                                'unpaid. This records an utang.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (_tenderError case final message?) ...[
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                const Text(
                  'Simulation only. No real payment will be processed.',
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _complete, child: const Text('Complete sale')),
      ],
    );
  }

  /// The Deliver section: off by default, and every field is required once it
  /// is on (the server refuses a partial delivery with `INVALID_DELIVERY`).
  Widget _deliverySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('pos-deliver-toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Deliver to the customer'),
          subtitle: const Text('Adds a delivery charge after the discount.'),
          value: _deliver,
          onChanged: _setDeliver,
        ),
        if (_deliver) ...[
          TextFormField(
            key: const ValueKey('pos-delivery-address'),
            controller: _deliveryAddress,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Delivery address'),
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'A delivery needs an address.'
                : null,
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('pos-delivery-contact'),
                  controller: _deliveryContact,
                  decoration: const InputDecoration(
                    labelText: 'Contact name',
                    // Half-width column: the required sentence needs two lines.
                    errorMaxLines: 4,
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'A delivery needs a contact name.'
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('pos-delivery-phone'),
                  controller: _deliveryPhone,
                  decoration: const InputDecoration(
                    labelText: 'Contact phone',
                    // Half-width column: the required sentence needs two lines.
                    errorMaxLines: 4,
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'A delivery needs a contact phone number.'
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('pos-delivery-date'),
                  onPressed: _pickDeliveryDate,
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(
                    _deliveryDate == null
                        ? 'Delivery date'
                        : formatDate(_deliveryDate!),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('pos-delivery-fee'),
                  controller: _deliveryFee,
                  onChanged: (_) => setState(_syncFollowingRows),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Delivery fee',
                    // The fee's longest refusal wraps in this half-width column.
                    errorMaxLines: 4,
                  ),
                  validator: (value) => switch (moneyInputProblem(value)) {
                    // The rule is shared with the order form (item 10); the
                    // till keeps its own sentence, and its own field label.
                    MoneyInputProblem.notAnAmount =>
                      'The delivery fee must be a number, 0 or more.',
                    MoneyInputProblem.moreThanTwoDecimals =>
                      // 10.005 is refused by the server, not rounded: money the
                      // customer was charged is written to the cent.
                      'The delivery fee needs at most two decimals.',
                    null => null,
                  },
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _tenderRow(_TenderRow row) {
    return Padding(
      key: ValueKey(row),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<TenderMethod>(
                  key: ValueKey('pos-tender-method-${_rows.indexOf(row)}'),
                  isExpanded: true,
                  initialValue: row.method,
                  decoration: const InputDecoration(labelText: 'Method'),
                  items: [
                    for (final method in TenderMethod.tillTenders)
                      DropdownMenuItem(
                        value: method,
                        child: Text(method.label),
                      ),
                  ],
                  onChanged: (value) => _setMethod(row, value ?? row.method),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  key: ValueKey('pos-tender-amount-${_rows.indexOf(row)}'),
                  controller: row.amountController,
                  onChanged: (_) => setState(() {
                    row.followsRemaining = false;
                    _tenderError = null;
                  }),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Amount'),
                  // #21: a short amount is a real transaction (it records an utang),
                  // so the field accepts it and the warning below does the work.
                  validator: (value) {
                    if (double.tryParse((value ?? '').trim()) == null) {
                      return 'Enter a valid amount';
                    }
                    return null;
                  },
                ),
              ),
              IconButton(
                key: ValueKey('pos-remove-tender-${_rows.indexOf(row)}'),
                tooltip: 'Remove this tender',
                onPressed: _rows.length == 1 ? null : () => _removeRow(row),
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
          if (!row.isCheque)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextFormField(
                key: ValueKey('pos-tender-reference-${_rows.indexOf(row)}'),
                controller: row.reference,
                decoration: const InputDecoration(
                  labelText: 'Reference (optional)',
                ),
              ),
            ),
          if (row.isCheque) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('pos-cheque-number-${_rows.indexOf(row)}'),
                      controller: row.chequeNumber,
                      decoration: const InputDecoration(
                        labelText: 'Cheque number',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('pos-cheque-bank-${_rows.indexOf(row)}'),
                      controller: row.bank,
                      decoration: const InputDecoration(labelText: 'Bank'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                key: ValueKey('pos-cheque-date-${_rows.indexOf(row)}'),
                onPressed: () => _pickChequeDate(row),
                icon: const Icon(Icons.event, size: 18),
                label: Text(
                  row.chequeDate == null
                      ? 'Cheque date'
                      : formatDate(row.chequeDate!),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'A cheque is pending until a manager clears it. It does not pay '
                'the sale now.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickChequeDate(_TenderRow row) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: row.chequeDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null || !mounted) return;
    setState(() => row.chequeDate = picked);
  }

  Widget _summaryRow(String label, String value, {bool bold = true}) =>
      _textSummaryRow(label, value, bold: bold);

  Widget _textSummaryRow(String label, String value, {bool bold = true}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      );

  /// Validates, asks for approval when the discount is over the cap, and pops with
  /// the details. Nothing is submitted from here: the page owns the sale.
  Future<void> _complete() async {
    setState(() => _tenderError = null);
    if (!_formKey.currentState!.validate()) return;

    // A cheque the server would refuse is caught here, where the cashier can still
    // fix it, with the same sentences the server's codes map to.
    final chequeRefusal = _chequeRefusal;
    if (chequeRefusal != null) {
      setState(() => _tenderError = chequeRefusal);
      return;
    }

    // Same rule for money that is not cash: the drawer pays the change, so it may
    // not hand back more than the cash it took.
    final overpayRefusal = _nonCashOverpay;
    if (overpayRefusal != null) {
      setState(() => _tenderError = overpayRefusal);
      return;
    }

    final amounts = _amounts;
    final discount = widget.allowDiscount ? _discount : null;

    if (amounts.needsApproval(widget.discountCapPercent)) {
      final token = await _askApproval(
        amounts.percentOfGross,
        discount!.reason,
      );
      if (!mounted || token == null) return;
      _approvalToken = token;
      _approvedPercent = amounts.percentOfGross;
    }

    final token =
        _approvalToken != null &&
            (_approvedPercent - amounts.percentOfGross).abs() < 0.005
        ? _approvalToken
        : null;

    // A delivery always carries its date: leaving it blank would post a sale the
    // server refuses for a reason the cashier cannot see on this screen.
    final delivery = _deliver && widget.lockedDeliveryFee == null
        ? DeliveryDraft(
            address: _deliveryAddress.text.trim(),
            contactName: _deliveryContact.text.trim(),
            contactPhone: _deliveryPhone.text.trim(),
            scheduledDate: _deliveryDate ?? _tomorrow(),
            fee: _fee,
          )
        : null;

    Navigator.pop(
      context,
      PosPaymentDetails(
        tenders: [
          for (final row in _rows)
            PosTender(
              method: row.method,
              amount: row.amount,
              reference: row.reference.text.trim(),
              chequeNumber: row.chequeNumber.text.trim(),
              bank: row.bank.text.trim(),
              chequeDate: row.chequeDate,
            ),
        ],
        discount: discount,
        discountApprovalToken: token,
        delivery: delivery,
      ),
    );
  }

  static DateTime _tomorrow() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1);
  }

  Future<String?> _askApproval(double percent, String reason) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PosDiscountApprovalDialog(
        percent: percent,
        reason: reason,
        service: widget.approvalService,
      ),
    );
  }
}
