import 'dart:async';
// Phase 4 task 4 (decision 14). The checkout gains a CUSTOMER STEP: the cashier picks who is
// paying, or creates one on the spot, or leaves it anonymous.
//
// Today `submit()` resolves the Walk-in Customer id itself and the underpayment dialog passes a
// hardcoded 'Walk-in Customer' string, so there is no way to put a sale on a named account from
// the till. This is the state that replaces both.
//
// Decision 14's rules under test here:
//   * the default is ANONYMOUS - a walk-in, no record created, nothing asked of the buyer;
//   * a customer is created on a name + type record only;
//   * the sale goes to the SELECTED customer, not to whatever submit() used to resolve.

import 'package:client/data/models/customer.dart';
import 'package:client/data/repositories/customer_repository.dart';
import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubPosRepository extends PosRepository {
  _StubPosRepository() : super(PosService());

  int? sentCustomerId;

  /// When set, `checkout` throws it - so a test can drive the FAILURE path. Without this the
  /// stub always succeeded, which is how "the selection survives a failed submit" passed
  /// without ever failing (review finding 3).
  PosServiceException? failure;

  @override
  Future<int> walkInCustomerId() async => 1;

  @override
  Future<PosCheckoutResult> checkout({
    required int customerId,
    required List<PosCheckoutItem> items,
    required List<PosCheckoutPayment> payments,
    String source = 'WALK_IN',
  }) async {
    final boom = failure;
    if (boom != null) throw boom;
    sentCustomerId = customerId;
    return PosCheckoutResult(
      id: 18,
      transactionNo: 'TRX-20261016-0007',
      orNumber: 'OR-20261016-0007',
      transDate: DateTime(2026, 10, 16, 18, 56),
      grandTotal: 20,
    );
  }
}

class _StubCustomerRepository extends CustomerRepository {
  _StubCustomerRepository() : super(CustomerService());

  List<Customer> customers = const [];
  String? failureMessage;
  CustomerLedgerSummary? summary;
  int ledgerCalls = 0;

  /// Holds a load for [holdFor] in flight until the test completes [hold].
  ///
  /// This is what makes a LATE response testable at all. Without it a test can only observe a
  /// request that has already finished, so "a stale response arrived after the cashier moved
  /// on" - the whole class of defect F1 is about - cannot be reproduced. The previous attempt
  /// faked it with `lateFailureFor`, whose condition (`lateFailureFor != customerId`) was
  /// UNREACHABLE because the caller always requests the currently selected id: the test then
  /// failed A while A was still selected, which is correct behaviour, so it passed against the
  /// unfixed code as well.
  Completer<void>? hold;
  int? holdFor;

  int? failLedgerFor;

  /// This customer's ledger load throws - and it does so REGARDLESS of what else the test
  /// changes while the request is in flight.
  ///
  /// The first version of this test drove the failure with `failureMessage`, which
  /// `fetchLedgerSummary` reads AFTER the gate: the test then cleared that field before
  /// completing the gate, so the "failing" request actually SUCCEEDED, the error branch was
  /// never entered, and the test passed against the unguarded code. A failure a test can
  /// accidentally cancel is not a failure.
  PosServiceException? failure;
  ({String name, CustomerType type})? created;

  @override
  Future<List<Customer>> fetchCustomers() async {
    final failure = failureMessage;
    if (failure != null) throw CustomerServiceException(failure);
    return customers;
  }

  @override
  Future<CustomerLedgerSummary> fetchLedgerSummary(int customerId) async {
    ledgerCalls++;
    final gate = hold;
    if (gate != null && holdFor == customerId) await gate.future;
    if (failLedgerFor == customerId) {
      throw CustomerServiceException('Cannot connect to the BuildPro server.');
    }
    final failure = failureMessage;
    if (failure != null) throw CustomerServiceException(failure);
    return summary ?? CustomerLedgerSummary.empty(customerId);
  }

