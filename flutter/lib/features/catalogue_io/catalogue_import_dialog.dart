// Phase 3 Task F2: "Import from Excel", preview first.
//
// Pick the file, then this dialog says what the import WOULD do: how many records
// it creates, which fields it changes, which rows are already right and every cell
// the server refused. Nothing is written: APPLY belongs to the next step (backend
// B2, `POST .../apply/`), so the button is there, disabled, with a tooltip saying
// when it arrives. The fingerprint and the rows the preview read stay on
// `CatalogueImportViewmodel`, which is all an apply needs to send.
//
// A cancelled file pick is silence, exactly like a cancelled save in F1: nothing
// was lost, so nothing is said.

import 'dart:typed_data';

import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/catalogue_import_preview.dart';
import 'package:client/data/services/catalogue_import_service.dart';
import 'package:client/features/catalogue_io/catalogue_import_viewmodel.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// The one file type the import accepts. `xlsx` only: the export writes a real
/// workbook, and an older `.xls` is a different format this app cannot read.
const catalogueXlsxTypeGroup = XTypeGroup(
  label: 'Excel workbook',
  extensions: ['xlsx'],
  mimeTypes: [
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  ],
  uniformTypeIdentifiers: ['org.openxmlformats.spreadsheetml.sheet'],
);

/// The picked workbook's bytes, or null when the clerk cancelled.
typedef CatalogueSheetPicker = Future<Uint8List?> Function();

/// The real picker: `file_selector` on both targets, then the bytes.
///
/// Behind a function so a widget test injects a file instead of opening an OS
/// dialog, the same seam `CatalogueExporter` gives the export.
Future<Uint8List?> pickCatalogueSheet() async {
  final file = await openFile(
    acceptedTypeGroups: const [catalogueXlsxTypeGroup],
  );
  // Cancelled: silence is right, nothing was lost.
  if (file == null) return null;
  return file.readAsBytes();
}

/// What the file would change, before anything changes.
class CatalogueImportDialog extends StatefulWidget {
  const CatalogueImportDialog({
    super.key,
    this.picker = pickCatalogueSheet,
    this.service,
    this.onApplied,
  });

  /// Injected by tests; the app opens the OS file dialog.
  final CatalogueSheetPicker picker;

  /// Injected by tests; the app talks to the server.
  final CatalogueImportService? service;

  /// Run once an apply WROTE something: the products list behind this dialog is
  /// now out of date. The products page passes its catalogue reload.
  final Future<void> Function()? onApplied;

  @override
  State<CatalogueImportDialog> createState() => _CatalogueImportDialogState();
}

class _CatalogueImportDialogState extends State<CatalogueImportDialog> {
  late final CatalogueImportViewmodel _viewModel = CatalogueImportViewmodel(
    service: widget.service,
  );

  @override
  void initState() {
    super.initState();
    _viewModel.addListener(_onChanged);
    _open();
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onChanged);
    _viewModel.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _open() async {
    final Uint8List? bytes;
    try {
      // Reading the file off disk can fail before there is a sheet to parse, and
      // that failure belongs in the same one banner the rest of the preview uses.
      bytes = await widget.picker();
    } catch (_) {
      if (mounted) _viewModel.reportUnreadableFile();
      return;
    }
    if (!mounted) return;
    if (bytes == null) {
      Navigator.pop(context);
      return;
    }
    await _viewModel.openSheet(bytes);
  }

  /// The Excel row a preview row means, for the clerk to go and fix.
  int _sheetRow(int previewRow) => _viewModel.sheetRowOf(previewRow);

