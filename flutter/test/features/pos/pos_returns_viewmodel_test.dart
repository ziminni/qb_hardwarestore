// Phase 3 Task 4 / decision 05: the till's returns flow, below the widget.
//
// Everything here is a guard that must hold when no widget is watching:
//
//  * a MISS is not a stale hit — the previous customer's sale must be gone;
//  * the stepper is capped at `remaining_qty`, so the screen cannot offer a
//    quantity the server refuses with RETURN_QTY_EXCEEDED;
//  * a blank reason sends NOTHING (the server would refuse it, and a refusal
//    reads as a bug at the counter);
//  * the money is DEBT FIRST: return value settles the utang before any cash;
//  * the POSTED `refund_summary` REPLACES the client's estimate — the drawer's
//    figures are the server's arithmetic, not the till's.

import 'package:client/data/models/returns.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/repositories/returns_repository.dart';
import 'package:client/data/services/returns_service.dart';
import 'package:client/features/pos/viewmodels/pos_returns_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

TransactionRecord _sale({int id = 18, int customerId = 2}) => TransactionRecord(
  id: id,
  transactionNo: 'TRX-20261024-0007',
  transDate: DateTime(2026, 10, 24, 9),
  customerId: customerId,
  customerName: 'Maria Santos',
  cashierName: 'Ana Cruz',
  source: 'CHARGE',
  originalTransactionId: null,
  status: 'COMPLETED',
  grandTotal: 1000,
  items: const [],
  payments: const [],
);

ReturnableSale _preflight({
  double openDebt = 600,
  bool returnable = true,
  String? reasonIfNot,
}) => ReturnableSale(
  transactionNo: 'TRX-20261024-0007',
  customer: 'Maria Santos',
  source: 'CHARGE',
  returnable: returnable,
  reasonIfNot: reasonIfNot,
  openDebt: openDebt,
  lines: const [
    ReturnableLine(
      variantUomId: 8,
      name: 'Portland Cement - 40kg',
      uom: 'BAG',
      soldQty: 10,
      returnedQty: 2,
      remainingQty: 8,
      unitPrice: 100,
    ),
    ReturnableLine(
      variantUomId: 9,
      name: 'Steel Bar 10mm',
      uom: 'PC',
      soldQty: 5,
      returnedQty: 5,
      remainingQty: 0,
      unitPrice: 250,
    ),
  ],
);

class _StubReturns extends ReturnsRepository {
  TransactionRecord? found;
  ReturnableSale? preflight;
  Object? failSearch;
  Object? failPreflight;
  Object? failPost;

  final List<
    ({
      int customerId,
      int originalTransactionId,
      String reason,
      String paymentMethod,
      List<ReturnRequestLine> lines,
    })
  >
  posts = [];

  final List<String> queries = [];
  int preflightCalls = 0;

  @override
  Future<TransactionRecord?> findSale(String query) async {
    queries.add(query);
    if (failSearch != null) throw failSearch!;
    return found;
  }

  @override
  Future<ReturnableSale> fetchReturnable(int transactionId) async {
    preflightCalls++;
    if (failPreflight != null) throw failPreflight!;
    return preflight!;
  }

  @override
  Future<ReturnResult> postReturn({
    required int customerId,
    required int originalTransactionId,
    required String reason,
    required String paymentMethod,
    required List<ReturnRequestLine> lines,
  }) async {
    posts.add((
      customerId: customerId,
      originalTransactionId: originalTransactionId,
      reason: reason,
      paymentMethod: paymentMethod,
      lines: lines,
    ));
    if (failPost != null) throw failPost!;
    return const ReturnResult(
      returnNo: 'RTN-20261024-0001',
      refund: RefundSummary(
        returnValue: 800,
        debtReduced: 600,
        cashRefund: 200,
        refundMethod: 'CASH',
        ledgerId: 5,
        ledgerBalance: 0,
      ),
    );
  }
}