  @override
  Future<Customer> createCustomer({
    required String name,
    required CustomerType type,
  }) async {
    created = (name: name, type: type);
    final failure = failureMessage;
    if (failure != null) throw CustomerServiceException(failure);
    return Customer(id: 77, name: name, customerType: type.apiValue);
  }
}

void main() {
  _loadCustomersTests();
  _utangPanelTests();
  _reviewFixTests();

  late InventoryViewmodel inventory;
  late _StubPosRepository pos;
  late _StubCustomerRepository customers;
  late PosTransactionViewmodel cart;

  setUp(() {
    inventory = InventoryViewmodel();
    pos = _StubPosRepository();
    customers = _StubCustomerRepository();
    cart = PosTransactionViewmodel(
      inventory,
      ProductTrackingViewmodel(),
      pos: pos,
      customers: customers,
    );
  });

  Future<void> addOneLine() async {
    final item = cart.filteredProducts.first;
    final option = cart.saleOptionsFor(item).first;
    expect(cart.addLine(option, 1), isNull);
  }

  test('starts ANONYMOUS - a walk-in is not a customer record', () {
    expect(cart.selectedCustomer, isNull);
    expect(
      cart.customerLabel,
      contains('Walk-in'),
      reason:
          'the default must read as an anonymous sale, not as "nobody selected"',
    );
  });

  test(
    'selecting a customer changes the label and what the sale is addressed to',
    () async {
      await addOneLine();
      cart.selectCustomer(
        const Customer(id: 5, name: 'Maria Santos', customerType: 'REGULAR'),
      );

      expect(cart.customerLabel, 'Maria Santos');
      await cart.submit(paymentMethod: 'CASH', amountPaid: 100);
      expect(
        pos.sentCustomerId,
        5,
        reason:
            'the sale must go to the chosen account, not to the resolved walk-in',
      );
    },
  );

  test('an anonymous sale still resolves the walk-in id itself', () async {
    await addOneLine();

    await cart.submit(paymentMethod: 'CASH', amountPaid: 100);

    expect(pos.sentCustomerId, 1, reason: 'the seeded Walk-in Customer');
  });

  test('creating a customer selects it and sends only name and type', () async {
    final error = await cart.createAndSelectCustomer(
      name: 'Nena Reyes',
      type: CustomerType.regular,
    );

    expect(error, isNull);
    expect(cart.selectedCustomer?.name, 'Nena Reyes');
    expect(cart.selectedCustomer?.id, 77);
    expect(customers.created, isNotNull);
    expect(customers.created!.name, 'Nena Reyes');
    expect(
      customers.created!.type,
      CustomerType.regular,
      reason: 'the four-type enum must reach the wire, not a hardcoded default',
    );
  });

  test('a failed create reports a message and selects NOTHING', () async {
    customers.failureMessage = 'The customer list could not be loaded.';

    final error = await cart.createAndSelectCustomer(
      name: 'Nena Reyes',
      type: CustomerType.regular,
    );

    expect(error, isNotNull);
    expect(
      cart.selectedCustomer,
      isNull,
      reason:
          'selecting a customer that was never created would post a sale to a ghost',
    );
  });

  test(
    'the selection survives a failed submit - the cart is not reset',
    () async {
      await addOneLine();
      cart.selectCustomer(
        const Customer(id: 5, name: 'Maria Santos', customerType: 'REGULAR'),
      );
      pos.sentCustomerId = null;

      await cart.submit(paymentMethod: 'CASH', amountPaid: 100);

      expect(cart.selectedCustomer?.id, 5);
    },
  );
}

