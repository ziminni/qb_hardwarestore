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

  @override
  Future<int> walkInCustomerId() async => 1;

  @override
  Future<PosCheckoutResult> checkout({
    required int customerId,
    required List<PosCheckoutItem> items,
    required List<PosCheckoutPayment> payments,
    String source = 'WALK_IN',
  }) async {
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

    test('a failed load sets customersError and does NOT empty the list', () async {
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
    });
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

    test('a failed ledger load sets an error and does not invent a balance', () async {
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
    });
  });
}
