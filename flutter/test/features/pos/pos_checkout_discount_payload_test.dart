// Phase 4 Task F4 (decision 18): what the till SENDS for a discounted sale.
//
// The wire shape is `"discount": {"kind", "value", "reason"}` plus, above the cap,
// `"discount_approval": "<token>"`. Getting this wrong is not a display bug: the
// server refuses an approval-less over-cap discount (DISCOUNT_OVER_CAP) and treats a
// malformed discount as INVALID_DISCOUNT, so the sale never happens.

import 'package:client/data/models/sale_discount.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

class _RecordingPosRepository extends PosRepository {
  _RecordingPosRepository() : super(PosService());

  PosDiscount? lastDiscount;
  String? lastApproval;
  List<PosCheckoutPayment> lastPayments = const [];

  /// Set to throw on the next checkout, the way the server refuses a discount.
  PosServiceException? failure;

  @override
  Future<int> walkInCustomerId() async => 1;

  @override
  Future<PosCheckoutResult> checkout({
    required int customerId,
    required List<PosCheckoutItem> items,
    required List<PosCheckoutPayment> payments,
    String source = 'WALK_IN',
    String? idempotencyKey,
    PosDiscount? discount,
    String? discountApproval,
  }) async {
    lastDiscount = discount;
    lastApproval = discountApproval;
    lastPayments = payments;
    final boom = failure;
    if (boom != null) throw boom;
    return PosCheckoutResult(
      id: 7,
      transactionNo: 'TRX-20261111-0007',
      orNumber: 'OR-20261111-0007',
      transDate: DateTime(2026, 11, 11, 10),
      grandTotal: 850,
      discountAmount: 150,
      discountReason: discount?.reason ?? '',
      vatableSales: 758.93,
      vatAmount: 91.07,
      vatRegistered: true,
    );
  }
}

void main() {
  late InventoryViewmodel inventory;
  late _RecordingPosRepository repository;
  late PosTransactionViewmodel cart;

  setUp(() {
    inventory = seededInventory();
    repository = _RecordingPosRepository();
    cart = PosTransactionViewmodel(inventory, pos: repository);
  });

  void addOne() {
    final product = cart.filteredProducts.first;
    final option = cart.saleOptionsFor(product).first;
    expect(cart.addLine(option, 2), isNull);
  }

  test('a discounted sale sends the discount and nothing else', () async {
    addOne();

    final confirmed = await cart.submit(
      method: TenderMethod.cash,
      amountPaid: 850,
      discount: const PosDiscount(
        kind: DiscountKind.amount,
        value: 150,
        reason: 'bulk order',
      ),
    );

    expect(confirmed, isTrue);
    expect(repository.lastDiscount?.kind, DiscountKind.amount);
    expect(repository.lastDiscount?.value, 150);
    expect(repository.lastDiscount?.reason, 'bulk order');
    expect(
      repository.lastApproval,
      isNull,
      reason: 'no token is sent when no approval was needed',
    );
  });

  test('an approved discount also sends its one-time token', () async {
    addOne();

    await cart.submit(
      method: TenderMethod.cash,
      amountPaid: 850,
      discount: const PosDiscount(
        kind: DiscountKind.percent,
        value: 15,
        reason: 'loyal customer',
      ),
      discountApprovalToken: 'TOKEN-ABC',
    );

    expect(repository.lastDiscount?.kind, DiscountKind.percent);
    expect(repository.lastApproval, 'TOKEN-ABC');
  });

  test('a sale with no discount sends no discount key at all', () async {
    addOne();

    await cart.submit(method: TenderMethod.cash, amountPaid: 20);

    expect(
      repository.lastDiscount,
      isNull,
      reason: 'an absent discount is not the same as a zero one',
    );
    expect(repository.lastApproval, isNull);
  });

  test('the receipt carries the server discount and VAT numbers', () async {
    addOne();

    await cart.submit(
      method: TenderMethod.cash,
      amountPaid: 850,
      discount: const PosDiscount(
        kind: DiscountKind.amount,
        value: 150,
        reason: 'bulk order',
      ),
      vatRate: 12,
    );

    final receipt = cart.receipts.first;
    expect(receipt.total, 850, reason: 'the server grand total is the NET');
    expect(receipt.discountAmount, 150);
    expect(receipt.discountReason, 'bulk order');
    expect(receipt.vatableSales, 758.93);
    expect(receipt.vatAmount, 91.07);
    expect(receipt.vatRegistered, isTrue);
    expect(receipt.vatRate, 12);
    // Change comes from the server (`change_given`), which saw the net.
    expect(receipt.changeGiven, 0);
  });

  test('a refused discount keeps the cart and exposes the code', () async {
    addOne();
    repository.failure = const PosServiceException(
      'This discount is above the cashier cap.',
      code: 'DISCOUNT_OVER_CAP',
    );

    final confirmed = await cart.submit(
      method: TenderMethod.cash,
      amountPaid: 850,
      discount: const PosDiscount(
        kind: DiscountKind.amount,
        value: 150,
        reason: 'bulk order',
      ),
    );

    expect(confirmed, isFalse);
    expect(
      cart.lines,
      isNotEmpty,
      reason: 'a refused sale rolled back; the basket must survive',
    );
    expect(cart.receipts, isEmpty);
    // The page needs the code to decide whether to ask the manager again.
    expect(cart.submitErrorCode, 'DISCOUNT_OVER_CAP');
  });
}
