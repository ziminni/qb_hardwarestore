import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/format/money_input.dart';
import 'package:client/data/models/customer.dart';
import 'package:client/data/models/delivery.dart';
import 'package:client/data/models/pos_transaction.dart';
import 'package:client/data/models/sale_discount.dart';
import 'package:client/data/models/store_settings.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/data/services/customer_profile_store.dart';
import 'package:client/data/services/discount_approval_service.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
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
/// The part of a sale the customer owes instead of paying (owner 2026-11-19):
/// chosen as the "Utang" method, owed by the person named here. It is never a
/// payment on the wire: the server records whatever the payments leave unpaid
/// as utang, against the named customer the till selects from these details.
class PosUtang {
  const PosUtang({
    required this.name,
    required this.contact,
    required this.amount,
    this.address = '',
  });

  final String name;
  final String contact;
  final String address;
  final double amount;
}

class PosPaymentDetails {
  const PosPaymentDetails({
    required this.tenders,
    this.discount,
    this.discountApprovalToken,
    this.delivery,
    this.utang,
  });

  /// What is owed as utang, and by whom; null when the sale is paid.
  final PosUtang? utang;

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
  // A sale owed in full as utang carries no tender at all.
  TenderMethod get method =>
      tenders.isEmpty ? TenderMethod.cash : primary.method;

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
    this.lines = const [],
    this.cart,
    this.customer,
    this.tenderFees = const [],
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

  /// The cart, for the Review step (owner 2026-11-19). Empty in a caller that
  /// has no cart to show; the step then shows only the totals.
  final List<PosCartLine> lines;

  /// The till's live cart (owner 2026-11-19): the Items step edits it, and the
  /// totals follow it. Null in a caller with no cart; there is no Items step
  /// then, and [total] and [lines] are used as given.
  final PosTransactionViewmodel? cart;

  /// Optional explicit buyer; defaults to [cart.selectedCustomer].
  ///
  /// When a named customer is present, their saved profile automatically
  /// pre-populates the Discount, Utang, and Delivery sections while keeping
  /// every input field editable.
  final Customer? customer;

  Customer? get currentCustomer => customer ?? cart?.selectedCustomer;

  /// The shop's per-tender fees (owner ruling), read from store settings.
  ///
  /// The dialog PREVIEWS them; it never sends one. Each tender row's amount is
  /// the part of the BILL it covers, and the server adds the fee itself, so
  /// sending the fee here would charge it twice.
  final List<TenderFee> tenderFees;

  /// What is being bought, live from [cart] when there is one.
  List<PosCartLine> get currentLines => cart?.lines ?? lines;

  /// The goods' gross, live from [cart] when there is one.
  double get currentTotal => cart?.total ?? total;

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

  /// The Utang choice: this amount is owed, not paid. [method] is ignored then.
  bool isUtang = false;

  double get amount => double.tryParse(amountController.text.trim()) ?? 0;
  bool get isCheque => !isUtang && method.isCheque;

  /// Money in hand: neither a pending cheque nor an utang.
  bool get isMoney => !isUtang && !method.isCheque;

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
  final _utangName = TextEditingController();
  final _utangContact = TextEditingController();
  final _utangAddress = TextEditingController();
  final List<_TenderRow> _rows = [_TenderRow(method: TenderMethod.cash)];

  /// True once the cashier says the goods go out (decision 18).
  bool _deliver = false;

  /// Where the cashier is in the three steps (owner 2026-11-19).
  int _stepIndex = 0;

  /// Payment, Discount (only when the sale may take one), Review.
  List<_PayStep> get _steps => [
    if (widget.cart != null) _PayStep.items,
    _PayStep.payment,
    if (widget.allowDiscount) _PayStep.discount,
    _PayStep.review,
  ];

  _PayStep get _current => _steps[_stepIndex];

  bool get _isLastStep => _stepIndex == _steps.length - 1;

