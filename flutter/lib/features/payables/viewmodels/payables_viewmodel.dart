import 'package:client/data/models/supplier_payables.dart';
import 'package:client/data/models/supplier_returns.dart';
import 'package:client/data/repositories/payables_repository.dart';
import 'package:client/data/services/payables_service.dart';
import 'package:flutter/foundation.dart';

/// The payables screen's data: what the shop owes, and one payment at a time.
///
/// Screen-scoped and provided by its own page rather than registered in
/// `main.dart` (decision 11's ruling): a viewmodel that lives as long as one
/// screen should not outlive it, and a stale balance on tomorrow's screen is
/// exactly the mistake this screen cannot afford.
class PayablesViewmodel extends ChangeNotifier {
  PayablesViewmodel({PayablesRepository? repository})
    : _repository = repository ?? PayablesRepository();

  final PayablesRepository _repository;

  List<SupplierBill> _bills = const [];
  List<SupplierPayable> _suppliers = const [];
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _loadError;
  String? _payError;

  List<SupplierCreditNote> _creditNotes = const [];
  bool _creditNotesLoaded = false;
  bool _creditNotesLoading = false;
  String? _creditNotesError;

  /// The queue: CHEQUES only. The payments route also answers cash and credit
  /// rows, and an ordinary tender has no bank decision to make.
  List<SupplierPayment> _cheques = const [];
  bool _chequesLoaded = false;
  bool _chequesLoading = false;
  String? _chequesError;
  SupplierPaymentStatus? _chequeStatusFilter;
  final Set<int> _deciding = {};
  String? _decisionError;

  List<SupplierBill> get bills => List.unmodifiable(_bills);
  List<SupplierPayable> get suppliers => List.unmodifiable(_suppliers);
  bool get isLoading => _isLoading;

  /// The last read's failure. A failed refresh keeps the rows it already had —
  /// "no bills" and "not loaded" are different facts about the shop's debts.
  String? get loadError => _loadError;

  /// A payment is in flight. The dialog disables its button on this, so a
  /// double tap cannot post twice.
  bool get isSubmitting => _isSubmitting;

  /// The last refusal, in the server's own words; null when none.
  String? get payError => _payError;

  /// Every credit note read so far, newest first (the server's order).
  List<SupplierCreditNote> get creditNotes => List.unmodifiable(_creditNotes);
  bool get isLoadingCreditNotes => _creditNotesLoading;

  /// The credit-notes read's failure; a retry re-runs it.
  String? get creditNotesError => _creditNotesError;

  /// The supplier cheques on file, oldest cheque first — the order a queue is
  /// chased in.
  List<SupplierPayment> get cheques => List.unmodifiable(_cheques);
  bool get isLoadingCheques => _chequesLoading;
  String? get chequesError => _chequesError;

  /// The status chip the reader picked, or null for every cheque.
  SupplierPaymentStatus? get chequeStatusFilter => _chequeStatusFilter;

  /// The cheques the chip left visible.
  List<SupplierPayment> get filteredCheques => [
    for (final cheque in _cheques)
      if (_chequeStatusFilter == null || cheque.status == _chequeStatusFilter)
        cheque,
  ];

  /// The last decision's refusal, in the server's own words; null when none.
  String? get decisionError => _decisionError;

  /// True while a decision on [paymentId] is in flight, so its buttons rest.
  bool isDeciding(int paymentId) => _deciding.contains(paymentId);

