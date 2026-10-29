// Phase 4 task 8, review finding 2. The client's idea of "anonymous" must be the SERVER's.
//
// The server refuses a shortfall when customer_type == WALK_IN (apps/pos/services.py), but the
// page tested `selectedCustomer == null` - so a cashier could create a customer typed Walk-in
// from the very picker T6 added, have it selected, be shown the NAMED dialog copy promising a
// receivable, and get a 400. Worse, that customer is then hidden from the picker forever.
//
// The rule now has ONE home on the viewmodel, which is what makes it testable.

import 'package:client/data/models/customer.dart';
import 'package:client/data/repositories/customer_repository.dart';
import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import '../../support/phase4_fakes.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubPosRepository extends PosRepository {
  _StubPosRepository() : super(PosService());

  @override
  Future<int> walkInCustomerId() async => 1;

  @override
  Future<PosCheckoutResult> checkout({
    required int customerId,
    required List<PosCheckoutItem> items,
    required List<PosCheckoutPayment> payments,
    String source = 'WALK_IN',
    String? idempotencyKey,
  }) async => PosCheckoutResult(
    id: 1,
    transactionNo: 'TRX-1',
    orNumber: 'OR-1',
    transDate: DateTime(2026, 10, 17, 10),
    grandTotal: 0,
  );
}

class _StubCustomerRepository extends CustomerRepository {
  _StubCustomerRepository() : super(CustomerService());

  @override
  Future<List<Customer>> fetchCustomers() async => const [];

  @override
  Future<CustomerLedgerSummary> fetchLedgerSummary(int customerId) async =>
      CustomerLedgerSummary.empty(customerId);
}

Customer _customer(String type) =>
    Customer(id: 7, name: 'Named Person', customerType: type);

void main() {
  late PosTransactionViewmodel cart;

  setUp(() {
    cart = PosTransactionViewmodel(
      seededInventory(),
      pos: _StubPosRepository(),
      customers: _StubCustomerRepository(),
    );
  });

  test('nothing selected is anonymous - the ordinary default', () {
    expect(cart.selectedCustomer, isNull);
    expect(cart.isAnonymousSelection, isTrue);
  });

  test(
    'a customer TYPED walk-in is STILL anonymous, because the server says so',
    () {
      cart.selectCustomer(_customer('WALK_IN'));

      expect(
        cart.selectedCustomer,
        isNotNull,
        reason:
            'it IS selected - which is exactly why a null check was the wrong test',
      );
      expect(
        cart.isAnonymousSelection,
        isTrue,
        reason:
            'the server refuses on customer_type == WALK_IN, so this cannot owe',
      );
    },
  );

  test('a MIS-CASED type is not recognised, and so is NOT treated as walk-in', () {
    // `CustomerType.fromApiValue` matches the server's exact values; anything else falls back
    // to `unknown`. Asserted rather than wished for: the server writes these constants, so a
    // mis-cased value means the contract changed, not that the cashier typed it.
    cart.selectCustomer(_customer('walk_in'));
    expect(cart.isAnonymousSelection, isFalse);
  });

  test('a real account is not anonymous', () {
    for (final type in ['REGULAR', 'CONTRACTOR', 'CONSTRUCTION_FIRM']) {
      cart.selectCustomer(_customer(type));
      expect(cart.isAnonymousSelection, isFalse, reason: type);
    }
  });

  test('a type the client does not recognise is treated as a NAMED account', () {
    // The genuine dilemma, resolved toward the optimistic answer: a type added on the server
    // is almost certainly a named customer, so refusing to let them owe would block legitimate
    // business. The cost is that if such a type IS anonymous, the dialog promises a receivable
    // and the server refuses it - the dead end again, but only for a type that does not exist
    // yet. The server remains the authority either way; the client cannot know.
    cart.selectCustomer(_customer('SOMETHING_NEW'));
    expect(cart.isAnonymousSelection, isFalse);
  });

  test('clearing the selection makes it anonymous again', () {
    cart.selectCustomer(_customer('REGULAR'));
    expect(cart.isAnonymousSelection, isFalse);
    cart.selectCustomer(null);
    expect(cart.isAnonymousSelection, isTrue);
  });
}
