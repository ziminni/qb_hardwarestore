import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/catalogue_io/stock_records_xlsx.dart';
import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stockRecordsXlsxBytes writes live stock quantities, values, SKUs and leading-zero barcodes', () {
    final p = Product(
      id: 1,
      categoryId: 2,
      categoryName: 'Plumbing',
      brandId: 3,
      brandName: 'Omni',
      baseName: '=Faucet',
      description: '',
      imageUrl: '',
      isActive: true,
      storedAtName: 'Store',
      variants: [
        ProductVariant(
          id: 10,
          productId: 1,
          variantName: 'Per Piece',
          sku: '00123-FAUCET',
          baseUomId: 1,
          baseUomCode: 'PC',
          minStockThreshold: 5,
          maxStockLevel: 0,
          isActive: true,
          sellingUoms: const [
            VariantUom(
              id: 101,
              variantId: 10,
              uomId: 1,
              uomCode: 'PC',
              uomName: 'Piece',
              barcodeQr: '0012345678905',
              conversionFactor: 1,
              defaultSellingPrice: 250,
            ),
          ],
        ),
      ],
    );

    final rows = stockRecordSheetRows(
      records: [(product: p, variant: p.variants.single)],
      stockOnHandFor: (_) => 12,
      costFor: (_) => 150.5,
      statusForVariant: (_) => InventoryStockStatus.inStock,
    );

    final bytes = stockRecordsXlsxBytes(rows);
    final excel = Excel.decodeBytes(bytes);
    expect(excel.tables.keys, [stockRecordsSheetName]);

    final sheet = excel[stockRecordsSheetName];
    expect(
      sheet.rows[0].map((c) => c?.value.toString()).toList(),
      stockRecordsSheetHeaders,
    );

    final dataRow = sheet.rows[1];
    expect(dataRow[0]?.value.toString(), "'=Faucet"); // formula-safe
    expect(dataRow[1]?.value.toString(), 'Per Piece');
    expect(dataRow[2]?.value, isA<TextCellValue>());
    expect(dataRow[2]?.value.toString(), '00123-FAUCET');
    expect(dataRow[5]?.value.toString(), 'Store');
    expect(dataRow[7]?.value.toString(), '12'); // On hand
    expect(dataRow[10]?.value.toString(), '150.5'); // Unit cost
    expect(dataRow[11]?.value.toString(), '1806'); // Stock value (12 * 150.5)
    expect(dataRow[12]?.value.toString(), '250'); // Selling price
    expect(dataRow[13]?.value, isA<TextCellValue>());
    expect(dataRow[13]?.value.toString(), '0012345678905');
  });
}