  /// Next: the step's own fields are checked first, so a mistake is fixed on
  /// the step that made it rather than found at the end.
  void _next() {
    setState(() => _tenderError = null);
    if (!_formKey.currentState!.validate()) return;
    if (_current == _PayStep.payment) {
      if (_duplicateMethod case final duplicate?) {
        setState(() => _tenderError = duplicate);
        return;
      }
      final chequeRefusal = _chequeRefusal;
      if (chequeRefusal != null) {
        setState(() => _tenderError = chequeRefusal);
        return;
      }
    }
    setState(() => _stepIndex++);
  }

  void _back() => setState(() {
    _tenderError = null;
    if (_stepIndex > 0) _stepIndex--;
  });

  /// The fields of steps no longer on screen, checked again at the end: a
  /// hidden field cannot validate itself. Answers the step to return to.
  _PayStep? _hiddenStepProblem() {
    if (_hasUtang &&
        (_utangName.text.trim().isEmpty || _utangContact.text.trim().isEmpty)) {
      _tenderError =
          'An utang needs the name and contact number of who owes it.';
      return _PayStep.payment;
    }
    if (_discountValue.text.trim().isNotEmpty &&
        _discountReason.text.trim().isEmpty) {
      _tenderError = 'A discount needs a reason.';
      return _PayStep.discount;
    }
    return null;
  }

