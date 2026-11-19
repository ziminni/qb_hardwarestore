import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/sale_discount.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/customer_profile_store.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/views/pos_customers_page.dart';
import 'package:client/features/pos/widgets/pos_payment_dialog.dart';
import 'package:client/features/pos/widgets/pos_transaction_cart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/payment_steps.dart';
import '../../support/phase4_fakes.dart';

void main() {
  late PosTransactionViewmodel cart;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CustomerProfileStore.instance.resetToDefaults();
    cart = PosTransactionViewmodel(seededInventory());
    final firstProduct = cart.filteredProducts.first;
    final firstOption = cart.saleOptionsFor(firstProduct).first;
    expect(cart.addLine(firstOption, 2), isNull);
  });

  group('Automatic pre-fill when a customer is selected', () {
    testWidgets(
      'Mang Kanor (Senior Citizen regular) automatically fills the discount section in the transaction and payment dialog',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final mangKanor = CustomerProfileStore.instance
            .mergeCustomers(const [])
            .firstWhere((e) => e.customer.name == 'Mang Kanor')
            .customer;

        cart.selectCustomer(mangKanor);

        PosPaymentDetails? result;
        await tester.pumpWidget(
          ChangeNotifierProvider<PosTransactionViewmodel>.value(
            value: cart,
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: Builder(
                  builder: (context) => Row(
                    children: [
                      SizedBox(
                        width: 400,
                        height: 700,
                        child: PosTransactionCart(
                          onPayment: () async {
                            result = await showDialog<PosPaymentDetails>(
                              context: context,
                              builder: (_) => PosPaymentDialog(
                                total: cart.total,
                                discountCapPercent: 25,
                                lines: cart.lines,
                                cart: cart,
                              ),
                            );
                          },
                          onClear: () {},
                          onChangeCustomer: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Cart immediately shows Mang Kanor's Senior Citizen 20% discount badge & discount row.
        expect(find.text('Mang Kanor'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('pos-cart-customer-discount-badge')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('pos-cart-discount-section')),
          findsOneWidget,
        );
        expect(find.textContaining('Senior Citizen (20%)'), findsWidgets);

        // 2. Open the payment dialog and go to the Discount step.
        await tester.tap(find.text('Proceed to payment'));
        await tester.pumpAndSettle();
        await goToDiscountStep(tester);

        // The Discount section is already turned ON and populated with 20% + Senior Citizen reason.
        final valueField = tester.widget<TextFormField>(
          find.byKey(const ValueKey('pos-discount-value')),
        );
        final reasonField = tester.widget<TextFormField>(
          find.byKey(const ValueKey('pos-discount-reason')),
        );
        expect(valueField.controller!.text, '20');
        expect(
          reasonField.controller!.text,
          contains('Senior Citizen (20%)'),
        );

        // Still editable by the cashier if needed.
        await tester.enterText(
          find.byKey(const ValueKey('pos-discount-reason')),
          'Senior Citizen — Mang Kanor (OSCA-20419)',
        );
        await tester.pumpAndSettle();

        await completePayment(tester);
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.discount, isNotNull);
        expect(result!.discount!.kind, DiscountKind.percent);
        expect(result!.discount!.value, 20);
        expect(
          result!.discount!.reason,
          'Senior Citizen — Mang Kanor (OSCA-20419)',
        );
      },
    );

    testWidgets(
      'Manang Rosa (regular) automatically fills Name, Contact number, and Address in Utang while remaining editable',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final manangRosa = CustomerProfileStore.instance
            .mergeCustomers(const [])
            .firstWhere((e) => e.customer.name == 'Manang Rosa')
            .customer;

        cart.selectCustomer(manangRosa);

        PosPaymentDetails? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    result = await showDialog<PosPaymentDetails>(
                      context: context,
                      builder: (_) => PosPaymentDialog(
                        total: cart.total,
                        lines: cart.lines,
                        cart: cart,
                      ),
                    );
                  },
                  child: const Text('Pay'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Pay'));
        await tester.pumpAndSettle();
        await goToPaymentStep(tester);

        // Switch tender method to Utang.
        await tester.tap(
          find.byKey(const ValueKey('pos-tender-method-0')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Utang').last);
        await tester.pumpAndSettle();

        // Utang fields are automatically filled with Manang Rosa's saved details.
        final nameField = tester.widget<TextFormField>(
          find.byKey(const ValueKey('pos-utang-name')),
        );
        final contactField = tester.widget<TextFormField>(
          find.byKey(const ValueKey('pos-utang-contact')),
        );
        final addressField = tester.widget<TextFormField>(
          find.byKey(const ValueKey('pos-utang-address')),
        );

        expect(nameField.controller!.text, 'Manang Rosa');
        expect(contactField.controller!.text, '0918-634-5521');
        expect(
          addressField.controller!.text,
          '142 Mabini St., Brgy. San Jose',
        );

        // Cashier can still type / edit the pre-filled Utang fields.
        await tester.enterText(
          find.byKey(const ValueKey('pos-utang-address')),
          '145 Mabini St., Brgy. San Jose (Near Plaza)',
        );
        await tester.pumpAndSettle();

        await completePayment(tester);
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.utang, isNotNull);
        expect(result!.utang!.name, 'Manang Rosa');
        expect(result!.utang!.contact, '0918-634-5521');
        expect(
          result!.utang!.address,
          '145 Mabini St., Brgy. San Jose (Near Plaza)',
        );
      },
    );

    testWidgets(
      'Delivery toggle automatically fills Contact name, Contact phone, and Delivery address from selected customer while remaining editable',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final manangRosa = CustomerProfileStore.instance
            .mergeCustomers(const [])
            .firstWhere((e) => e.customer.name == 'Manang Rosa')
            .customer;

        cart.selectCustomer(manangRosa);

        PosPaymentDetails? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    result = await showDialog<PosPaymentDetails>(
                      context: context,
                      builder: (_) => PosPaymentDialog(
                        total: cart.total,
                        lines: cart.lines,
                        cart: cart,
                      ),
                    );
                  },
                  child: const Text('Pay'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Pay'));
        await tester.pumpAndSettle();
        await goToPaymentStep(tester);

        // Toggle Delivery switch ON.
        await tester.tap(find.byKey(const ValueKey('pos-deliver-toggle')));
        await tester.pumpAndSettle();

        final addressField = tester.widget<TextFormField>(
          find.byKey(const ValueKey('pos-delivery-address')),
        );
        final contactField = tester.widget<TextFormField>(
          find.byKey(const ValueKey('pos-delivery-contact')),
        );
        final phoneField = tester.widget<TextFormField>(
          find.byKey(const ValueKey('pos-delivery-phone')),
        );

        expect(
          addressField.controller!.text,
          '142 Mabini St., Brgy. San Jose',
        );
        expect(contactField.controller!.text, 'Manang Rosa');
        expect(phoneField.controller!.text, '0918-634-5521');

        // Cashier can still type / edit the pre-filled Delivery fields.
        await tester.enterText(
          find.byKey(const ValueKey('pos-delivery-address')),
          'Site Gate 2, 142 Mabini St., Brgy. San Jose',
        );
        await tester.pumpAndSettle();

        await completePayment(tester);
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.delivery, isNotNull);
        expect(result!.delivery!.contactName, 'Manang Rosa');
        expect(result!.delivery!.contactPhone, '0918-634-5521');
        expect(
          result!.delivery!.address,
          'Site Gate 2, 142 Mabini St., Brgy. San Jose',
        );
      },
    );
  });

  group('Cashier Customers Page (/pos/customers)', () {
    testWidgets(
      'lists regular customers, selects one for the current sale, and adds a new regular customer with presets',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthViewmodel>.value(
                value: AuthViewmodel(AuthRepository(AuthService())),
              ),
              ChangeNotifierProvider<PosTransactionViewmodel>.value(
                value: cart,
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: PosCustomersPage(viewmodel: cart),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Shows Mang Kanor and Manang Rosa with their presets.
        expect(find.text('Mang Kanor'), findsOneWidget);
        expect(find.text('Manang Rosa'), findsOneWidget);
        expect(find.text('Senior Citizen · 20% off'), findsOneWidget);

        // Select Mang Kanor for the current sale directly from the Customers page.
        await tester.tap(
          find.byKey(const ValueKey('pos-customer-use-Mang Kanor')),
        );
        await tester.pumpAndSettle();

        expect(cart.selectedCustomer?.name, 'Mang Kanor');
        expect(cart.selectedCustomerPresetDiscount?.value, 20);

        // Add a new regular customer (Aling Nena, PWD 20%) and auto-select for current sale.
        await tester.tap(find.byKey(const ValueKey('pos-customers-add-btn')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('pos-customer-form-name')),
          'Aling Nena',
        );
        await tester.enterText(
          find.byKey(const ValueKey('pos-customer-form-phone')),
          '0919-777-1234',
        );
        await tester.enterText(
          find.byKey(const ValueKey('pos-customer-form-address')),
          '88 Bonifacio St., Brgy. Poblacion',
        );
        await tester.tap(
          find.byKey(const ValueKey('pos-customer-discount-chip-pwd')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('pos-customer-form-save')));
        await tester.pumpAndSettle();

        expect(cart.selectedCustomer?.name, 'Aling Nena');
        expect(cart.selectedCustomerProfile?.phone, '0919-777-1234');
        expect(
          cart.selectedCustomerProfile?.address,
          '88 Bonifacio St., Brgy. Poblacion',
        );
        expect(
          cart.selectedCustomerPresetDiscount?.kind,
          DiscountKind.percent,
        );
        expect(cart.selectedCustomerPresetDiscount?.value, 20);
        expect(
          cart.selectedCustomerPresetDiscount?.reason,
          contains('PWD (20%)'),
        );
      },
    );
  });
}
