// Phase 1 Task 6 (audit remediation): the checkout ATTEMPT key.
//
// `POST /api/v1/transactions/` accepts an optional `Idempotency-Key`. The server
// answers a repeat of the same key + same body with **200** and the ORIGINAL
// transaction, which is the only thing standing between a dropped response and a
// second, real sale. But that guarantee exists only if the client's key means the
// right thing:
//
//   * A RETRY of the same attempt must carry the SAME key — otherwise the server
//     sees two different sales.
//   * A NEW attempt must carry a NEW key — otherwise the server replays the old
//     sale and the second customer walks out with the first customer's receipt.
//   * A changed cart or a changed customer is a NEW attempt, so the key is
//     dropped: the body no longer matches, and reusing the key would earn a 409
//     `IDEMPOTENCY_KEY_REUSED` instead of ringing the corrected sale.
//
// The key therefore lives on the viewmodel, is created on first submit and cleared
// on success — never in the view, which is rebuilt freely.

import 'package:client/data/models/customer.dart';
import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingPosRepository extends PosRepository {
  _RecordingPosRepository() : super(PosService());

  final List<String?> sentKeys = [];
  PosServiceException? failure;
  List<PosCheckoutLine> serverLines = const [];

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
    sentKeys.add(idempotencyKey);
    final boom = failure;
    if (boom != null) throw boom;
    return PosCheckoutResult(
      id: 18,
      transactionNo: 'TRX-20261016-0007',
      orNumber: 'OR-20261016-0007',
      transDate: DateTime(2026, 10, 16, 18, 56),
      grandTotal: 20,
      lines: serverLines,
    );
  }
}

void main() {
  late InventoryViewmodel inventory;
  late _RecordingPosRepository repository;
  late PosTransactionViewmodel cart;

  setUp(() {
    inventory = InventoryViewmodel();
    repository = _RecordingPosRepository();
    cart = PosTransactionViewmodel(
      inventory,
      ProductTrackingViewmodel(),
      pos: repository,
    );
  });

  void addOne() {
    final product = cart.filteredProducts.first;
    final option = cart.saleOptionsFor(product).first;
    expect(cart.addLine(option, 2), isNull);
  }

  Future<bool> submit() => cart.submit(paymentMethod: 'CASH', amountPaid: 20);

  test('a payment attempt is sent under a 32-hex-character key', () async {
    addOne();
    await submit();

    final key = repository.sentKeys.single;
    expect(key, isNotNull);
    expect(
      RegExp(r'^[0-9a-f]{32}$').hasMatch(key!),
      isTrue,
      reason:
          'Random.secure() hex: no dashes, 32 chars, well under the '
          'server\'s 64-char cap',
    );
  });

  test('a retry after a failure REUSES the key', () async {
    addOne();
    repository.failure = const PosServiceException('Server unreachable.');

    expect(await submit(), isFalse);
    // The cashier presses Pay again: same basket, same attempt.
    repository.failure = null;
    expect(await submit(), isTrue);

    expect(repository.sentKeys, hasLength(2));
    expect(
      repository.sentKeys[1],
      repository.sentKeys[0],
      reason: 'a new key here would ring a SECOND sale for one basket',
    );
  });

  test('a sale after a success uses a NEW key', () async {
    addOne();
    expect(await submit(), isTrue);

    // A second customer, a second basket.
    addOne();
    expect(await submit(), isTrue);

    expect(repository.sentKeys, hasLength(2));
    expect(
      repository.sentKeys[1],
      isNot(repository.sentKeys[0]),
      reason:
          'reusing it would replay the first sale instead of ringing this '
          'one',
    );
  });

  test('changing the cart DROPS the key, so a corrected sale is new', () async {
    addOne();
    repository.failure = const PosServiceException('Server unreachable.');
    expect(await submit(), isFalse);
    final firstKey = repository.sentKeys.single;

    // The cashier removes a line to fix the basket: different body, so the key
    // must go or the server answers 409 instead of ringing the sale.
    cart.removeLine(0);
    addOne();
    repository.failure = null;
    expect(await submit(), isTrue);

    expect(repository.sentKeys.last, isNot(firstKey));
  });

  test('clearing the cart DROPS the key', () async {
    addOne();
    repository.failure = const PosServiceException('Server unreachable.');
    expect(await submit(), isFalse);
    final firstKey = repository.sentKeys.single;

    cart.clear();
    addOne();
    repository.failure = null;
    expect(await submit(), isTrue);

    expect(repository.sentKeys.last, isNot(firstKey));
  });

  test('changing the customer DROPS the key', () async {
    addOne();
    cart.selectCustomer(
      const Customer(id: 2, name: 'Maria Santos', customerType: 'REGULAR'),
    );
    repository.failure = const PosServiceException('Server unreachable.');
    expect(await submit(), isFalse);
    final firstKey = repository.sentKeys.single;

    // Same basket, different buyer: the body changed.
    cart.selectCustomer(
      const Customer(id: 3, name: 'Juan Dela Cruz', customerType: 'REGULAR'),
    );
    repository.failure = null;
    expect(await submit(), isTrue);

    expect(repository.sentKeys.last, isNot(firstKey));
  });

  test('the receipt prints the SERVER line prices', () async {
    addOne();
    // The server ignores the client's preview price and prices from
    // VariantUOM.default_selling_price, so the cart here says 2 x 10 = 20 while
    // the server wrote 2 x 12.50.
    repository.serverLines = const [
      PosCheckoutLine(
        variantUomId: 1,
        quantity: 2,
        unitPrice: 12.5,
        subtotal: 25,
      ),
    ];

    expect(await submit(), isTrue);

    final line = cart.receipts.first.lines.single;
    expect(line.unitPrice, 12.5, reason: 'not the cart\'s 10.00');
    expect(line.total, 25, reason: 'not the cart\'s 20.00');
    expect(
      line.productName,
      isNotEmpty,
      reason: 'the response carries no names, so the cart supplies them',
    );
  });
}