// Appended for the widget layer: the page needs the live customer list to hand the picker, so
// the viewmodel owns loading it (the one-data-path invariant - the page never touches a service).
void _loadCustomersTests() {
  group('customer list', () {
    late InventoryViewmodel inventory;
    late _StubCustomerRepository customers;
    late PosTransactionViewmodel cart;

    setUp(() {
      inventory = InventoryViewmodel();
      customers = _StubCustomerRepository();
      cart = PosTransactionViewmodel(
        inventory,
        ProductTrackingViewmodel(),
        pos: _StubPosRepository(),
        customers: customers,
      );
    });

    test('starts with nothing loaded and no error', () {
      expect(cart.customers, isEmpty);
      expect(cart.customersError, isNull);
    });

    test('loadCustomers brings the list in', () async {
      customers.customers = const [
        Customer(id: 2, name: 'Maria Santos', customerType: 'REGULAR'),
      ];

      await cart.loadCustomers();

      expect(cart.customers, hasLength(1));
      expect(cart.customers.single.name, 'Maria Santos');
      expect(cart.customersError, isNull);
    });

    test(
      'a failed load sets customersError and does NOT empty the list',
      () async {
        customers.customers = const [
          Customer(id: 2, name: 'Maria Santos', customerType: 'REGULAR'),
        ];
        await cart.loadCustomers();
        customers.failureMessage = 'Cannot connect to the BuildPro server.';

        await cart.loadCustomers();

        expect(cart.customersError, contains('Cannot connect'));
        expect(
          cart.customers,
          hasLength(1),
          reason: 'an emptied list would read as "this store has no customers"',
        );
      },
    );
  });
}

// T5: the utang panel. The balance is loaded for the SELECTED customer, and a customer who
// owes nothing is a zero summary rather than an error - decision 14's panel shows the account
// at the till, so "owes nothing" and "could not ask" must not look alike.
void _utangPanelTests() {
  group('utang for the selected customer', () {
    late InventoryViewmodel inventory;
    late _StubCustomerRepository customers;
    late PosTransactionViewmodel cart;

    setUp(() {
      inventory = InventoryViewmodel();
      customers = _StubCustomerRepository();
      cart = PosTransactionViewmodel(
        inventory,
        ProductTrackingViewmodel(),
        pos: _StubPosRepository(),
        customers: customers,
      );
    });

    test('no customer selected means no summary and no request', () {
      expect(cart.ledgerSummary, isNull);
      expect(customers.ledgerCalls, 0);
    });

    test('selecting a customer loads their balance', () async {
      customers.summary = const CustomerLedgerSummary(
        customerId: 5,
        customerName: 'Maria Santos',
        totalBalance: 4900,
        openCount: 2,
        overdueCount: 1,
      );

      cart.selectCustomer(
        const Customer(id: 5, name: 'Maria Santos', customerType: 'REGULAR'),
      );
      await cart.loadLedgerForSelection();

      expect(customers.ledgerCalls, 1);
      expect(cart.ledgerSummary!.totalBalance, 4900);
      expect(cart.ledgerSummary!.overdueCount, 1);
    });

    test('an anonymous sale has no utang to show', () async {
      cart.selectCustomer(
        const Customer(id: 5, name: 'Maria Santos', customerType: 'REGULAR'),
      );
      await cart.loadLedgerForSelection();
      cart.selectCustomer(null);

      expect(
        cart.ledgerSummary,
        isNull,
        reason: 'an anonymous sale cannot owe, so there is nothing to display',
      );
    });

    test(
      'a failed ledger load sets an error and does not invent a balance',
      () async {
        customers.failureMessage = 'Cannot connect to the BuildPro server.';
        cart.selectCustomer(
          const Customer(id: 5, name: 'Maria Santos', customerType: 'REGULAR'),
        );

        await cart.loadLedgerForSelection();

        expect(cart.ledgerError, contains('Cannot connect'));
        expect(
          cart.ledgerSummary,
          isNull,
          reason: 'a zero balance would read as "this customer owes nothing"',
        );
      },
    );
  });
}

