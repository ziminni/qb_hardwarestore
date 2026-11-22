// Owner rulings, at the UI boundary: the drawer carry, the close's cash-left
// question, and the credit-price switch. Each asserts the number the cashier or
// the customer acts on, not a widget's internals.

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/pos_transaction.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_cart_bar.dart';
import 'package:client/features/pos/widgets/pos_opening_float_form.dart';
import 'package:client/features/pos/widgets/pos_shift_close_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// A shift service that answers from the test instead of the wire.
class _FakeShiftService extends ShiftService {
  _FakeShiftService({this.suggestion, this.onClose});

  final ShiftOpeningSuggestion? suggestion;
  final void Function(double count, double? cashLeft)? onClose;

  @override
  Future<ShiftOpeningSuggestion> fetchOpeningSuggestion() async =>
      suggestion ?? const ShiftOpeningSuggestion();

  @override
  Future<Shift> openShift(double openingFloat) async => _openShift();

  @override
  Future<Shift> closeShift(
    int shiftId,
    double closingCount, {
    double? cashLeft,
    Map<String, int>? denominations,
  }) async {
    onClose?.call(closingCount, cashLeft);
    return _closedShift(cashLeft: cashLeft);
  }
}

Shift _openShift() => Shift.fromJson({
  'id': 4,
  'cashier_name': 'Ada',
  'status': 'OPEN',
  'opening_float': '100.00',
  'closing_count': null,
  'opened_at': '2026-01-01T08:00:00+08:00',
  'closed_at': null,
  'notes': '',
});

Shift _closedShift({double? cashLeft}) => Shift.fromJson({
  'id': 4,
  'cashier_name': 'Ada',
  'status': 'CLOSED',
  'opening_float': '100.00',
  'closing_count': '250.00',
  'cash_left_in_drawer': cashLeft?.toStringAsFixed(2),
  'opened_at': '2026-01-01T08:00:00+08:00',
  'closed_at': '2026-01-01T18:00:00+08:00',
  'notes': '',
  'z_reading': {
    'transaction_count': 3,
    'gross_sales': '150.00',
    'cash_sales': '150.00',
    'card_sales': '0.00',
    'gcash_sales': '0.00',
    'expected_drawer': '250.00',
    'variance': '0.00',
    'cash_taken_out': '250.00',
  },
});

/// The cart's state behind the switch, without a catalogue round trip.
class _FakeCart extends PosTransactionViewmodel {
  _FakeCart(this._linesUnderTest) : super(InventoryViewmodel());

  final List<PosCartLine> _linesUnderTest;
  bool _on = false;

  @override
  List<PosCartLine> get lines => _linesUnderTest;

  @override
  bool get hasCreditMarkup => true;

  @override
  bool get creditSale => _on;

  @override
  void setCreditSale(bool value) {
    _on = value;
    notifyListeners();
  }

  @override
  double get subtotal =>
      _linesUnderTest.fold(0, (sum, line) => sum + line.total);

  @override
  double get creditTotal =>
      _linesUnderTest.fold(0, (sum, line) => sum + line.creditTotal);

  @override
  double get total => creditSale ? creditTotal : subtotal;

}

void main() {
  // `ApiClient.init()` is not idempotent; the fake shift service still uses the
  // real singleton's `dio`, so it is initialised once for the whole file.
  setUpAll(() => ApiClient.instance.init());

  testWidgets('a CLEARED last drawer prefills 0.00 and stays editable', (
    tester,
  ) async {
    final viewmodel = ShiftViewmodel(
      service: _FakeShiftService(
        suggestion: const ShiftOpeningSuggestion(
          suggestedFloat: 0,
          cleared: true,
        ),
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ShiftViewmodel>.value(
        value: viewmodel,
        child: const MaterialApp(
          home: Scaffold(body: PosOpeningFloatForm()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    // Prefilled with the REAL 0.00 the server sent - not a blank box the
    // cashier might read as "nothing to count".
    expect(tester.widget<TextField>(field).controller!.text, '0.00');
    expect(
      find.textContaining('The last shift cleared the drawer'),
      findsOneWidget,
    );

    // Editable: the cashier always counts and may correct the prefill.
    await tester.enterText(field, '1500');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '1500');
  });

  testWidgets('the close sends what stays in the drawer, or an explicit 0', (
    tester,
  ) async {
    final captured = <double?>[];
    final viewmodel = ShiftViewmodel(
      service: _FakeShiftService(onClose: (_, cashLeft) => captured.add(cashLeft)),
    );
    await viewmodel.openShift(100);

    await tester.pumpWidget(
      ChangeNotifierProvider<ShiftViewmodel>.value(
        value: viewmodel,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showShiftCloseDialog(context, viewmodel),
                child: const Text('close'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Cash counted'), '250');
    await tester.enterText(
      find.widgetWithText(TextField, 'Cash left in drawer'),
      '50',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Close shift'));
    await tester.pumpAndSettle();

    expect(captured, [50.0]);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Second close: "Drawer cleared" records a REAL 0.00, not "not recorded".
    await viewmodel.openShift(100);
    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Cash counted'), '250');
    await tester.tap(find.text('Drawer cleared'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Close shift'));
    await tester.pumpAndSettle();

    expect(captured, [50.0, 0.0]);
  });

  testWidgets('the utang switch changes the preview, never an agreed price', (
    tester,
  ) async {
    const orderLine = PosCartLine(
      variantUomId: 8,
      productName: 'Wire',
      variantName: 'Standard',
      quantity: 2,
      unit: 'PC',
      unitPrice: 10,
      availableQuantity: 10,
      creditUnitPrice: 10.5,
    );
    final cart = _FakeCart([orderLine]);

    await tester.pumpWidget(
      ChangeNotifierProvider<PosTransactionViewmodel>.value(
        value: cart,
        child: const MaterialApp(home: Scaffold(body: PosCreditPriceToggle())),
      ),
    );
    await tester.pumpAndSettle();

    expect(cart.creditSale, isFalse);
    expect(cart.total, 20, reason: 'cash price is the default');

    await tester.tap(find.byKey(const ValueKey('credit-sale-switch')));
    await tester.pumpAndSettle();

    expect(cart.creditSale, isTrue);
    expect(cart.total, 21, reason: 'preview follows credit prices');
    // The line's own agreed/cash price is untouched by the preview.
    expect(cart.lines.single.unitPrice, 10);
    expect(cart.lines.single.total, 20);
  });
}
