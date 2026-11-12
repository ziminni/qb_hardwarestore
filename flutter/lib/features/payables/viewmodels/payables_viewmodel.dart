import 'package:client/data/models/supplier_payables.dart';
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
  Future<String?> pay({
    required SupplierBill bill,
    required double amount,
    required SupplierPaymentMethod method,
    String reference = '',
    String? chequeNumber,
    String? chequeBank,
    DateTime? chequeDate,
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
      });
    } on PayablesServiceException catch (error) {
      _payError = error.message;
      return error.message;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }

    await _refreshAfterPayment(bill.id);
    return null;
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
