import 'package:client/data/models/held_cart.dart';
import 'package:client/data/services/held_cart_service.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:flutter/foundation.dart';

/// The parked-cart queue behind the POS "Held transactions" tab (Phase 3).
///
/// A held cart is a basket the cashier walked away from — nothing has been
/// deducted, no sale exists, no money has moved. Two rules live here rather than
/// in the widget, because both are about what the SERVER holds:
///
/// * **A failed reload keeps the carts already shown.** An empty queue reads as
///   "nothing was held", so a cashier would re-ring a basket that is still
///   parked — and the customer would be charged twice.
/// * **A failed void keeps its row.** The basket is still on the server, so
///   hiding it would strand a customer's items with nothing pointing at them.
class HeldCartViewmodel extends ChangeNotifier {
  HeldCartViewmodel({HeldCartService? service})
    : _service = service ?? HeldCartService();

  final HeldCartService _service;

  List<HeldCart> _carts = const [];
  List<HeldCart> get carts => _carts;

  bool isLoading = false;

  /// Why the last load failed, or null. Kept alongside the carts so the page can
  /// show a banner over rows that are still valid.
  String? loadError;

  /// Why the last hold/void/complete failed, or null. Separate from
  /// [loadError] because it is about one row, not about the whole list.
  String? actionError;

  bool get hasCarts => _carts.isNotEmpty;

  /// The basket the held-transactions tab has asked the till to pick back up.
  ///
  /// A parked basket lives on the server, so "resume" is two steps that happen
  /// on two screens: the row records the hand-off here, then navigates, and the
  /// till consumes it on open. Put on the shared viewmodel rather than passed
  /// through the route so both screens read one value with one meaning — and so
  /// a resumed basket cannot be re-loaded by a rebuild.
  HeldCart? _pendingResume;
  HeldCart? get pendingResume => _pendingResume;

  /// Hands [cart] to the till. The caller navigates immediately after.
  void resumeCart(HeldCart cart) {
    _pendingResume = cart;
    notifyListeners();
  }

  /// Takes the pending basket, or null when there is none.
  ///
  /// Consuming it is deliberate: it is a one-shot hand-off, not a state the UI
  /// renders. Leaving it set would re-fill the till on every rebuild that
  /// re-runs the read, resurrecting a basket the cashier may since have paid for.
  ///
  /// No [notifyListeners] here — nothing on screen displays this value; the till
  /// immediately renders the basket itself.
  HeldCart? takePendingResume() {
    final cart = _pendingResume;
    _pendingResume = null;
    return cart;
  }

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    try {
      _carts = await _service.fetchAll();
      loadError = null;
    } on HeldCartServiceException catch (failure) {
      // Deliberately NOT `_carts = []`: see the class comment.
      loadError = failure.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Parks a basket and puts it at the top of the queue.
  ///
  /// Returns the created cart on success, or null after setting [actionError].
  /// The queue is updated from the server's own copy rather than an optimistic
  /// guess, because the id is what Void and Resume act on.
  Future<HeldCart?> holdCart({
    int? customerId,
    String notes = '',
    required List<HeldCartItem> items,
  }) async {
    actionError = null;
    try {
      final held = await _service.hold(
        customerId: customerId,
        notes: notes,
        items: items,
      );
      _carts = [held, ..._carts];
      notifyListeners();
      return held;
    } on HeldCartServiceException catch (failure) {
      actionError = failure.message;
      notifyListeners();
      return null;
    }
  }

  /// Discards a parked basket. Irreversible, so the page confirms first.
  Future<bool> voidCart(int cartId) async {
    actionError = null;
    try {
      await _service.voidCart(cartId);
      _carts = _carts.where((cart) => cart.id != cartId).toList(growable: false);
      notifyListeners();
      return true;
    } on HeldCartServiceException catch (failure) {
      actionError = failure.message;
      notifyListeners();
      return false;
    }
  }

  /// Sells a parked basket through the server's `complete` action.
  ///
  /// Returns the written sale, or null after setting [actionError]. The cart is
  /// removed only on success: the server deletes it inside the same
  /// transaction that writes the sale, so a failed call means it still exists.
  Future<Map<String, dynamic>?> completeCart(
    int cartId, {
    required List<PosCheckoutPayment> payments,
  }) async {
    actionError = null;
    try {
      final sale = await _service.complete(cartId, payments: payments);
      _carts = _carts.where((cart) => cart.id != cartId).toList(growable: false);
      notifyListeners();
      return sale;
    } on HeldCartServiceException catch (failure) {
      actionError = failure.message;
      notifyListeners();
      return null;
    }
  }
}
