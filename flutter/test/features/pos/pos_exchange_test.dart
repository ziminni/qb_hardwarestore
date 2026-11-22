import 'package:client/data/models/returns.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/repositories/returns_repository.dart';
import 'package:client/features/pos/viewmodels/pos_returns_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeReturnsRepository extends ReturnsRepository {
  ReturnRequestLine? lastReturnLine;
  ReturnRequestLine? lastReplacementLine;
  double? lastTendered;
  bool postedReturn = false;

  @override
  Future<TransactionRecord?> findSale(String query) async => TransactionRecord(
    id: 42,
    transactionNo: 'TRX-42',
    orNumber: 'OS-42',
    transDate: DateTime(2026, 11, 22),
    customerId: 7,
    customerName: 'Juan Dela Cruz',
    cashierName: 'Cashier',
    source: 'WALK_IN',
    status: 'COMPLETED',
    grandTotal: 200,
    originalTransactionId: null,
    items: const [],
    payments: const [],
  );

  @override
  Future<ReturnableSale> fetchReturnable(int transactionId) async =>
      const ReturnableSale(
        transactionNo: 'TRX-42',
        customer: 'Juan Dela Cruz',
        source: 'WALK_IN',
        returnable: true,
        reasonIfNot: null,
        openDebt: 30,
        lines: [
          ReturnableLine(
            variantUomId: 1,
            name: 'Paint 1L',
            uom: 'CAN',
            soldQty: 2,
            returnedQty: 0,
            remainingQty: 2,
            unitPrice: 100,
          ),
        ],
      );

  @override
  Future<ExchangeResult> postExchange({
    required int customerId,
    required int originalTransactionId,
    required String reason,
    required List<ReturnRequestLine> returnLines,
    required List<ReturnRequestLine> replacementLines,
    String paymentMethod = 'CASH',
    double? amountTendered,
  }) async {
    lastReturnLine = returnLines.first;
    lastReplacementLine = replacementLines.first;
    lastTendered = amountTendered;
    return const ExchangeResult(
      exchangeNo: 'TRX-99',
      summary: ExchangeSummary(
        returnCredit: 100,
        replacementTotal: 150,
        netDifference: 50,
        extraPaid: 100,
        changeGiven: 50,
        paymentMethod: 'CASH',
        debtReduced: 0,
        storeCreditIssued: 0,
        customerStoreCreditBalance: 0,
        ledgerId: null,
        ledgerBalance: null,
      ),
    );
  }

  @override
  Future<ReturnResult> postReturn({
    required int customerId,
    required int originalTransactionId,
    required String reason,
    required String paymentMethod,
    required List<ReturnRequestLine> lines,
  }) async {
    postedReturn = true;
    return const ReturnResult(
      returnNo: 'TRX-100',
      refund: RefundSummary(
        returnValue: 100,
        debtReduced: 30,
        cashRefund: 70,
        refundMethod: 'CASH',
        ledgerId: 1,
        ledgerBalance: 0,
      ),
    );
  }
}

void main() {
  test('exchange mode defaults first and computes extra pay vs cheaper swap credit', () async {
    final repo = _FakeReturnsRepository();
    final vm = PosReturnsViewmodel(repository: repo);
    expect(vm.mode, ReturnMode.exchange);

    await vm.search('OS-42');
    vm.setQuantity(1, 1); // 100.00 return credit
    vm.setReason('Wrong color');
    // Cannot submit exchange without replacement item.
    expect(vm.canSubmit, isFalse);

    // Cheaper replacement (60.00) -> 40.00 excess: 30.00 reduces utang, 10.00 store credit.
    vm.addReplacement(
      const ExchangeReplacementLine(
        variantUomId: 2,
        name: 'Small Brush',
        uom: 'PC',
        unitPrice: 60,
        qty: 1,
      ),
    );
    expect(vm.exchangeDifference, -40);
    expect(vm.exchangeDebtReducedEstimate, 30);
    expect(vm.exchangeStoreCreditEstimate, 10);
    expect(vm.canSubmit, isTrue);

    // Swap to more expensive replacement (150.00) -> customer pays 50.00 extra.
    vm.removeReplacement(2);
    vm.addReplacement(
      const ExchangeReplacementLine(
        variantUomId: 3,
        name: 'Premium Paint',
        uom: 'CAN',
        unitPrice: 150,
        qty: 1,
      ),
    );
    vm.setExchangeAmountTendered(100);
    expect(vm.exchangeExtraDue, 50);

    final ok = await vm.submit();
    expect(ok, isTrue);
    expect(vm.exchangeResult?.exchangeNo, 'TRX-99');
    expect(repo.lastReturnLine?.variantUomId, 1);
    expect(repo.lastReplacementLine?.variantUomId, 3);
    expect(repo.lastTendered, 100);
  });

  test('cash refund mode requires confirming no replacement is available', () async {
    final repo = _FakeReturnsRepository();
    final vm = PosReturnsViewmodel(repository: repo);
    await vm.search('OS-42');
    vm.setQuantity(1, 1);
    vm.setReason('Defective');
    vm.setMode(ReturnMode.refund);

    expect(vm.canSubmit, isFalse);
    expect(await vm.submit(), isFalse);
    expect(repo.postedReturn, isFalse);

    vm.setNoReplacementConfirmed(true);
    expect(vm.canSubmit, isTrue);
    expect(await vm.submit(), isTrue);
    expect(repo.postedReturn, isTrue);
    expect(vm.result?.returnNo, 'TRX-100');
  });
}
