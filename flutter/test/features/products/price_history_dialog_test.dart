import 'package:client/core/format/format.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/products/widgets/products_details_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

/// Row detail the product timeline owes the reader: the opening price and the
/// date each change happened, besides the unit and its source.
void main() {
  final older = DateTime.utc(2026, 11, 18, 8, 0);
  final newer = DateTime.utc(2026, 11, 20, 9, 30);

  final units = [
    const PriceHistoryUnit(variantUomId: 1001, label: 'PC'),
    const PriceHistoryUnit(variantUomId: 1002, label: 'BOX (×10)'),
  ];

  Future<void> pumpHistory(
    WidgetTester tester,
    Future<List<PriceHistoryEntry>> Function(int unitId) loader,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => PriceHistoryDialog(
                  title: 'Latex Paint',
                  units: units,
                  loader: loader,
                ),
              ),
              child: const Text('open history'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open history'));
    await tester.pumpAndSettle();
  }

  Map<int, List<PriceHistoryEntry>> stubHistory() => {
    1002: [
      PriceHistoryEntry(
        oldPrice: 90,
        newPrice: 100,
        changedAt: older,
        actor: 'Ana Cruz',
        source: 'CATALOGUE',
      ),
      PriceHistoryEntry(
        oldPrice: 100,
        newPrice: 110,
        changedAt: newer,
        actor: 'Ana Cruz',
        source: 'ADMIN',
      ),
    ],
    1001: [
      PriceHistoryEntry(
        oldPrice: null,
        newPrice: 15,
        changedAt: newer.subtract(const Duration(hours: 1)),
        actor: 'Ana Cruz',
        source: 'ADMIN',
      ),
    ],
  };

  testWidgets('empty state when no unit has a recorded change', (
    tester,
  ) async {
    await pumpHistory(tester, (unitId) async => const <PriceHistoryEntry>[]);

    expect(find.byType(ListTile), findsNothing);
    expect(
      find.text('No price changes recorded yet for these selling units.'),
      findsOneWidget,
    );
  });

  testWidgets('product details opens the same product-wide timeline', (
    tester,
  ) async {
    final trade = product(
      id: 7,
      name: 'Latex Paint',
      variants: [
        variant(
          id: 70,
          productId: 7,
          name: 'White 1L',
          baseUomCode: 'PC',
          sellingUoms: const [
            VariantUom(
              id: 1001,
              variantId: 70,
              uomId: 1,
              uomCode: 'PC',
              uomName: 'Piece',
              barcodeQr: 'QB000701-1',
              conversionFactor: 1,
              defaultSellingPrice: 15,
            ),
            VariantUom(
              id: 1002,
              variantId: 70,
              uomId: 2,
              uomCode: 'BOX',
              uomName: 'Box',
              barcodeQr: 'QB000702-2',
              conversionFactor: 10,
              defaultSellingPrice: 100,
            ),
          ],
        ),
      ],
    );
    final inventory = InventoryViewmodel.seeded(
      products: [trade],
      batches: const [],
    );
    final byUnit = stubHistory();
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
          ChangeNotifierProvider<AuthViewmodel>.value(
            value: AuthViewmodel(AuthRepository(AuthService())),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ProductsDetailsDialog(
                    product: trade,
                    priceHistoryLoader: (unitId) async =>
                        byUnit[unitId] ?? const <PriceHistoryEntry>[],
                  ),
                ),
                child: const Text('open details'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open details'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('product-price-history-7')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Price History'), findsOneWidget);
    // Both selling units of the product, not only the one the reader was on.
    expect(find.text('${formatPeso(90)} → ${formatPeso(100)}'), findsOneWidget);
    expect(find.text('Initial price: ${formatPeso(15)}'), findsOneWidget);
    expect(find.textContaining('BOX (×10) · Catalogue'), findsOneWidget);
    expect(find.textContaining('PC · Admin'), findsOneWidget);
  });

  testWidgets('every unit row carries its date and source, meter to peso kept', (
    tester,
  ) async {
    final byUnit = stubHistory();
    await pumpHistory(tester, (unitId) async => byUnit[unitId] ?? const []);

    expect(find.text('Price History'), findsOneWidget);
    // A first price has no old side, and still gets the peso format.
    expect(find.text('Initial price: ${formatPeso(15)}'), findsOneWidget);
    expect(find.text('${formatPeso(90)} → ${formatPeso(100)}'), findsOneWidget);
    expect(find.text('${formatPeso(100)} → ${formatPeso(110)}'), findsOneWidget);

    expect(
      find.textContaining(
        'BOX (×10) · Admin · by Ana Cruz · ${formatDateTime(newer.toLocal())}',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'PC · Admin · by Ana Cruz · '
        '${formatDateTime(newer.subtract(const Duration(hours: 1)).toLocal())}',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'BOX (×10) · Catalogue · by Ana Cruz · ${formatDateTime(older.toLocal())}',
      ),
      findsOneWidget,
    );
  });
}