_PosReturnsHarness _harness() {
  final repository = _StubReturns();
  return _PosReturnsHarness(
    repository,
    PosReturnsViewmodel(repository: repository),
  );
}

class _PosReturnsHarness {
  _PosReturnsHarness(this.repository, this.viewmodel);

  final _StubReturns repository;
  final PosReturnsViewmodel viewmodel;
}

void main() {
  group('search', () {
    test('a hit loads the sale AND its pre-flight', () async {
      final h = _harness();
      h.repository
        ..found = _sale()
        ..preflight = _preflight();

      await h.viewmodel.search('OR-20261024-0007');

      expect(h.repository.queries, ['OR-20261024-0007']);
      expect(h.viewmodel.foundSale?.id, 18);
      expect(h.viewmodel.preflight?.lines, hasLength(2));
      expect(h.viewmodel.searchedMiss, isFalse);
      expect(h.viewmodel.searchError, isNull);
    });

    test(
      'a miss clears the previous sale instead of leaving it to be refunded',
      () async {
        final h = _harness();
        h.repository
          ..found = _sale()
          ..preflight = _preflight();
        await h.viewmodel.search('OR-1');
        h.viewmodel.setQuantity(8, 3);

        h.repository.found = null;
        await h.viewmodel.search('OR-2');

        expect(h.viewmodel.searchedMiss, isTrue);
        expect(
          h.viewmodel.foundSale,
          isNull,
          reason:
              'a stale sale left on screen is the previous customer, refunded by '
              'mistake',
        );
        expect(h.viewmodel.preflight, isNull);
        expect(h.viewmodel.hasQuantity, isFalse);
      },
    );

    test(
      'an empty query asks for a number instead of hitting the server',
      () async {
        final h = _harness();

        await h.viewmodel.search('  ');

        expect(h.repository.queries, isEmpty);
        expect(h.viewmodel.searchError, contains('Enter the transaction'));
      },
    );

    test(
      'a failed pre-flight is reported, and the sale is not postable',
      () async {
        final h = _harness();
        h.repository
          ..found = _sale()
          ..failPreflight = const ReturnsServiceException(
            'The returnable quantities could not be read.',
          );

        await h.viewmodel.search('OR-1');

        expect(h.viewmodel.searchError, contains('could not be read'));
        expect(h.viewmodel.preflight, isNull);
        expect(h.viewmodel.canSubmit, isFalse);
      },
    );
  });

  group('the quantity cap', () {
    test('a quantity above what is left is capped, not sent', () async {
      final h = _harness();
      h.repository
        ..found = _sale()
        ..preflight = _preflight();
      await h.viewmodel.search('OR-1');

      h.viewmodel.setQuantity(8, 99);

      expect(
        h.viewmodel.quantityFor(8),
        8,
        reason:
            'the server would refuse 99 with RETURN_QTY_EXCEEDED; offering it '
            'turns a rules mistake into an apparent bug',
      );
    });

    test('a fully returned line cannot be incremented', () async {
      final h = _harness();
      h.repository
        ..found = _sale()
        ..preflight = _preflight();
      await h.viewmodel.search('OR-1');

      h.viewmodel.increment(9);

      expect(h.viewmodel.quantityFor(9), 0);
      expect(h.viewmodel.hasQuantity, isFalse);
    });

    test('decrement never goes below zero', () async {
      final h = _harness();
      h.repository
        ..found = _sale()
        ..preflight = _preflight();
      await h.viewmodel.search('OR-1');
      h.viewmodel.increment(8);

      h.viewmodel.decrement(8);
      h.viewmodel.decrement(8);

      expect(h.viewmodel.quantityFor(8), 0);
    });

    test('only chosen lines are sent', () async {
      final h = _harness();
      h.repository
        ..found = _sale()
        ..preflight = _preflight();
      await h.viewmodel.search('OR-1');
      h.viewmodel.setQuantity(8, 8);
      h.viewmodel.setReason('cracked sacks');

      await h.viewmodel.submit();

      expect(h.repository.posts.single.lines, hasLength(1));
      expect(h.repository.posts.single.lines.single.variantUomId, 8);
      expect(h.repository.posts.single.lines.single.qty, 8);
    });
  });

  group('a reason is required before anything is sent', () {
    test('a blank reason sends NOTHING and says why', () async {
      final h = _harness();
      h.repository
        ..found = _sale()
        ..preflight = _preflight();
      await h.viewmodel.search('OR-1');
      h.viewmodel.setQuantity(8, 2);

      expect(await h.viewmodel.submit(), isFalse);

      expect(h.repository.posts, isEmpty);
      expect(h.viewmodel.submitError, contains('needs a reason'));
      expect(
        h.viewmodel.submitError,
        contains('say why the customer brought the goods back'),
      );
    });

    test('whitespace is not a reason', () async {
      final h = _harness();
      h.repository
        ..found = _sale()
        ..preflight = _preflight();
      await h.viewmodel.search('OR-1');
      h.viewmodel.setQuantity(8, 2);
      h.viewmodel.setReason('   ');

      expect(await h.viewmodel.submit(), isFalse);
      expect(h.repository.posts, isEmpty);
    });

    test('no quantity chosen sends nothing', () async {
      final h = _harness();
      h.repository
        ..found = _sale()
        ..preflight = _preflight();
      await h.viewmodel.search('OR-1');
      h.viewmodel.setReason('unwanted');

      expect(await h.viewmodel.submit(), isFalse);
      expect(h.repository.posts, isEmpty);
      expect(h.viewmodel.submitError, contains('Choose at least one quantity'));
    });
  });

  group('the money is debt first', () {
    test('the estimate settles the utang before cash', () async {
      final h = _harness();
      h.repository
        ..found = _sale()
        ..preflight = _preflight(openDebt: 600);
      await h.viewmodel.search('OR-1');
      h.viewmodel.setQuantity(8, 8);

      expect(h.viewmodel.returnValue, 800);
      expect(h.viewmodel.debtReducedEstimate, 600);
      expect(
        h.viewmodel.cashRefundEstimate,
        200,
        reason:
            'decision 05: the shop does NOT hand 800 cash back for goods the '
            'customer never finished paying for',
      );
    });

    test('a sale owing more than the return refunds no cash at all', () async {
      final h = _harness();
      h.repository
        ..found = _sale()
        ..preflight = _preflight(openDebt: 900);
      await h.viewmodel.search('OR-1');
      h.viewmodel.setQuantity(8, 2);

      expect(h.viewmodel.returnValue, 200);
      expect(h.viewmodel.debtReducedEstimate, 200);
      expect(h.viewmodel.cashRefundEstimate, 0);
    });

    test('a paid-up sale refunds the whole value in cash', () async {
      final h = _harness();
      h.repository
        ..found = _sale()
        ..preflight = _preflight(openDebt: 0);
      await h.viewmodel.search('OR-1');
      h.viewmodel.setQuantity(8, 2);

      expect(h.viewmodel.debtReducedEstimate, 0);
      expect(h.viewmodel.cashRefundEstimate, 200);
    });
  });

  group('submitting', () {
    test(
      'sends the original sale, its customer, the reason and the method',
      () async {
        final h = _harness();
        h.repository
          ..found = _sale(id: 18, customerId: 2)
          ..preflight = _preflight();
        await h.viewmodel.search('OR-1');
        h.viewmodel.setQuantity(8, 8);
        h.viewmodel.setReason(' cracked sacks between layers ');
        h.viewmodel.setRefundMethod('GCASH');

        expect(await h.viewmodel.submit(), isTrue);

        final post = h.repository.posts.single;
        expect(
          post.customerId,
          2,
          reason:
              'the ORIGINAL sale customer: a refund settles THAT customer\'s '
              'utang, and the pre-flight body carries no id',
        );
        expect(post.originalTransactionId, 18);
        expect(post.reason, ' cracked sacks between layers ');
        expect(post.paymentMethod, 'GCASH');
      },
    );

    test('the POSTED summary replaces the client estimate', () async {
      final h = _harness();
      h.repository
        ..found = _sale()
        ..preflight = _preflight(openDebt: 900);
      await h.viewmodel.search('OR-1');
      h.viewmodel.setQuantity(8, 2);
      h.viewmodel.setReason('unwanted');
      // The client's estimate is 0 cash (debt 900 > value 200)...
      expect(h.viewmodel.cashRefundEstimate, 0);

      await h.viewmodel.submit();

      // ...and the server's answer is what the screen prints afterwards.
      expect(h.viewmodel.result?.returnNo, 'RTN-20261024-0001');
      expect(h.viewmodel.result?.refund.debtReduced, 600);
      expect(h.viewmodel.result?.refund.cashRefund, 200);
      expect(h.viewmodel.result?.refund.ledgerBalance, 0);
      expect(h.viewmodel.canSubmit, isFalse, reason: 'one return, one post');
    });

    test('a NO_OPEN_SHIFT refusal is flagged as fixable', () async {
      final h = _harness();
      h.repository
        ..found = _sale()
        ..preflight = _preflight()
        ..failPost = const ReturnsServiceException(
          'You have no open shift. Open a shift before posting a return.',
          code: 'NO_OPEN_SHIFT',
          needsOpenShift: true,
        );
      await h.viewmodel.search('OR-1');
      h.viewmodel.setQuantity(8, 2);
      h.viewmodel.setReason('unwanted');

      expect(await h.viewmodel.submit(), isFalse);

      expect(h.viewmodel.needsOpenShift, isTrue);
      expect(h.viewmodel.submitError, contains('Open a shift'));
      expect(h.viewmodel.result, isNull);
    });

    test("a server's refusal is shown in its own words", () async {
      final h = _harness();
      h.repository
        ..found = _sale()
        ..preflight = _preflight()
        ..failPost = const ReturnsServiceException(
          'Selling unit 8 sold 10.00 on this sale, 2.00 already returned.',
          code: 'RETURN_QTY_EXCEEDED',
        );
      await h.viewmodel.search('OR-1');
      h.viewmodel.setQuantity(8, 2);
      h.viewmodel.setReason('unwanted');

      expect(await h.viewmodel.submit(), isFalse);

      expect(h.viewmodel.submitError, contains('sold 10.00'));
      expect(h.viewmodel.needsOpenShift, isFalse);
    });
  });

  group('a document the server refuses to reverse', () {
    test('cannot be submitted, and says which rule stopped it', () async {
      final h = _harness();
      h.repository
        ..found = _sale()
        ..preflight = _preflight(
          returnable: false,
          reasonIfNot: 'RELEASE_NOT_RETURNABLE',
        );
      await h.viewmodel.search('OR-1');
      h.viewmodel.setQuantity(8, 2);
      h.viewmodel.setReason('unwanted');

      expect(h.viewmodel.isRefusedByServer, isTrue);
      expect(
        h.viewmodel.refusalMessage,
        contains('material release, not a sale'),
      );
      expect(h.viewmodel.canSubmit, isFalse);

      expect(await h.viewmodel.submit(), isFalse);
      expect(h.repository.posts, isEmpty);
    });
  });

  group('starting the next return', () {
    test('reset clears the sale, the quantities and the reason', () async {
      final h = _harness();
      h.repository
        ..found = _sale()
        ..preflight = _preflight();
      await h.viewmodel.search('OR-1');
      h.viewmodel.setQuantity(8, 2);
      h.viewmodel.setReason('unwanted');
      await h.viewmodel.submit();

      h.viewmodel.reset();

      expect(h.viewmodel.foundSale, isNull);
      expect(h.viewmodel.preflight, isNull);
      expect(h.viewmodel.reason, isEmpty);
      expect(h.viewmodel.result, isNull);
      expect(h.viewmodel.hasQuantity, isFalse);
      expect(h.viewmodel.refundMethod, 'CASH');
    });
  });
}