  /// Writes the previewed file, then reloads the products list behind the dialog:
  /// the counts on that screen are the ones the apply just changed.
  Future<void> _apply() async {
    await _viewModel.apply();
    if (_viewModel.applied != null) await widget.onApplied?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.upload_file_outlined,
      title: 'Import catalogue',
      subtitle: 'Check what the file changes before you apply it.',
      // Wide enough that a desktop window draws the error table as a table; a
      // narrow one turns the same rows into cards (DataPanel decides).
      width: 820,
      content: _body(context),
      actions: _actions(context),
    );
  }

  List<Widget> _actions(BuildContext context) {
    // A write that already happened is done: the only thing left is closing, so
    // there is no button here that could send it again.
    if (_viewModel.applied != null) {
      return [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      _applyAction(),
    ];
  }

  Widget _applyAction() {
    if (_viewModel.isApplying) {
      return const FilledButton(
        onPressed: null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.sm),
            Text('Applying'),
          ],
        ),
      );
    }
    // Disabled until a clean preview and its fingerprint are in hand; the body
    // says what is missing, so the button carries no tooltip of its own.
    return FilledButton(
      onPressed: _viewModel.canApply ? _apply : null,
      child: const Text('Apply import'),
    );
  }

  Widget _body(BuildContext context) {
    if (_viewModel.applied case final applied?) {
      return _Applied(summary: applied.summary);
    }

    if (_viewModel.isPreviewing || _isIdle) return const _Reading();

    if (_viewModel.error case final message?) {
      if (!_viewModel.isStale) return ErrorBanner(message: message);
      // The catalogue moved: the rows are still here, so one click reads them
      // again instead of making the clerk pick the file a second time.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ErrorBanner(message: message),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _viewModel.previewAgain,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Preview again'),
            ),
          ),
        ],
      );
    }

    final preview = _viewModel.preview;
    if (preview == null) return const _NothingPicked();

    // An apply refusal is the later word on the same rows, so it is what the
    // table shows when there is one.
    final errors = _viewModel.errors;
    final changes = preview.changes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_counts(preview), style: Theme.of(context).textTheme.titleMedium),
        if (errors.isEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Apply writes these changes to the catalogue.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (errors.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          const ErrorBanner(
            message: 'Fix these cells in Excel, then import the file again.',
          ),
          const SizedBox(height: AppSpacing.md),
          DataPanel<CatalogueImportError>(
            title: 'Errors',
            count: errors.length,
            rows: errors,
            emptyMessage: 'No row errors.',
            rowKey: (error) =>
                ValueKey('import-error.${error.row}.${error.code}'),
            columns: [
              DataPanelColumn<CatalogueImportError>(
                label: 'Row',
                cell: (error) => Text('${_sheetRow(error.row)}'),
              ),
              DataPanelColumn<CatalogueImportError>(
                label: 'Column',
                cell: (error) => Text(error.column),
              ),
              DataPanelColumn<CatalogueImportError>(
                label: 'Message',
                flex: 3,
                cell: (error) => Text(error.message, maxLines: 2),
              ),
            ],
          ),
        ],
        if (changes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          DataPanel<CatalogueImportChange>(
            title: 'Changes',
            count: changes.length,
            rows: changes,
            emptyMessage: 'No field changes.',
            rowKey: (change) =>
                ValueKey('import-change.${change.row}.${change.field}'),
            columns: [
              DataPanelColumn<CatalogueImportChange>(
                label: 'Row',
                cell: (change) => Text('${_sheetRow(change.row)}'),
              ),
              DataPanelColumn<CatalogueImportChange>(
                label: 'Column',
                cell: (change) => Text(change.field),
              ),
              DataPanelColumn<CatalogueImportChange>(
                label: 'Before',
                cell: (change) => Text(
                  change.before.isEmpty ? 'Blank' : change.before,
                  maxLines: 2,
                ),
              ),
              DataPanelColumn<CatalogueImportChange>(
                label: 'After',
                cell: (change) => Text(
                  change.after.isEmpty ? 'Blank' : change.after,
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Shown before the first answer arrives, so the dialog is not an empty frame
  /// while the file is being read.
  bool get _isIdle => _viewModel.preview == null && _viewModel.error == null;

  /// What the import would do, in the order a clerk asks it: what is new, what
  /// changes, what stays as it is. Zeros are kept, so "nothing new" is a fact
  /// read off the file and not a line that quietly disappeared.
  String _counts(CatalogueImportPreview preview) {
    final creates = preview.creates;
    final changes = preview.changes.length;
    final unchanged = preview.unchanged;
    return [
      _count(creates.products, 'new product', 'new products'),
      _count(creates.variants, 'new variant', 'new variants'),
      _count(creates.units, 'new selling unit', 'new selling units'),
      changes == 0 ? 'No changes' : _count(changes, 'change', 'changes'),
      _count(unchanged, 'row unchanged', 'rows unchanged'),
    ].join(', ');
  }

  String _count(int value, String singular, String plural) =>
      '${formatCount(value)} ${value == 1 ? singular : plural}';
}

class _Applied extends StatelessWidget {
  const _Applied({required this.summary});

  /// The server's own sentence, the one it keeps in the audit trail, so the
  /// clerk reads exactly what was recorded.
  final String summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(summary, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'The products list is up to date.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: AppSpacing.md),
        Text('Reading the sheet'),
      ],
    );
  }
}

class _NothingPicked extends StatelessWidget {
  const _NothingPicked();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Pick the catalogue workbook to see what importing it would change.',
    );
  }
}