  /// The Discount switch (owner 2026-11-19): off, the discount fields stay
  /// hidden and no discount is applied.
  bool _discountOn = false;

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
    _applyCustomerPrefill();
    // What the sale ASKS FOR, which is not always the goods total: an order's
    // fulfilment carries the delivery fee agreed on its slip.
    _rows.first.amountController.text = _due.toStringAsFixed(2);
    widget.cart?.addListener(_onCartChanged);
  }

  CustomerProfile? get _activeProfile =>
      CustomerProfileStore.instance.resolveFor(widget.currentCustomer);

  /// Pre-populates Discount, Utang, and Delivery fields from the selected
  /// customer's saved profile while leaving every field editable.
  void _applyCustomerPrefill() {
    final buyer = widget.currentCustomer;
    if (buyer == null || buyer.isWalkIn) return;
    final profile = _activeProfile;

    _prefillUtangFields(buyer, profile);
    _prefillDeliveryFields(buyer, profile);

    if (widget.allowDiscount) {
      final preset = profile?.toPosDiscount;
      if (preset != null) {
        _discountOn = true;
        _kind = preset.kind;
        _discountValue.text = formatQuantity(preset.value);
        _discountReason.text = preset.reason;
      }
    }
  }

  void _prefillUtangFields(Customer? buyer, CustomerProfile? profile) {
    if (buyer == null || buyer.isWalkIn) return;
    if (_utangName.text.trim().isEmpty) {
      _utangName.text = buyer.name;
    }
    final phone = profile?.phone.trim() ?? '';
    if (_utangContact.text.trim().isEmpty && phone.isNotEmpty) {
      _utangContact.text = phone;
    }
    final address = profile?.address.trim() ?? '';
    if (_utangAddress.text.trim().isEmpty && address.isNotEmpty) {
      _utangAddress.text = address;
    }
  }

  void _prefillDeliveryFields(Customer? buyer, CustomerProfile? profile) {
    if (buyer == null || buyer.isWalkIn) return;
    if (_deliveryContact.text.trim().isEmpty) {
      _deliveryContact.text = buyer.name;
    }
    final phone = profile?.phone.trim() ?? '';
    if (_deliveryPhone.text.trim().isEmpty && phone.isNotEmpty) {
      _deliveryPhone.text = phone;
    }
    final address = profile?.address.trim() ?? '';
    if (_deliveryAddress.text.trim().isEmpty && address.isNotEmpty) {
      _deliveryAddress.text = address;
    }
  }

  /// The cart changed on the Items step: the payment rows that follow the
  /// amount due follow it, and an emptied cart has nothing left to pay.
  void _onCartChanged() {
    if (!mounted) return;
    // Only while this dialog is the screen on top. After Complete it has
    // already popped itself, and the sale then clears the cart and reloads
    // stock: popping again would close whatever sits above the till (the
    // receipt) or throw on an empty navigator.
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (widget.currentLines.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(_syncFollowingRows);
  }

  /// Applies an Items-step change; a refusal (not enough stock) is shown.
  void _editLine(String? Function() change) {
    final refusal = change();
    setState(() => _tenderError = refusal);
  }

  Future<void> _typeQuantity(int index, PosCartLine line) async {
    final controller = TextEditingController(
      text: formatQuantity(line.quantity),
    );
    final typed = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Quantity of ${line.productName}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: line.unit),
          onSubmitted: (value) =>
              Navigator.pop(context, double.tryParse(value.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text.trim())),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (typed == null || !mounted) return;
    _editLine(() => widget.cart!.setLineQuantity(index, typed));
  }

  @override
  void dispose() {
    widget.cart?.removeListener(_onCartChanged);
    for (final row in [..._rows, ..._removedRows]) {
      row.dispose();
    }
    _discountValue.dispose();
    _discountReason.dispose();
    _deliveryAddress.dispose();
    _deliveryContact.dispose();
    _deliveryPhone.dispose();
    _deliveryFee.dispose();
    _utangName.dispose();
    _utangContact.dispose();
    _utangAddress.dispose();
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
      PosDiscountAmounts.forDiscount(widget.currentTotal, _discount);

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
    // An utang names the customer, so a cheque beside it has someone to owe.
    if (!widget.customerIsNamed && !_hasUtang) {
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
      .where((row) => row.isMoney)
      .fold(0.0, (sum, row) => sum + row.amount);

  bool get _hasUtang => _rows.any((row) => row.isUtang);

  /// The fee one tender row owes, mirroring the server's rule: percent of what
  /// the row covers, or the flat value once per row.
  double _feeFor(String method, double covered) {
    for (final fee in widget.tenderFees) {
      if (!fee.isActive || fee.method != method) continue;
      final raw = fee.kind == TenderFee.kindPercent
          ? covered * fee.value / 100
          : fee.value;
      return (raw * 100).roundToDouble() / 100;
    }
    return 0;
  }

  /// Every fee on this sale, previewed once (money tenders only: utang is owed,
  /// a pending cheque has not arrived).
  double get _paymentFeeTotal => _rows
      .where((row) => row.isMoney)
      .fold(0.0, (sum, row) => sum + _feeFor(row.method.code, row.amount));

  double get _utangTotal => _rows
      .where((row) => row.isUtang)
      .fold(0.0, (sum, row) => sum + row.amount);

  double get _pendingChequeTotal => _rows
      .where((row) => row.isCheque)
      .fold(0.0, (sum, row) => sum + row.amount);

  double get _cashTotal => _rows
      .where((row) => row.isMoney && row.method == TenderMethod.cash)
      .fold(0.0, (sum, row) => sum + row.amount);

  /// What the sale still asks the drawer for, before any cheque is taken.
  double get _remainingBeforeCheques =>
      (_due - _paidNow).clamp(0, double.infinity);

  /// Change is paid from the DRAWER only: cash above what is owed, never from a
  /// cheque the shop has not cashed.
  double get _change {
    final nonCashPaid = _rows
        .where((row) => row.isMoney && row.method != TenderMethod.cash)
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
        'drawer: lower the GCash amount and take the rest in cash.';
  }

  /// Turning the discount off clears it, so a hidden value is never applied.
  void _setDiscountOn(bool value) {
    setState(() => _discountOn = value);
    if (!value) {
      _discountValue.clear();
      _discountReason.clear();
      _onDiscountChanged();
    }
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
      if (value) {
        _prefillDeliveryFields(widget.currentCustomer, _activeProfile);
      }
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

  /// Every method the till offers, Utang last, as dropdown choices.
  static final List<String> _allChoices = [
    for (final method in TenderMethod.tillTenders) method.code,
    _utangChoice,
  ];

  String _choiceOf(_TenderRow row) =>
      row.isUtang ? _utangChoice : row.method.code;

  String _labelOf(String choice) => choice == _utangChoice
      ? 'Utang'
      : TenderMethod.fromWire(choice)?.label ?? choice;

  /// The methods rows OTHER than [row] already use: each method once per
  /// sale (owner 2026-11-19), so a split is Cash + GCash, never Cash + Cash.
  Set<String> _usedByOthers(_TenderRow? row) => {
    for (final other in _rows)
      if (!identical(other, row)) _choiceOf(other),
  };

  /// The methods no row uses yet, in the dropdown's order.
  List<String> get _unusedChoices {
    final used = _usedByOthers(null);
    return [
      for (final choice in _allChoices)
        if (!used.contains(choice)) choice,
    ];
  }

  /// The warning for two rows on the same method, or null.
  String? get _duplicateMethod {
    final seen = <String>{};
    for (final row in _rows) {
      final choice = _choiceOf(row);
      if (!seen.add(choice)) {
        return '${_labelOf(choice)} is chosen twice. Each tender needs a '
            'different method: change or remove one.';
      }
    }
    return null;
  }

  /// Selects the whole of a money field on tap (owner 2026-11-19), so the
  /// cashier types the new amount straight over the old one.
  void _selectAll(TextEditingController controller) {
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  void _addRow() {
    final free = _unusedChoices;
    if (free.isEmpty) return;
    final row = _TenderRow(
      method: TenderMethod.cash,
      amount: _remainingBeforeCheques.toStringAsFixed(2),
    );
    // The new row starts on the first method no other row uses.
    final choice = free.first;
    if (choice == _utangChoice) {
      row.isUtang = true;
      _prefillUtangFields(widget.currentCustomer, _activeProfile);
    } else {
      row.method = TenderMethod.fromWire(choice) ?? TenderMethod.cash;
    }
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

  static const _utangChoice = 'UTANG';

  void _setChoice(_TenderRow row, String? choice) {
    if (choice == null) return;
    if (_usedByOthers(row).contains(choice)) {
      setState(
        () => _tenderError =
            '${_labelOf(choice)} is already used by another tender. '
            'Choose a different method.',
      );
      return;
    }
    if (choice == _utangChoice) {
      setState(() {
        row.isUtang = true;
        _prefillUtangFields(widget.currentCustomer, _activeProfile);
        _tenderError = null;
      });
      return;
    }
    row.isUtang = false;
    _setMethod(
      row,
      TenderMethod.tillTenders.firstWhere(
        (method) => method.code == choice,
        orElse: () => TenderMethod.cash,
      ),
    );
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
    final unpaid = _remainingBeforeCheques;
    final media = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      // One fixed, tall size on every step (owner 2026-11-19): the window does
      // not jump as the cashier moves between Items, Payment and Review.
      child: SizedBox(
        width: 520,
        height: (media.height - 48).clamp(0, 760).toDouble(),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---- Title bar --------------------------------------------
              Container(
                color: AppColors.brandBlack,
                padding: const EdgeInsets.fromLTRB(24, 14, 12, 14),
                child: Row(
                  children: [
                    const Icon(Icons.point_of_sale, color: AppColors.brandGold),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Payment',
                        style: TextStyle(
                          color: AppColors.brandWhite,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cancel',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close,
                        color: AppColors.brandWhite,
                      ),
                    ),
                  ],
                ),
              ),
              // ---- Body ---------------------------------------------------
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _stepBar(),
                      const SizedBox(height: 24),
                      // Step 1: the cart itself, editable before paying.
                      if (_current == _PayStep.items) _itemsSection(),
                      // Step 2: how it is paid, then whether it is delivered.
                      if (_current == _PayStep.payment) ...[
                        _section(
                          icon: Icons.payments_outlined,
                          title: 'Payment',
                          trailing: TextButton.icon(
                            key: const ValueKey('pos-add-tender'),
                            // Off once every method has a row.
                            onPressed: _unusedChoices.isEmpty ? null : _addRow,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add tender'),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final row in _rows) _tenderRow(row),
                              if (_hasUtang) _utangFields(),
                            ],
                          ),
                        ),
                      ],
                      if (widget.lockedDeliveryFee == null &&
                          _current == _PayStep.payment)
                        _section(
                          icon: Icons.local_shipping_outlined,
                          title: 'Delivery',
                          // The switch sits on the heading's right (owner
                          // 2026-11-19); the fields appear only when it is on.
                          trailing: Switch(
                            key: const ValueKey('pos-deliver-toggle'),
                            value: _deliver,
                            onChanged: _setDeliver,
                          ),
                          collapsed: !_deliver,
                          child: _deliverySection(),
                        ),
                      // Step 3: any discount (owner 2026-11-19). Off: only two
                      // centred squares, Apply discount and Continue.
                      if (widget.allowDiscount &&
                          _current == _PayStep.discount &&
                          !_discountOn)
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 400),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _squareButton(
                                      key: const ValueKey(
                                        'pos-discount-toggle',
                                      ),
                                      icon: Icons.sell_outlined,
                                      label: 'Apply discount',
                                      onTap: () => _setDiscountOn(true),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _squareButton(
                                      key: const ValueKey('pos-payment-next'),
                                      icon: Icons.arrow_forward,
                                      label: 'Continue',
                                      dark: true,
                                      onTap: _next,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      // On: the section as first designed; its switch turns
                      // the discount back off and returns to the squares.
                      if (widget.allowDiscount &&
                          _current == _PayStep.discount &&
                          _discountOn)
                        _section(
                          icon: Icons.sell_outlined,
                          title: 'Discount',
                          trailing: Switch(
                            key: const ValueKey('pos-discount-toggle'),
                            value: _discountOn,
                            onChanged: _setDiscountOn,
                          ),
                          note: needsApproval
                              ? 'Needs manager approval: '
                                    '${amounts.percentOfGross.toStringAsFixed(2)}% '
                                    'is above the '
                                    '${widget.discountCapPercent.toStringAsFixed(2)}% cap.'
                              : null,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
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
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
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
                                        if (parsed == null) {
                                          return 'Enter a valid number';
                                        }
                                        if (parsed < 0) {
                                          return 'A discount cannot be negative';
                                        }
                                        if (_kind == DiscountKind.percent &&
                                            parsed > 100) {
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
                                      key: const ValueKey(
                                        'pos-discount-reason',
                                      ),
                                      controller: _discountReason,
                                      onChanged: (_) => _onDiscountChanged(),
                                      decoration: const InputDecoration(
                                        labelText: 'Reason for the discount',
                                      ),
                                      validator: (value) {
                                        if ((_discountValue.text
                                                .trim()
                                                .isNotEmpty) &&
                                            (value ?? '').trim().isEmpty) {
                                          return 'A discount needs a reason';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              // The over-cap sentence is the section's note.
                            ],
                          ),
                        ),
                      // Step 4: what is being bought, before it is final.
                      if (_current == _PayStep.review) _reviewSection(),
                    ],
                  ),
                ),
              ),
              // ---- Footer: the totals and the decision, always in view ----
              // (On the Discount step only a Back button: the step's own
              // Continue moves on, owner 2026-11-19.)
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceSunken,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: _current == _PayStep.discount && !_discountOn
                    ? _discountFooter()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Amount due',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Text(
                                formatPeso(_due),
                                key: const ValueKey('pos-amount-due'),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _total('Paid now', formatPeso(_paidNow)),
                              ),
                              Expanded(
                                child: _total(
                                  'Change (cash only)',
                                  formatPeso(_change),
                                ),
                              ),
                              Expanded(
                                child: _total(
                                  _hasUtang ? 'Utang' : 'Unpaid',
                                  formatPeso(unpaid),
                                  warn: unpaid > 0,
                                ),
                              ),
                            ],
                          ),
                          if (_pendingChequeTotal > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: _textSummaryRow(
                                'Cheque pending (not counted as paid)',
                                formatPeso(_pendingChequeTotal),
                              ),
                            ),
                          // What the drawer has NOT covered stays owed even when a
                          // cheque sits on it: a pending cheque is not money.
                          if (unpaid > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                _pendingChequeTotal > 0
                                    ? '${formatPeso(unpaid)} will be left unpaid. The '
                                          'cheque holds it open as utang until a manager '
                                          'clears it.'
                                    : '${formatPeso(unpaid)} will be left unpaid. This '
                                          'records an utang.',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (_tenderError case final message?)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                message,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                  ),
                                  onPressed: _stepIndex == 0
                                      ? () => Navigator.pop(context)
                                      : _back,
                                  child: Text(
                                    _stepIndex == 0 ? 'Cancel' : 'Back',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                    backgroundColor: AppColors.brandBlack,
                                    foregroundColor: AppColors.brandWhite,
                                  ),
                                  key: const ValueKey('pos-payment-next'),
                                  onPressed: _isLastStep ? _complete : _next,
                                  icon: Icon(
                                    _isLastStep
                                        ? Icons.check_circle_outline
                                        : Icons.arrow_forward,
                                  ),
                                  label: Text(
                                    _isLastStep
                                        ? 'Complete transaction'
                                        : 'Next',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The three steps across the top: done ones ticked, the current one gold.
  Widget _stepBar() {
    final steps = _steps;
    return Row(
      key: const ValueKey('pos-payment-steps'),
      children: [
        for (final (index, step) in steps.indexed) ...[
          if (index > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: index <= _stepIndex
                    ? AppColors.brandGold
                    : AppColors.border,
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: index < _stepIndex
                    ? AppColors.brandBlack
                    : index == _stepIndex
                    ? AppColors.brandGold
                    : AppColors.surfaceMuted,
                child: index < _stepIndex
                    ? const Icon(
                        Icons.check,
                        size: 16,
                        color: AppColors.brandGold,
                      )
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: index == _stepIndex
                              ? AppColors.brandBlack
                              : AppColors.textSecondary,
                        ),
                      ),
              ),
              const SizedBox(height: 4),
              Text(
                step.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: index == _stepIndex
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: index == _stepIndex
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Items: every cart line with - / quantity / + and remove, so the order is
  /// corrected here instead of going back to the till (owner 2026-11-19).
  Widget _itemsSection() {
    final lines = widget.currentLines;
    // Plain rows under a heading, not a card (owner 2026-11-19).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Row(
            children: [
              const Icon(
                Icons.shopping_cart_outlined,
                size: 20,
                color: AppColors.brandGoldText,
              ),
              const SizedBox(width: 8),
              Text(
                'Items (${lines.length})',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 20),
        for (final (index, line) in lines.indexed) ...[
          Row(
            key: ValueKey('pos-item-${line.variantUomId}'),
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.variantName.isEmpty
                          ? line.productName
                          : '${line.productName} · ${line.variantName}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${formatPeso(line.unitPrice)} / ${line.unit}  ·  '
                      '${formatPeso(line.total)}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'One less',
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    _editLine(() => widget.cart!.stepLine(index, -1)),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              InkWell(
                key: ValueKey('pos-item-qty-${line.variantUomId}'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => _typeQuantity(index, line),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 52),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${formatQuantity(line.quantity)} ${line.unit}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'One more',
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    _editLine(() => widget.cart!.stepLine(index, 1)),
                icon: const Icon(Icons.add_circle_outline),
              ),
              IconButton(
                tooltip: 'Remove',
                visualDensity: VisualDensity.compact,
                onPressed: () => _editLine(() {
                  widget.cart!.removeLine(index);
                  return null;
                }),
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
              ),
            ],
          ),
          const Divider(height: 20),
        ],
      ],
    );
  }

  /// Review: every cart line, then how the sale is being paid, before the
  /// cashier completes it.
  Widget _reviewSection() {
    final amounts = _amounts;
    return _section(
      icon: Icons.receipt_long_outlined,
      title: 'Review',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.currentLines.isNotEmpty) ...[
            for (final line in widget.currentLines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.variantName.isEmpty
                                ? line.productName
                                : '${line.productName} · ${line.variantName}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${formatQuantity(line.quantity)} ${line.unit} × '
                            '${formatPeso(line.unitPrice)}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formatPeso(line.total),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            const Divider(height: 16),
          ],
          _textSummaryRow('Gross', formatPeso(amounts.gross), bold: false),
          if (amounts.discountAmount > 0)
            _textSummaryRow(
              'Discount',
              formatPeso(-amounts.discountAmount),
              bold: false,
            ),
          if (_deliveryCharge > 0)
            _textSummaryRow(
              'Delivery charge',
              formatPeso(_deliveryCharge),
              bold: false,
            ),
          _textSummaryRow('Amount due', formatPeso(_due)),
          // Owner ruling (tender fees): a separate line from VAT, and the one
          // number the customer actually hands over / transfers.
          if (_paymentFeeTotal > 0) ...[
            _textSummaryRow(
              'Payment fees',
              formatPeso(_paymentFeeTotal),
              bold: false,
            ),
            _textSummaryRow(
              'Total to pay',
              formatPeso(_due + _paymentFeeTotal),
            ),
          ],
          const Divider(height: 16),
          for (final row in _rows)
            _textSummaryRow(
              row.isUtang
                  ? 'Utang · ${_utangName.text.trim()}'
                  : row.isCheque
                  ? '${row.method.label} (pending)'
                  : _feeFor(row.method.code, row.amount) > 0
                  ? '${row.method.label} · send '
                        '${formatPeso(row.amount + _feeFor(row.method.code, row.amount))}'
                  : row.method.label,
              formatPeso(row.amount),
              bold: false,
            ),
          if (_deliver && widget.lockedDeliveryFee == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Deliver to ${_deliveryAddress.text.trim()} on '
                '${formatDate(_deliveryDate ?? _tomorrow())}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  /// One section of the payment: an icon and title, then its fields, on a
  /// white card so Discount, Delivery and Payment read as separate steps.
  Widget _section({
    required IconData icon,
    required String title,
    required Widget child,
    Widget? trailing,
    String? note,
    bool collapsed = false,
  }) {
    // Plain, not a card (owner 2026-11-19: too many boxes): a heading, a rule,
    // then the fields, straight on the window. Still on a Material, so the
    // Deliver and Discount switches have one to paint on.
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.brandGoldText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            // The heading's line always shows; a switched-off section hides
            // only its fields (owner 2026-11-19).
            const Divider(height: 20),
            if (!collapsed) child,
            if (note != null) ...[
              const SizedBox(height: 10),
              Text(
                note,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// A big square choice on the Discount step: an icon over a label. Gold
  /// when [selected]; black for the step's forward choice.
  Widget _squareButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
    bool dark = false,
  }) {
    final background = dark
        ? AppColors.brandBlack
        : selected
        ? AppColors.brandGoldLight
        : AppColors.cardBackground;
    final foreground = dark ? AppColors.brandWhite : AppColors.brandBlack;
    return AspectRatio(
      aspectRatio: 1.25,
      child: Material(
        key: key,
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected || dark ? AppColors.brandGold : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? Icons.check_circle : icon,
                size: 34,
                color: dark ? AppColors.brandGold : foreground,
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The Discount step's footer: any error, and Back.
  Widget _discountFooter() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_tenderError case final message?)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      OutlinedButton.icon(
        key: const ValueKey('pos-payment-back'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: _back,
        icon: const Icon(Icons.arrow_back),
        label: const Text('Back'),
      ),
    ],
  );

  /// One of the footer's three totals.
  Widget _total(String label, String value, {bool warn = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: warn ? Theme.of(context).colorScheme.error : null,
        ),
      ),
    ],
  );

  Widget _deliverySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                // Drawn like the fee beside it (owner 2026-11-19): a labelled
                // box with the date inside, the calendar at its end.
                child: InkWell(
                  key: const ValueKey('pos-delivery-date'),
                  onTap: _pickDeliveryDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    isEmpty: _deliveryDate == null,
                    decoration: const InputDecoration(
                      labelText: 'Delivery date',
                      suffixIcon: Icon(Icons.event, size: 20),
                    ),
                    child: Text(
                      _deliveryDate == null ? '' : formatDate(_deliveryDate!),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('pos-delivery-fee'),
                  controller: _deliveryFee,
                  onTap: () => _selectAll(_deliveryFee),
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

  /// Who owes the utang: a name and a number to reach them, and where they
  /// live if the cashier has it. The till names the sale's customer from these.
  // Plain fields under a bold line, no tinted box (owner 2026-11-19).
  Widget _utangFields() => Padding(
    key: const ValueKey('pos-utang-details'),
    padding: const EdgeInsets.only(top: 4, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Utang of ${formatPeso(_utangTotal)}: who owes it?',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: const ValueKey('pos-utang-name'),
          controller: _utangName,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
          validator: (value) => (value ?? '').trim().isEmpty
              ? 'Enter the name of who owes it'
              : null,
        ),
        TextFormField(
          key: const ValueKey('pos-utang-contact'),
          controller: _utangContact,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Contact number'),
          validator: (value) =>
              (value ?? '').trim().isEmpty ? 'Enter a contact number' : null,
        ),
        TextFormField(
          key: const ValueKey('pos-utang-address'),
          controller: _utangAddress,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Address (optional)'),
        ),
      ],
    ),
  );

  Widget _tenderRow(_TenderRow row) {
    return Padding(
      key: ValueKey(row),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('pos-tender-method-${_rows.indexOf(row)}'),
                  isExpanded: true,
                  initialValue: row.isUtang ? _utangChoice : row.method.code,
                  decoration: const InputDecoration(labelText: 'Method'),
                  // Owner 2026-11-19: Card left the till and Utang took its
                  // place; a method another row already uses is not offered.
                  items: [
                    for (final choice in _allChoices)
                      if (choice == _choiceOf(row) ||
                          !_usedByOthers(row).contains(choice))
                        DropdownMenuItem(
                          value: choice,
                          child: Text(_labelOf(choice)),
                        ),
                  ],
                  onChanged: (value) => _setChoice(row, value),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  key: ValueKey('pos-tender-amount-${_rows.indexOf(row)}'),
                  controller: row.amountController,
                  onTap: () => _selectAll(row.amountController),
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
          if (row.isMoney)
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

    // A field on an earlier step is no longer built, so it cannot validate
    // itself: check it here and send the cashier back to it.
    if (_duplicateMethod case final duplicate?) {
      setState(() {
        _tenderError = duplicate;
        _stepIndex = _steps.indexOf(_PayStep.payment);
      });
      return;
    }
    if (_hiddenStepProblem() case final step?) {
      setState(() => _stepIndex = _steps.indexOf(step));
      return;
    }

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
        // An utang row is owed, not paid: it never goes on the wire.
        tenders: [
          for (final row in _rows.where((row) => !row.isUtang))
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
        utang: _hasUtang
            ? PosUtang(
                name: _utangName.text.trim(),
                contact: _utangContact.text.trim(),
                address: _utangAddress.text.trim(),
                amount: _utangTotal,
              )
            : null,
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

/// The payment window's steps, in order (owner 2026-11-19).
enum _PayStep {
  items('Items'),
  payment('Payment'),
  discount('Discount'),
  review('Review');

  const _PayStep(this.label);
  final String label;
}
