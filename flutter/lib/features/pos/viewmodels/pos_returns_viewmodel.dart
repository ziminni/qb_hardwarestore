import 'dart:math' as math;

import 'package:client/data/models/returns.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/repositories/returns_repository.dart';
import 'package:client/data/services/returns_service.dart';
import 'package:flutter/foundation.dart';

/// The till's Returns tab (decision 05, Phase 3).
///
/// The flow is fixed by the server's contract, and each step below is a guard
/// that must exist BELOW the widget, because a widget test cannot be the thing
/// that stops a refund:
///
/// 1. **Search** the original sale by transaction or receipt number. A miss is
///    an ordinary answer (the server's `?q=` is scoped to the caller, so another
///    till's number is simply "not yours"), never a stale row left on screen.
/// 2. **Pre-flight** through `returnable/`: what is left per selling unit. The
///    stepper caps at `remaining_qty`, so the screen cannot even offer an amount
///    the server would refuse with `RETURN_QTY_EXCEEDED`.
/// 3. **Reason** is mandatory, and it is checked HERE before the POST: the
///    server refuses a reasonless return with `RETURN_REASON_REQUIRED`, and a
///    cashier should be told before the round trip, not after it.
/// 4. **Refund method** defaults to Cash — the drawer the Z-reading counts.
/// 5. **Confirm** shows return value, debt reduced and the cash refund ESTIMATE.
///    The posted `refund_summary` then REPLACES that estimate: the client's
///    arithmetic is a preview and must never be printed as the ledger's answer.
///
/// The customer sent on the POST is the ORIGINAL sale's customer, taken from the
/// searched [TransactionRecord] — the `returnable/` payload names the customer
/// but carries no id, and refunding against the wrong person would settle the
/// wrong utang.
class PosReturnsViewmodel extends ChangeNotifier {
  PosReturnsViewmodel({ReturnsRepository? repository})
    : _repository = repository ?? ReturnsRepository();

  final ReturnsRepository _repository;

  /// Methods the server accepts on a refund (`Payment.Method`). Cash first, and
  /// the default: only cash moves the expected drawer.
  static const List<String> refundMethods = [
    'CASH',
    'CARD',
    'GCASH',
    'BANK_TRANSFER',
  ];

  // ---- search state -------------------------------------------------------

  bool isSearching = false;

  /// Why the last search failed (transport, permission, unreadable body).
  String? searchError;

  /// True when the server answered with NO row: a miss, which the screen states
  /// plainly instead of leaving the previous sale on it.
  bool searchedMiss = false;

  /// The original sale's own row — the source of `original_transaction` and the
  /// customer id the POST must carry.
  TransactionRecord? sale;
  TransactionRecord? get foundSale => sale;

  /// What is left to return, from `returnable/`.
  ReturnableSale? preflight;

  /// Why the pre-flight failed, when it did.
  String? preflightError;

  final Map<int, double> _quantities = {};

  String _reason = '';

  /// The reason for the return. Empty until the cashier types one; the server
  /// requires one and this viewmodel refuses to submit without it.
  String get reason => _reason;

  String _refundMethod = refundMethods.first;

  /// Which method the EXCESS is refunded in (`CASH` by default).
  String get refundMethod => _refundMethod;

  // ---- submit state -------------------------------------------------------

  bool isSubmitting = false;

  /// Why the last submit failed, in words a cashier can act on.
  String? submitError;

  /// True when the last refusal was `NO_OPEN_SHIFT`: the screen then offers the
  /// Shifts tab instead of a retry that cannot work.
  bool needsOpenShift = false;

  /// The posted return, once the server accepted it.
  ReturnResult? result;

  // ---- derived ------------------------------------------------------------

  /// How much of [variantUomId] the cashier chose.
  double quantityFor(int variantUomId) => _quantities[variantUomId] ?? 0;

  /// The lines that will actually be sent: chosen quantity above zero.
  List<ReturnRequestLine> get lines => [
    for (final line in preflight?.lines ?? const <ReturnableLine>[])
      if (quantityFor(line.variantUomId) > 0)
        ReturnRequestLine(
          variantUomId: line.variantUomId,
          qty: quantityFor(line.variantUomId),
        ),
  ];

  bool get hasQuantity => lines.isNotEmpty;

  /// The return's value at the ORIGINAL sale's prices — a PREVIEW.
  double get returnValue {
    var total = 0.0;
    for (final line in preflight?.lines ?? const <ReturnableLine>[]) {
      total += line.valueOf(quantityFor(line.variantUomId));
    }
    return total;
  }

  /// What the sale's utang absorbs first (decision 05: debt before drawer).
  double get debtReducedEstimate =>
      math.min(returnValue, preflight?.openDebt ?? 0);

  /// What would actually leave the drawer: only the excess.
  double get cashRefundEstimate => returnValue - debtReducedEstimate;

  /// The server already said this sale cannot be returned (`RETURN_OF_RETURN`,
  /// `RELEASE_NOT_RETURNABLE`, `ORIGINAL_NOT_COMPLETED`).
  bool get isRefusedByServer => preflight != null && !preflight!.returnable;

