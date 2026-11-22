import 'package:client/features/catalogue_io/catalogue_import_dialog.dart';
import 'package:client/features/catalogue_io/catalogue_io_dialog.dart';
import 'package:client/features/catalogue_io/catalogue_sheet.dart';
import 'package:client/features/catalogue_io/catalogue_xlsx.dart';
import 'package:client/features/catalogue_io/stock_records_xlsx.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/labels/barcode_list_dialog.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// The stocker's import / export actions, in ONE place so the Products page
// buttons and the Import & export page open exactly the same dialogs.

/// The barcode masterlist (Phase 4 F2): every code, printable or as CSV.
///
/// Handed the WHOLE catalogue: the masterlist has its own filters.
Future<void> openBarcodeList(BuildContext context) async {
  final inventory = context.read<InventoryViewmodel>();
  await showDialog<void>(
    context: context,
    builder: (_) => BarcodeListDialog(
      products: inventory.products,
      unitsOf: (variant) =>
          inventory.variantFor(variant.id)?.sellingUoms ?? variant.sellingUoms,
    ),
  );
}

/// The catalogue workbook export (Phase 3 F1). No stock anywhere in the file.
Future<void> openCatalogueExport(BuildContext context) async {
  final inventory = context.read<InventoryViewmodel>();
  await showDialog<void>(
    context: context,
    builder: (_) => CatalogueIoDialog(
      products: inventory.products,
      lists: CatalogueSheetLists.fromSources(
        categories: inventory.categories,
        units: inventory.units,
        locations: inventory.storageLocations,
        brands: inventory.brands,
      ),
      unitsOf: (variant) =>
          inventory.variantFor(variant.id)?.sellingUoms ?? variant.sellingUoms,
    ),
  );
}

/// The catalogue workbook import (Phase 3 F2): preview first, apply on Apply,
/// then the catalogue reloads.
Future<void> openCatalogueImport(BuildContext context) async {
  final inventory = context.read<InventoryViewmodel>();
  await showDialog<void>(
    context: context,
    builder: (_) => CatalogueImportDialog(onApplied: inventory.load),
  );
}

/// The import template (owner 2026-11-18): the catalogue workbook's exact
/// headings, example rows with BLANK IDs (so they create), the Lists sheet from
/// this shop's own names, and a "How to fill" sheet.
///
/// [saveTo] is injectable for tests; by default a Save dialog picks the path.
Future<void> downloadImportTemplate(
  BuildContext context, {
  Future<String?> Function(String suggestedName)? pickLocation,
}) async {
  final inventory = context.read<InventoryViewmodel>();
  final messenger = ScaffoldMessenger.of(context);
  final lists = CatalogueSheetLists.fromSources(
    categories: inventory.categories,
    units: inventory.units,
    locations: inventory.storageLocations,
    brands: inventory.brands,
  );
  const name = 'catalogue-import-template.xlsx';
  try {
    final pick =
        pickLocation ??
        (String suggested) async =>
            (await getSaveLocation(suggestedName: suggested))?.path;
    final path = await pick(name);
    if (path == null) return;
    await XFile.fromData(
      catalogueXlsxBytes(
        rows: catalogueTemplateRows(lists),
        lists: lists,
        instructions: catalogueTemplateInstructions,
      ),
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      name: name,
    ).saveTo(path);
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not save the template: $error')),
    );
    return;
  }
  messenger.showSnackBar(
    const SnackBar(
      content: Text(
        'Template saved. Replace the example rows, then use Import catalogue '
        'from Excel.',
      ),
    ),
  );
}

/// Exports the live stock records (quantities, cost, stock value, status,
/// selling price, storage location, SKU, barcode) as an Excel workbook.
Future<void> exportStockRecordsToExcel(
  BuildContext context, {
  Future<String?> Function(String suggestedName)? pickLocation,
}) async {
  final inventory = context.read<InventoryViewmodel>();
  final messenger = ScaffoldMessenger.of(context);
  final rows = stockRecordSheetRows(
    records: [
      for (final record in inventory.stockRecords)
        (product: record.product, variant: record.variant),
    ],
    stockOnHandFor: inventory.stockOnHandFor,
    costFor: inventory.costFor,
    statusForVariant: inventory.statusForVariant,
    unitsOf: (variant) =>
        inventory.variantFor(variant.id)?.sellingUoms ?? variant.sellingUoms,
  );
  if (rows.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No stock records available to export.')),
    );
    return;
  }
  const name = 'stock-records.xlsx';
  try {
    final pick =
        pickLocation ??
        (String suggested) async =>
            (await getSaveLocation(suggestedName: suggested))?.path;
    final path = await pick(name);
    if (path == null) return;
    await XFile.fromData(
      stockRecordsXlsxBytes(rows),
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      name: name,
    ).saveTo(path);
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not save stock records: $error')),
    );
    return;
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text('Saved ${rows.length} stock record(s) to $name.'),
    ),
  );
}
