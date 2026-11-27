// Offline workbook smoke test: run with `dart run tool/workbook_smoke.dart`.
// No server, credentials, production data or file picker is involved.
import 'dart:io';
import 'package:client/data/models/reports.dart';
import 'package:client/features/admin/reports_excel_export.dart';
import 'package:client/features/catalogue_io/catalogue_import_sheet.dart';
import 'package:client/features/catalogue_io/catalogue_sheet.dart';
import 'package:client/features/catalogue_io/catalogue_xlsx.dart';
import 'package:client/features/catalogue_io/stock_records_xlsx.dart';
import 'package:excel_community/excel_community.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final sales = SalesSummary.fromJson({
    'from': '2026-10-01',
    'to': '2026-10-31',
    'totals': {'transactions': 2, 'gross_sales': '1000.00'},
    'by_day': [],
    'by_payment_method': [
      {'method': 'CASH', 'total': '650.00'},
      {'method': 'ON_ACCOUNT', 'total': '350.00'},
    ],
  });
  check(
    sales.byPaymentMethod.values.fold<double>(
          0,
          (sum, amount) => sum + amount,
        ) ==
        sales.totalGross,
    'Payment allocation must reconcile',
  );
  final report = Excel.decodeBytes(buildSalesReportXlsx(sales));
  final payments = report['Payment Allocation'].rows;
  check(
    payments[2][0]?.value.toString() == 'On account (utang)',
    'On-account allocation missing',
  );
  check(
    payments[3][1]?.value.toString() == '1000',
    'Payment allocation total incorrect',
  );
  stdout.writeln('PASS sales Excel allocation reconciles');

  final catalogue = catalogueXlsxBytes(
    lists: const CatalogueSheetLists.empty(),
    rows: const [
      CatalogueSheetRow(
        productId: 1,
        variantId: 2,
        unitId: 3,
        category: 'Cement',
        brand: 'Test',
        productName: 'Portland cement',
        variantName: 'Bag',
        unitCode: 'BAG',
        unitsPerBase: 1,
        price: 265.50,
        barcode: '0012345678905',
        lowStockThreshold: 10,
        storedAt: 'Store',
        active: true,
      ),
    ],
  );
  final parsed = parseCatalogueSheet(catalogue).single.values;
  check(parsed['barcode'] == '0012345678905', 'Barcode leading zeros lost');
  check(
    double.parse(parsed['price']!) == 265.5,
    'Catalogue price did not round-trip',
  );
  check(
    !parsed.containsKey('on_hand'),
    'Catalogue import must not change stock',
  );
  stdout.writeln('PASS catalogue Excel export/import round-trip');

  final inventory = Excel.decodeBytes(
    stockRecordsXlsxBytes(const [
      StockRecordSheetRow(
        productName: 'Portland cement',
        variantName: 'Bag',
        sku: '001-CEMENT',
        category: 'Cement',
        brand: 'Test',
        storedAt: 'Store',
        unitCode: 'BAG',
        onHand: 9.75,
        lowStockThreshold: 10,
        statusLabel: 'Low stock',
        unitCost: 100,
        stockValue: 975,
        sellingPrice: 265.5,
        barcode: '0012345678905',
      ),
    ]),
  );
  final record = inventory[stockRecordsSheetName].rows[1];
  check(record[7]?.value.toString() == '9.75', 'Fractional stock rounded');
  check(record[11]?.value.toString() == '975', 'Stock value incorrect');
  check(
    record[13]?.value.toString() == '0012345678905',
    'Stock barcode leading zeros lost',
  );
  stdout.writeln(
    'PASS stock workbook preserves fractional quantities and barcode',
  );
}