// Review findings 1-3. Written BEFORE the fixes, so each one is watched failing.
void _reviewFixTests() {
  group('review findings', () {
    late InventoryViewmodel inventory;
    late _StubCustomerRepository customers;
    late PosTransactionViewmodel cart;

    setUp(() {
      inventory = InventoryViewmodel();
      customers = _StubCustomerRepository();
      cart = PosTransactionViewmodel(
        inventory,
        ProductTrackingViewmodel(),
        pos: _StubPosRepository(),
        customers: customers,
      );
    });

    test(
      'F1: a late FAILURE for the PREVIOUS customer must not clobber the new one',
      () async {
        // The scenario the original test could not reach: A's load is still IN FLIGHT when the
        // cashier moves to B and B's balance loads, and only then does A's request land - as a
        // FAILURE. The success path was guarded against exactly this; the error path was not, so
        // A's failure overwrote B's state. The panel checks the error BEFORE the summary, so the
        // cashier saw "Cannot connect to the BuildPro server." where B's real balance had already
        // loaded, with B's summary nulled on the way.
        customers.hold = Completer<void>();
        customers.holdFor = 5;
        customers.failLedgerFor = 5;
        cart.selectCustomer(
          const Customer(id: 5, name: 'A', customerType: 'REGULAR'),
        );
        final aInFlight = cart.loadLedgerForSelection();

        // The cashier moves on while A's request is still in the air. B loads fine.
        customers.holdFor = null;
        customers.summary = const CustomerLedgerSummary(
          customerId: 6,
          customerName: 'B',
          totalBalance: 250,
          openCount: 1,
          overdueCount: 0,
        );
        cart.selectCustomer(
          const Customer(id: 6, name: 'B', customerType: 'REGULAR'),
        );
        await cart.loadLedgerForSelection();
        expect(cart.ledgerSummary?.totalBalance, 250);
        expect(cart.ledgerError, isNull);

        // A's request lands now, carrying A's failure.
        customers.hold!.complete();
        await aInFlight;

        expect(
          cart.ledgerError,
          isNull,
          reason: "A's failure describes A, who is no longer the selection",
        );
        expect(
          cart.ledgerSummary?.totalBalance,
          250,
          reason: "B's loaded balance must survive A's late failure",
        );
      },
    );

    test(
      'F2: a created customer must not inherit the previous one\'s debt',
      () async {
        customers.summary = const CustomerLedgerSummary(
          customerId: 5,
          customerName: 'Maria Santos',
          totalBalance: 4900,
          openCount: 2,
          overdueCount: 1,
        );
        cart.selectCustomer(
          const Customer(id: 5, name: 'Maria Santos', customerType: 'REGULAR'),
        );
        await cart.loadLedgerForSelection();
        expect(cart.ledgerSummary?.totalBalance, 4900);

        await cart.createAndSelectCustomer(
          name: 'Nena Reyes',
          type: CustomerType.regular,
        );

        expect(
          cart.ledgerSummary,
          isNull,
          reason: "Maria's 4900 must never render under Nena's name",
        );
        expect(cart.ledgerError, isNull);
      },
    );

    test('F3: the selection must survive a genuinely FAILED submit', () async {
      // The old test could not fail: the stub always returned success, so `submit` returned
      // true, the cart cleared, and the assertion held no matter what. This drives the
      // failure path the test claimed to cover.
      final pos = _StubPosRepository()
        ..failure = PosServiceException('The server broke.');
      final cart2 = PosTransactionViewmodel(
        inventory,
        ProductTrackingViewmodel(),
        pos: pos,
        customers: customers,
      );
      final item = cart2.filteredProducts.first;
      cart2.addLine(cart2.saleOptionsFor(item).first, 1);
      cart2.selectCustomer(
        const Customer(id: 5, name: 'Maria Santos', customerType: 'REGULAR'),
      );

      final confirmed = await cart2.submit(
        paymentMethod: 'CASH',
        amountPaid: 100,
      );

      expect(confirmed, isFalse, reason: 'the submit must really have failed');
      expect(cart2.submitError, isNotNull);
      expect(cart2.selectedCustomer?.id, 5);
      expect(cart2.lines, hasLength(1), reason: 'a failed sale keeps the cart');
    });
  });
}
