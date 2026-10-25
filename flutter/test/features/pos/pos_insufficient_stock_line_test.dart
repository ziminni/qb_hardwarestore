// Decision 06 section 3 requires insufficient stock to be treated as RECOVERABLE IN
// PLACE - "identify the offending line, let the cashier reduce the quantity, keep the
// cart intact" - and to be distinguishable from a terminal 5xx.
//
// This was the final-review gap. The cart-keeping half was right, but nothing in the UI
// acted on the distinction: `isInsufficientStock` was referenced by nothing outside its
// own definition, the viewmodel discarded it (`_submitError = error.message;`), and a
// stock rejection and a 500 produced the identical SnackBar. The server could not even
// be asked which line: the DRF handler held `InsufficientStock.variant_id` but never
// published it. That key is now in the 400 body, so the cart can point AT the row.

import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import '../../support/phase4_fakes.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what was sent and throws whatever it is told to.
class _StubPosRepository extends PosRepository {
  _StubPosRepository() : super(PosService());

  PosServiceException? failure;

  // `submit` resolves the Walk-in Customer BEFORE it checks out, so a stub that only
  // overrides `checkout` still reaches the real service and dies on the uninitialised
  // `ApiClient.dio`. Same reason the harness rule exists for `setUpAll(init())`.
  @override
  Future<int> walkInCustomerId() async => 1;

  @override
  Future<PosCheckoutResult> checkout({
    required int customerId,
    required List<PosCheckoutItem> items,
    required List<PosCheckoutPayment> payments,
    String source = 'WALK_IN',
    String? idempotencyKey,
  }) async {
    final boom = failure;
    if (boom != null) throw boom;
    return PosCheckoutResult(
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
  late _StubPosRepository repository;
  late PosTransactionViewmodel cart;

  setUp(() {
    inventory = seededInventory();
    repository = _StubPosRepository();
    cart = PosTransactionViewmodel(
      inventory,
      ProductTrackingViewmodel(),
      pos: repository,
    );
  });

  /// Adds the first sellable line and reports its id plus the VARIANT the server
  /// would name in a short-stock rejection.
  ({int lineId, int variantId}) addFirstLine() {
    final item = cart.filteredProducts.first;
    final option = cart.saleOptionsFor(item).first;
    expect(cart.addLine(option, 1), isNull);
    return (lineId: option.variantUomId, variantId: option.variantId);
  }

  test('a stock rejection names the cart line the cashier must fix', () async {
    final line = addFirstLine();
    // The server names the VARIANT; the cart is keyed by the VariantUom, so the
    // viewmodel must map one onto the other rather than guessing.
    repository.failure = PosServiceException(
      'Insufficient stock for Portland Cement — 40kg.',
      code: 'INSUFFICIENT_STOCK',
      shortfall: 1,
      variantId: line.variantId,
    );

    final confirmed = await cart.submit(
      method: TenderMethod.cash,
      amountPaid: 1,
    );

    expect(confirmed, isFalse);
    expect(
      cart.insufficientStockLineId,
      line.lineId,
      reason: 'without this the cashier is only told a sentence, not which row',
    );
  });

  test('a terminal failure does NOT claim to name a line', () async {
    addFirstLine();
    repository.failure = PosServiceException('The server broke.');

    await cart.submit(method: TenderMethod.cash, amountPaid: 1);

    expect(
      cart.insufficientStockLineId,
      isNull,
      reason:
          'a 500 is terminal - pointing at a row would blame the wrong thing',
    );
  });

  test('the marker clears on the next attempt', () async {
    final line = addFirstLine();
    repository.failure = PosServiceException(
      'short',
      code: 'INSUFFICIENT_STOCK',
      variantId: line.variantId,
    );
    await cart.submit(method: TenderMethod.cash, amountPaid: 1);
    expect(cart.insufficientStockLineId, line.lineId);

    repository.failure = PosServiceException('The server broke.');
    await cart.submit(method: TenderMethod.cash, amountPaid: 1);

    expect(
      cart.insufficientStockLineId,
      isNull,
      reason:
          'a stale marker would point at a line during an unrelated failure',
    );
  });

  test('a successful sale leaves no marker behind', () async {
    addFirstLine();

    final confirmed = await cart.submit(
      method: TenderMethod.cash,
      amountPaid: 100,
    );

    expect(confirmed, isTrue);
    expect(cart.insufficientStockLineId, isNull);
  });

  test(
    'a stock rejection the cart cannot map still reports no line, not a wrong one',
    () async {
      addFirstLine();
      // A variant id that matches no line in the cart: better to say nothing than to
      // point the cashier at an innocent row.
      repository.failure = PosServiceException(
        'short',
        code: 'INSUFFICIENT_STOCK',
        variantId: 999999,
      );

      await cart.submit(method: TenderMethod.cash, amountPaid: 1);

      expect(cart.insufficientStockLineId, isNull);
    },
  );
}