  /// Loads the bills and the per-supplier summary.
  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      final bills = await _repository.fetchBills();
      final suppliers = await _repository.fetchSummary();
      _bills = bills;
      _suppliers = suppliers;
    } on PayablesServiceException catch (error) {
      _loadError = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// The bills the reader asked for, overdue first and then by due date.
  ///
  /// The overdue-first order is the point of the screen: a late bill costs a
  /// supplier relationship, a bill due next month does not. The server already
  /// orders by `due_date`; this only lifts the overdue ones above them.
  List<SupplierBill> filteredBills({
    int? supplierId,
    SupplierBillStatus? status,
    bool overdueOnly = false,
  }) {
    final rows = [
      for (final bill in _bills)
        if ((supplierId == null || bill.supplierId == supplierId) &&
            (status == null || bill.status == status) &&
            (!overdueOnly || bill.isOverdue))
          bill,
    ];
    rows.sort((a, b) {
      if (a.isOverdue != b.isOverdue) return a.isOverdue ? -1 : 1;
      final byDate = a.dueDate.compareTo(b.dueDate);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    return rows;
  }

  /// Records one payment against [bill], then re-reads the bill and the totals.
  ///
  /// Returns null on success, or the sentence to show. A second call while the
  /// first is in flight returns at once and posts nothing: the server's lock
  /// already refuses a real overpayment, but there is no reason to spend a
  /// request finding that out.
  /// The one call this screen can make to a note: the money it settles is a
  /// ``CREDIT`` payment naming that note (`credit_note`), capped server-side at
  /// `min(note remaining, bill balance)` — the client's cap is only a courtesy.
  Future<String?> pay({
    required SupplierBill bill,
    required double amount,
    required SupplierPaymentMethod method,
    String reference = '',
    String? chequeNumber,
    String? chequeBank,
    DateTime? chequeDate,
    int? creditNoteId,
  }) async {
    if (_isSubmitting) return null;
    _isSubmitting = true;
    _payError = null;
    notifyListeners();
    try {
      await _repository.createPayment({
        'bill': bill.id,
        // 2 dp text, never the double: `399.99999999999994` is not a payment
        // anyone typed and the server refuses it.
        'amount': amount.toStringAsFixed(2),
        'method': method.code,
        if (reference.isNotEmpty) 'reference': reference,
        if (chequeNumber != null && chequeNumber.isNotEmpty)
          'cheque_number': chequeNumber,
        if (chequeBank != null && chequeBank.isNotEmpty)
          'cheque_bank': chequeBank,
        if (chequeDate != null) 'cheque_date': _isoDate(chequeDate),
        'credit_note': ?creditNoteId,
      });
    } on PayablesServiceException catch (error) {
      _payError = error.message;
      return error.message;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }

    await _refreshAfterPayment(bill.id);
    // Spending credit moved the note's own remaining, so the picker's figures
    // are stale until it is re-read.
    if (creditNoteId != null) {
      _creditNotesLoaded = false;
      await ensureCreditNotes();
    }
    return null;
  }

  /// Reads the credit notes once per screen (a retry after a failure, because a
  /// failed read left nothing loaded).
  ///
  /// No notify before the request: a tab asks for this from `initState`, which
  /// runs mid-build, and marking an ancestor dirty there is an error. The rows
  /// arrive one frame later, which is what a first load looks like anyway.
  Future<void> ensureCreditNotes() async {
    if (_creditNotesLoaded || _creditNotesLoading) return;
    _creditNotesLoading = true;
    try {
      _creditNotes = await _repository.fetchCreditNotes();
      _creditNotesError = null;
      _creditNotesLoaded = true;
    } on PayablesServiceException catch (error) {
      _creditNotesError = error.message;
    } finally {
      _creditNotesLoading = false;
      notifyListeners();
    }
  }

  /// [supplierId]'s notes that still have money on them, in the order read — the
  /// only notes an "Apply credit" picker may offer.
  List<SupplierCreditNote> openCreditNotesFor(int supplierId) => [
    for (final note in _creditNotes)
      if (note.supplierId == supplierId && note.isOpen) note,
  ];

  /// Reads the supplier cheque queue once per screen. See [ensureCreditNotes]
  /// for why nothing is notified before the request.
  Future<void> ensureCheques() async {
    if (_chequesLoaded || _chequesLoading) return;
    _chequesLoading = true;
    try {
      final rows = await _repository.fetchCheques();
      _cheques = _orderedCheques([
        for (final row in rows)
          if (row.method == SupplierPaymentMethod.cheque) row,
      ]);
      _chequesError = null;
      _chequesLoaded = true;
    } on PayablesServiceException catch (error) {
      _chequesError = error.message;
    } finally {
      _chequesLoading = false;
      notifyListeners();
    }
  }

  /// Narrows the queue to one status, or back to all of them. No re-read: the
  /// queue is already loaded and the chip is a view of it.
  void setChequeStatusFilter(SupplierPaymentStatus? status) {
    if (_chequeStatusFilter == status) return;
    _chequeStatusFilter = status;
    notifyListeners();
  }

  /// The bank honoured [cheque]: nothing moves (the bill counted it at issue).
  /// Returns true when the server accepted the decision.
  Future<bool> clearCheque(SupplierPayment cheque) => _decide(cheque, null);

  /// The bank refused [cheque]: the server puts the amount back on the bill.
  /// Returns true when the server accepted the decision.
  Future<bool> bounceCheque(SupplierPayment cheque, String reason) =>
      _decide(cheque, reason);

  /// One decision, never two at once on the same cheque. A bounce moves the
  /// bill's balance, so the bills and the totals are re-read afterwards; a
  /// refusal that says the cheque is already decided means the rows are wrong
  /// and the queue is re-read rather than argued with.
  Future<bool> _decide(SupplierPayment cheque, String? reason) async {
    if (_deciding.contains(cheque.id)) return false;
    _deciding.add(cheque.id);
    _decisionError = null;
    notifyListeners();
    try {
      final decided = reason == null
          ? await _repository.clearCheque(cheque.id)
          : await _repository.bounceCheque(cheque.id, reason);
      _cheques = [
        for (final row in _cheques) row.id == decided.id ? decided : row,
      ];
    } on PayablesServiceException catch (error) {
      _decisionError = error.message;
      if (error.alreadyDecided) {
        _chequesLoaded = false;
        _deciding.remove(cheque.id);
        notifyListeners();
        await ensureCheques();
        return false;
      }
      return false;
    } finally {
      _deciding.remove(cheque.id);
      notifyListeners();
    }
    await _reloadTotals();
    return true;
  }

  /// Oldest cheque date first, undated last, then by id: the queue exists to
  /// chase the cheque that has been outstanding longest.
  List<SupplierPayment> _orderedCheques(List<SupplierPayment> rows) {
    rows.sort((a, b) {
      final left = a.chequeDate;
      final right = b.chequeDate;
      if (left != null && right != null) {
        final byDate = left.compareTo(right);
        if (byDate != 0) return byDate;
      } else if (left != null) {
        return -1;
      } else if (right != null) {
        return 1;
      }
      return a.id.compareTo(b.id);
    });
    return rows;
  }

  /// Re-reads the bills and the per-supplier totals after something moved money.
  Future<void> _reloadTotals() async {
    try {
      _bills = await _repository.fetchBills();
      _suppliers = await _repository.fetchSummary();
    } on PayablesServiceException catch (error) {
      _loadError = error.message;
    } finally {
      notifyListeners();
    }
  }

  /// Replaces the paid bill with the server's copy and reloads the totals.
  ///
  /// The payment is already recorded, so a failed refresh is NOT a failed
  /// payment and is not reported as one: the row keeps its old balance and the
  /// next load corrects it. Reporting a refusal here would send a clerk to pay
  /// twice.
  Future<void> _refreshAfterPayment(int billId) async {
    try {
      final refreshed = await _repository.fetchBill(billId);
      _bills = [
        for (final bill in _bills) bill.id == billId ? refreshed : bill,
      ];
      _suppliers = await _repository.fetchSummary();
    } on PayablesServiceException catch (error) {
      _loadError = error.message;
    } finally {
      notifyListeners();
    }
  }

  /// Drops a refusal so a reopened dialog starts clean.
  void clearPayError() {
    if (_payError == null) return;
    _payError = null;
    notifyListeners();
  }

  /// `YYYY-MM-DD`: a `DateField` server-side rejects a timestamp, and a cheque
  /// date with a timezone on it is a date nobody wrote.
  static String _isoDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
