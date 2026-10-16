// Phase 3 Task 4 (decision 06, sections 3 and 5): the submit path.
//
// The contract this file pins is almost entirely about what happens on FAILURE, which
// is where a POS goes wrong expensively:
//
//   * The cart is cleared ONLY after a successful sale. `process_sale` runs inside one
//     `transaction.atomic()`, so a failure rolls back wholesale - the server state is
//     unchanged and the cashier's basket must survive so they can fix and retry.
//   * Insufficient stock is recoverable in place: the cart stays, the message says
//     what happened.
//   * A 5xx is a different thing and must not be reported as a stock problem.
//   * An empty cart is never submitted: the server has no guard on an empty items
//     list and would happily mint a zero-value receipt.

import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePosRepository extends PosRepository {
  _FakePosRepository() : super(PosService());

  int calls = 0;
  PosServiceException? failure;
  PosCheckoutResult? result;
  List<PosCheckoutItem> sentItems = const [];
  List<PosCheckoutPayment> sentPayments = const [];
  int? sentCustomerId;

  @override
  Future<PosCheckoutResult> checkout({
    required int customerId,
    required List<PosCheckoutItem> items,
    required List<PosCheckoutPayment> payments,
    String source = 'WALK_IN',
  }) async {
    calls++;
    sentCustomerId = customerId;
    sentItems = items;
    sentPayments = payments;
    final boom = failure;
    if (boom != null) throw boom;
    return result ??
        PosCheckoutResult(
          id: 18,
          transactionNo: 'TRX-20261016-0007',
          orNumber: 'OR-20261016-0007',
          transDate: DateTime(2026, 10, 16, 18, 56),
          grandTotal: 20,
        );
  }
}

void main() {
  late InventoryViewmodel inventory;
  late _FakePosRepository repository;
  late PosTransactionViewmodel cart;

  setUp(() {
    inventory = InventoryViewmodel();
    repository = _FakePosRepository();
    cart = PosTransactionViewmodel(
      inventory,
      ProductTrackingViewmodel(),
      pos: repository,
    );
  });

  /// Put one real catalogue line in the cart.
  void addOne() {
    final product = cart.filteredProducts.first;
    final option = cart.saleOptionsFor(product).first;
    expect(cart.addLine(option, 2), isNull);
  }

  Future<bool> submit() =>
      cart.submit(customerId: 2, paymentMethod: 'CASH', amountPaid: 20);

  test(
    'a confirmed sale clears the cart and carries the SERVER numbers',
    () async {
      addOne();
      final lines = cart.lines.length;
      expect(lines, 1);

      expect(await submit(), isTrue);

      expect(cart.lines, isEmpty, reason: 'cleared only after a 201');
      final receipt = cart.receipts.first;
      expect(receipt.reference, 'TRX-20261016-0007');
      expect(receipt.officialReceiptNumber, 'OR-20261016-0007');
      expect(receipt.total, 20);
      expect(cart.submitError, isNull);
      expect(cart.isSubmitting, isFalse);
    },
  );

  test('sends the real selling-unit ids and the chosen customer', () async {
    addOne();
    await submit();

    expect(repository.sentCustomerId, 2);
    expect(repository.sentItems, hasLength(1));
    expect(
      repository.sentItems.single.variantUomId,
      cart.receipts.first.lines.single.variantUomId,
    );
    expect(repository.sentPayments.single.method, 'CASH');
    expect(repository.sentPayments.single.amountTendered, 20);
  });

  test('insufficient stock keeps the cart, and says so', () async {
    addOne();
    repository.failure = const PosServiceException(
      'Insufficient stock for Portland Cement — 40kg.',
      code: 'INSUFFICIENT_STOCK',
      shortfall: 1,
    );

    expect(await submit(), isFalse);

    expect(
      cart.lines,
      hasLength(1),
      reason: 'a rejected sale must leave the basket intact so it can be fixed',
    );
    expect(cart.receipts, isEmpty);
    expect(cart.submitError, contains('Insufficient stock'));
    expect(cart.isSubmitting, isFalse);
  });

  test(
    'a server failure keeps the cart and is NOT called a stock problem',
    () async {
      addOne();
      repository.failure = const PosServiceException('Try again.');

      expect(await submit(), isFalse);

      expect(cart.lines, hasLength(1));
      expect(cart.receipts, isEmpty);
      expect(cart.submitError, 'Try again.');
    },
  );

  test('never submits an empty cart', () async {
    // The server has no empty-items guard: an empty sale would succeed and mint a
    // zero-value receipt.
    expect(await submit(), isFalse);
    expect(repository.calls, 0);
  });

  test('isSubmitting is true while the sale is in flight', () async {
    addOne();
    final states = <bool>[];
    cart.addListener(() => states.add(cart.isSubmitting));

    await submit();

    expect(
      states,
      contains(true),
      reason: 'submit must disable itself in flight',
    );
    expect(states.last, isFalse);
  });
}
