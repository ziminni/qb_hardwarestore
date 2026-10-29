import 'package:client/features/labels/label_document.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Hands a label PDF to the platform.
///
/// An interface rather than two direct `Printing` calls so a widget test can assert
/// WHAT would be printed without the printing plugin (and without a printer).
abstract class LabelPrinter {
  /// Opens the OS print dialog with one page per sticker.
  Future<void> print(List<LabelRequest> requests);

  /// Writes the same PDF to a file the user picks (Save PDF / share sheet).
  Future<void> savePdf(List<LabelRequest> requests);
}

/// The real one: `printing` on all four targets (decision 14).
class PdfLabelPrinter implements LabelPrinter {
  const PdfLabelPrinter();

  @override
  Future<void> print(List<LabelRequest> requests) {
    return Printing.layoutPdf(
      name: 'labels',
      onLayout: (_) => buildLabelPdfWithOpenSans(requests),
    );
  }

  @override
  Future<void> savePdf(List<LabelRequest> requests) async {
    await Printing.sharePdf(
      bytes: await buildLabelPdfWithOpenSans(requests),
      filename: 'labels.pdf',
    );
  }
}

/// The label picker: one row per selling unit, a copies field for the QB ones.
class LabelPrintDialog extends StatefulWidget {
  const LabelPrintDialog({
    super.key,
    required this.requests,
    this.printer,
    this.allowSkip = false,
  });

  final List<LabelRequest> requests;

  /// Injected by tests; the app uses [PdfLabelPrinter].
  final LabelPrinter? printer;

  /// When true a row may be set to 0, meaning "not this unit".
  ///
  /// Receiving needs it: a delivery pre-fills the base unit and leaves the other
  /// units of the variant at 0.
  final bool allowSkip;

  @override
  State<LabelPrintDialog> createState() => _LabelPrintDialogState();
}

class _LabelPrintDialogState extends State<LabelPrintDialog> {
  final _formKey = GlobalKey<FormState>();
  late final List<TextEditingController> _copies = [
    for (final request in widget.requests)
      TextEditingController(text: '${request.copies}'),
  ];

  /// Shown when the dialog refuses to generate anything (nothing selected, or the
  /// printer itself failed).
  String? _error;

  LabelPrinter get _printer => widget.printer ?? const PdfLabelPrinter();

  @override
  void dispose() {
    for (final controller in _copies) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Print labels'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < widget.requests.length; index++)
                  _row(index),
                if (_error case final message?) ...[
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          onPressed: () => _submit(print: false),
          child: const Text('Save PDF'),
        ),
        FilledButton(
          onPressed: () => _submit(print: true),
          child: const Text('Print'),
        ),
      ],
    );
  }

  Widget _row(int index) {
    final request = widget.requests[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${request.productName} · ${request.variantName} · '
              '${request.unitName}\n${request.code}',
            ),
          ),
          if (!request.code.startsWith('QB'))
            const Text('Factory barcode — skipped')
          else
            SizedBox(
              width: 110,
              child: TextFormField(
                controller: _copies[index],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Copies'),
                validator: _validateCopies,
              ),
            ),
        ],
      ),
    );
  }

  /// One rule for every row: a whole number of copies, 1..200 — or 0 for a row the
  /// user is deliberately leaving out, which only the Receiving pre-fill offers.
  String? _validateCopies(String? value) {
    final text = (value ?? '').trim();
    final copies = int.tryParse(text);
    if (copies == null) return 'Enter a whole number of copies';
    if (copies < 0) return 'Copies cannot be negative';
    if (copies == 0 && !widget.allowSkip) return 'At least 1 copy per label';
    if (copies > labelMaxCopies) {
      return 'At most $labelMaxCopies copies per unit';
    }
    return null;
  }

  /// What the user actually asked for: the edited copies, with skipped rows left
  /// out, so the PDF page count is exactly what was typed.
  List<LabelRequest> _requested() => [
    for (var index = 0; index < widget.requests.length; index++)
      if (_copiesFor(index) case final copies? when copies > 0)
        LabelRequest(
          code: widget.requests[index].code,
          productName: widget.requests[index].productName,
          variantName: widget.requests[index].variantName,
          unitName: widget.requests[index].unitName,
          copies: copies,
        ),
  ];

  /// The copies typed on a printable row, or null when the row is skipped (an EAN
  /// row has no field at all).
  int? _copiesFor(int index) {
    if (!widget.requests[index].code.startsWith('QB')) return null;
    return int.tryParse(_copies[index].text.trim());
  }

  Future<void> _submit({required bool print}) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final requests = _requested();
    if (requests.isEmpty) {
      setState(() => _error = 'Choose at least one copy to print.');
      return;
    }
    setState(() => _error = null);
    try {
      if (print) {
        await _printer.print(requests);
      } else {
        await _printer.savePdf(requests);
      }
    } catch (error) {
      // A refused print must not lose the picker: the user retries or saves.
      if (mounted) setState(() => _error = 'Could not print the labels: $error');
      return;
    }
    if (mounted) Navigator.pop(context);
  }
}
