import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/labels/barcode_list_csv.dart';
import 'package:client/features/labels/barcode_list_document.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// The role CODES the server admits to reading the catalogue's codes
/// (Phase 4 Task F2, decision 18): Stock Manager (`inventory`), Store Manager
/// (`sales`) and Admin. These are codes the server sends as `role.name`, never
/// display labels — the same comparison the product details dialog and the Low
/// stock screen make.
const Set<String> catalogueCodeAreas = {'inventory', 'sales', 'admin'};

/// Whether an account HOLDING [heldAreas] may read the catalogue's codes.
///
/// Phase 2 F3 (decision 24): the gate asks the areas the account holds, because
/// a merged account has no single active area — but is still one Cashier or
/// one Stock Manager's worth of authority per area it holds.
bool canExportBarcodeList(Iterable<String> heldAreas) =>
    heldAreas.any(catalogueCodeAreas.contains);

/// Hands the masterlist to the platform: a CSV file and a PDF.
///
/// An interface rather than three direct plugin calls so a widget test can assert
/// WHAT would be written without a save dialog, a browser download or a printer.
abstract class BarcodeListExporter {
  /// Writes the CSV: a browser download on web, a Save dialog on desktop.
  Future<void> saveCsv(BarcodeListData data);

  /// Writes the PDF to a file the user picks (or downloads, on web).
  Future<void> savePdf(BarcodeListData data);

  /// Opens the OS print dialog with the same PDF.
  Future<void> printPdf(BarcodeListData data);
}

/// The real one: `printing` for the PDF, `file_selector` for the CSV.
///
/// `XFile.saveTo` already does the right thing on both targets with the packages
/// this app depends on: on web it clicks a download link built from the bytes, on
/// desktop it writes to the path the Save dialog returned. No new dependency.
class BarcodeListFileExporter implements BarcodeListExporter {
  const BarcodeListFileExporter();

  static const csvName = 'barcode-list.csv';
  static const pdfName = 'barcode-list.pdf';

  @override
  Future<void> saveCsv(BarcodeListData data) async {
    final location = await getSaveLocation(suggestedName: csvName);
    // Cancelled: silence is right, the file is still in the list.
    if (location == null) return;
    await XFile.fromData(
      barcodeListCsvBytes(data.rows),
      mimeType: 'text/csv',
      name: csvName,
    ).saveTo(location.path);
  }

  @override
  Future<void> savePdf(BarcodeListData data) async {
    await Printing.sharePdf(
      bytes: await buildBarcodeListPdfWithOpenSans(data),
      filename: pdfName,
    );
  }

  @override
  Future<void> printPdf(BarcodeListData data) {
    return Printing.layoutPdf(
      name: pdfName,
      onLayout: (_) => buildBarcodeListPdfWithOpenSans(data),
    );
  }
}

/// The barcode masterlist dialog: pick what goes on the sheet, then print, save a
/// PDF or download a CSV.
class BarcodeListDialog extends StatefulWidget {
  const BarcodeListDialog({
    super.key,
    required this.products,
    this.unitsOf,
    this.exporter,
  });

  /// The whole catalogue, not the screen's filtered rows: the masterlist has its
  /// own filters, and a storekeeper who filtered the table to one brand must still
  /// be able to print every code.
  final List<Product> products;

  /// The selling units the store holds, when they are fresher than the nested
  /// catalogue rows (see [barcodeListRowsForProduct]).
  final List<VariantUom> Function(ProductVariant variant)? unitsOf;

  /// Injected by tests; the app uses [BarcodeListFileExporter].
  final BarcodeListExporter? exporter;

  @override
  State<BarcodeListDialog> createState() => _BarcodeListDialogState();
}

class _BarcodeListDialogState extends State<BarcodeListDialog> {
  /// null means "All categories".
  String? _category;
  bool _activeOnly = true;

  /// Shown when an export was refused (a save dialog that could not be written,
  /// a printer that is not there). The dialog stays open: the choices are kept.
  String? _error;

  BarcodeListExporter get _exporter =>
      widget.exporter ?? const BarcodeListFileExporter();

  /// The categories this catalogue actually has, once each, alphabetically.
  List<String> get _categories {
    final names = widget.products
        .map((product) => product.categoryName)
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    names.sort();
    return names;
  }

  /// The filtered list, plus how many products it came from (a product with no
  /// selling unit contributes nothing and is not counted).
  ({List<BarcodeListRow> rows, int products}) _prepared() {
    final rows = <BarcodeListRow>[];
    var products = 0;
    for (final product in widget.products) {
      if (_category != null && product.categoryName != _category) continue;
      if (_activeOnly && !product.isActive) continue;
      final productRows = barcodeListRowsForProduct(
        product,
        unitsOf: widget.unitsOf,
      );
      if (productRows.isEmpty) continue;
      products++;
      rows.addAll(productRows);
    }
    return (rows: rows, products: products);
  }

  BarcodeListData _data(List<BarcodeListRow> rows) => BarcodeListData(
    rows: rows,
    generatedAt: appClock.now(),
    categoryLabel: _category ?? 'All categories',
    activeOnly: _activeOnly,
  );

  Future<void> _export(
    Future<void> Function(BarcodeListData data) write,
    List<BarcodeListRow> rows,
  ) async {
    setState(() => _error = null);
    try {
      await write(_data(rows));
    } catch (error) {
      // A refused export must not lose the filters: the user fixes the cause and
      // tries again from here.
      if (mounted) {
        setState(() => _error = 'Could not save the barcode list: $error');
      }
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final prepared = _prepared();
    final rows = prepared.rows;
    final empty = rows.isEmpty;
    final categories = _categories;

    return AppDialog(
      icon: Icons.qr_code_2_rounded,
      title: 'Barcode list',
      subtitle: 'Every selling unit with its own scannable code.',
      width: 640,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String?>(
            initialValue: _category,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('All categories'),
              ),
              for (final name in categories)
                DropdownMenuItem(
                  value: name,
                  child: Text(name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) => setState(() => _category = value),
          ),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _activeOnly,
            onChanged: (value) => setState(() => _activeOnly = value),
            title: const Text('Active products only'),
            subtitle: const Text(
              'Archived products stay out of the sheet and the file.',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _countLabel(rows.length, prepared.products),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (empty) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'No codes match these filters. Widen the category or '
              'include archived products.',
            ),
          ],
          if (_error case final message?) ...[
            const SizedBox(height: AppSpacing.md),
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
        TextButton(
          onPressed: empty ? null : () => _export(_exporter.saveCsv, rows),
          child: const Text('Download CSV'),
        ),
        OutlinedButton(
          onPressed: empty ? null : () => _export(_exporter.savePdf, rows),
          child: const Text('Save PDF'),
        ),
        FilledButton.icon(
          onPressed: empty ? null : () => _export(_exporter.printPdf, rows),
          icon: const Icon(Icons.print_outlined, size: 18),
          label: const Text('Print'),
        ),
      ],
    );
  }

  /// `3 codes from 2 products`: the sentence the plan asks for, so nobody has to
  /// count rows to know whether the filters did what they meant.
  String _countLabel(int codes, int products) =>
      '${formatCount(codes)} ${codes == 1 ? 'code' : 'codes'} from '
      '${formatCount(products)} ${products == 1 ? 'product' : 'products'}';
}