  /// Clerk-readable reason the sale cannot be returned, or null.
  String? get refusalMessage =>
      preflight?.notReturnableMessage ??
      (preflight?.reasonIfNot ?? 'This sale cannot be returned at the till.');

  /// True only when a POST would be a real, complete return: the server said
  /// yes, some quantity is chosen, and a reason is written.
  bool get canSubmit =>
      !isSubmitting &&
      result == null &&
      preflight != null &&
      preflight!.returnable &&
      hasQuantity &&
      _reason.trim().isNotEmpty;

  // ---- actions ------------------------------------------------------------

  /// Looks the original sale up by transaction number or OR number.
  ///
  /// Clears the previous sale FIRST: a failed or empty search must not leave the
  /// last customer's sale on screen to be refunded by mistake.
  Future<void> search(String query) async {
    final trimmed = query.trim();
    _resetSelection();
    if (trimmed.isEmpty) {
      searchError = 'Enter the transaction or receipt number to search for.';
      notifyListeners();
      return;
    }

    isSearching = true;
    searchError = null;
    searchedMiss = false;
    notifyListeners();

    try {
      final found = await _repository.findSale(trimmed);
      if (found == null) {
        searchedMiss = true;
        return;
      }
      sale = found;
      await _loadPreflight(found.id);
    } on ReturnsServiceException catch (failure) {
      searchError = failure.message;
    } finally {
      isSearching = false;
      notifyListeners();
    }
  }

  /// The pre-flight for the sale already found. Kept separate so a Retry can
  /// re-read the quantities without re-searching.
  Future<void> reloadPreflight() async {
    final found = sale;
    if (found == null) return;
    preflightError = null;
    notifyListeners();
    try {
      await _loadPreflight(found.id);
    } on ReturnsServiceException catch (failure) {
      preflightError = failure.message;
    }
    notifyListeners();
  }

  Future<void> _loadPreflight(int transactionId) async {
    preflight = await _repository.fetchReturnable(transactionId);
    _quantities.clear();
  }

  /// Sets how much of one selling unit comes back, CAPPED at what is left.
  ///
  /// The cap lives here rather than in the stepper's `max`: a screen that could
  /// hold a larger number would send a request the server refuses
  /// (`RETURN_QTY_EXCEEDED`), which reads as the till being broken instead of
  /// the quantity being wrong.
  void setQuantity(int variantUomId, double qty) {
    final line = _lineFor(variantUomId);
    if (line == null) return;
    final capped = line.cappedQty(qty);
    if (capped <= 0) {
      _quantities.remove(variantUomId);
    } else {
      _quantities[variantUomId] = capped;
    }
    notifyListeners();
  }

  /// One more of [variantUomId], still capped.
  void increment(int variantUomId) =>
      setQuantity(variantUomId, quantityFor(variantUomId) + 1);

  /// One fewer, never below zero.
  void decrement(int variantUomId) =>
      setQuantity(variantUomId, quantityFor(variantUomId) - 1);

  void setReason(String value) {
    _reason = value;
    notifyListeners();
  }

  void setRefundMethod(String method) {
    if (!refundMethods.contains(method)) return;
    _refundMethod = method;
    notifyListeners();
  }

  /// Posts the return. Returns true only when the server accepted it.
  ///
  /// Every client-side refusal sets [submitError] and sends NOTHING: a return is
  /// money out of a drawer, so an incomplete form must not reach the server and
  /// come back as a refusal the cashier reads as a bug.
  Future<bool> submit() async {
    submitError = null;
    final found = sale;
    final checked = preflight;
    if (found == null || checked == null) {
      submitError = 'Search for the original sale first.';
      notifyListeners();
      return false;
    }
    if (!checked.returnable) {
      submitError = refusalMessage;
      notifyListeners();
      return false;
    }
    if (!hasQuantity) {
      submitError = 'Choose at least one quantity to return.';
      notifyListeners();
      return false;
    }
    if (_reason.trim().isEmpty) {
      submitError =
          'A return needs a reason before it can be posted: say why the '
          'customer brought the goods back.';
      notifyListeners();
      return false;
    }

    isSubmitting = true;
    needsOpenShift = false;
    notifyListeners();
    try {
      result = await _repository.postReturn(
        customerId: found.customerId,
        originalTransactionId: found.id,
        reason: _reason,
        paymentMethod: _refundMethod,
        lines: lines,
      );
      return true;
    } on ReturnsServiceException catch (failure) {
      submitError = failure.message;
      needsOpenShift = failure.needsOpenShift;
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  /// Starts the next return: clears the sale, the quantities and the result.
  void reset() {
    _resetSelection();
    _reason = '';
    _refundMethod = refundMethods.first;
    submitError = null;
    needsOpenShift = false;
    notifyListeners();
  }

  void _resetSelection() {
    sale = null;
    preflight = null;
    preflightError = null;
    searchError = null;
    searchedMiss = false;
    result = null;
    submitError = null;
    needsOpenShift = false;
    _quantities.clear();
  }

  ReturnableLine? _lineFor(int variantUomId) {
    for (final line in preflight?.lines ?? const <ReturnableLine>[]) {
      if (line.variantUomId == variantUomId) return line;
    }
    return null;
  }
}
