// Phase 3 Task F1: the catalogue export dialog and the file it hands to the
// platform.
//
// Same shape as `BarcodeListDialog`: the exporter is an interface so a widget test
// can assert WHAT would be written without a save dialog, a browser download or a
// real path. A cancelled save is not an error and says nothing.

import 'package:client/core/format/format.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/catalogue_io/catalogue_sheet.dart';
import 'package:client/features/catalogue_io/catalogue_xlsx.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// Where the save dialog said to write, or null when the user cancelled.
typedef SaveLocationPicker = Future<String?> Function(String suggestedName);

/// Writes the workbook. Behind an interface for the same reason the barcode list
/// is: the test asserts the payload, not the plugin.
abstract class CatalogueExporter {
  Future<void> saveXlsx(CatalogueSheetData data);
}

/// The real one: `file_selector` for the location, `XFile.saveTo` for the write.
///
/// `saveTo` already does the right thing on both targets with the packages this
/// app depends on: on web it clicks a download link built from the bytes, on
/// desktop it writes to the path the Save dialog returned.
class CatalogueFileExporter implements CatalogueExporter {
  const CatalogueFileExporter({this.pickLocation = _pickXlsxLocation});

  static const xlsxName = 'catalogue.xlsx';

  final SaveLocationPicker pickLocation;

  @override
  Future<void> saveXlsx(CatalogueSheetData data) async {
    final path = await pickLocation(xlsxName);
    // Cancelled: silence is right, nothing was lost.
    if (path == null) return;
    await XFile.fromData(
      catalogueXlsxBytes(rows: data.rows, lists: data.lists),
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      name: xlsxName,
    ).saveTo(path);
  }
}

Future<String?> _pickXlsxLocation(String suggestedName) async {
  final location = await getSaveLocation(suggestedName: suggestedName);
  return location?.path;
}

/// "Export catalogue": says how much is going into the file, then saves it.
///
/// The catalogue it is handed is the WHOLE one, archived products included: the
/// Active column carries the archive flag, so a round trip changes nothing.
class CatalogueIoDialog extends StatefulWidget {
  const CatalogueIoDialog({
    super.key,
    required this.products,
    required this.lists,
    this.unitsOf,
    this.exporter,
  });

  final List<Product> products;

  /// Categories, unit codes, locations and brands for the Lists sheet.
  final CatalogueSheetLists lists;

  /// The selling units the store holds, when they are fresher than the nested
  /// catalogue rows (see [catalogueSheetRows]).
  final List<VariantUom> Function(ProductVariant variant)? unitsOf;

  /// Injected by tests; the app uses [CatalogueFileExporter].
  final CatalogueExporter? exporter;

  @override
  State<CatalogueIoDialog> createState() => _CatalogueIoDialogState();
}

class _CatalogueIoDialogState extends State<CatalogueIoDialog> {
  /// Shown when the save was refused (an unwritable path). The dialog stays open
  /// so the user can pick another place.
  String? _error;

  CatalogueExporter get _exporter =>
      widget.exporter ?? const CatalogueFileExporter();

  Future<void> _export(List<CatalogueSheetRow> rows) async {
    setState(() => _error = null);
    try {
      await _exporter.saveXlsx(
        CatalogueSheetData(rows: rows, lists: widget.lists),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not save the catalogue: $error');
      }
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final rows = catalogueSheetRows(
      widget.products,
      unitsOf: widget.unitsOf,
    );
    final products = widget.products
        .where((product) => rows.any((row) => row.productId == product.id))
        .length;

    return AppDialog(
      icon: Icons.table_view_outlined,
      title: 'Export catalogue',
      subtitle: 'Edit the catalogue in Excel, then bring it back.',
      width: 560,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${formatCount(rows.length)} '
            '${rows.length == 1 ? 'row' : 'rows'} for '
            '${formatCount(products)} '
            '${products == 1 ? 'product' : 'products'}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'One row per selling unit, archived products included. The second '
            'sheet lists the categories, unit codes, locations and brands the '
            'file accepts. Stock is never part of the file.',
          ),
          if (rows.isEmpty) ...[
            const SizedBox(height: 12),
            const Text('The catalogue has no selling units to export yet.'),
          ],
          if (_error case final message?) ...[
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: rows.isEmpty ? null : () => _export(rows),
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: const Text('Save .xlsx'),
        ),
      ],
    );
  }
}
