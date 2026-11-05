import 'package:client/core/format/format.dart';
import 'package:client/data/models/pos_transaction.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/features/pos/widgets/receipt_document.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Hands a receipt PDF to the platform.
///
/// An interface for the same reason as `LabelPrinter`: a widget test asserts
/// WHAT would be printed without the printing plugin or a printer.
abstract class ReceiptPrinter {
  Future<void> print(PosReceipt receipt);
}

/// The real one: the OS print dialog, so any printer the OS knows (a USB or
/// Bluetooth thermal printer included) takes the 80 mm roll.
class PdfReceiptPrinter implements ReceiptPrinter {
  const PdfReceiptPrinter();

  @override
  Future<void> print(PosReceipt receipt) {
    return Printing.layoutPdf(
      name: receipt.officialReceiptNumber,
      format: receiptPageFormat,
      onLayout: (_) => buildReceiptPdfWithOpenSans(receipt),
    );
  }
}

class PosReceiptDialog extends StatefulWidget {
  const PosReceiptDialog({super.key, required this.receipt, this.printer});
  final PosReceipt receipt;

  /// Injected by tests; the app uses [PdfReceiptPrinter].
  final ReceiptPrinter? printer;

  @override
  State<PosReceiptDialog> createState() => _PosReceiptDialogState();
}

class _PosReceiptDialogState extends State<PosReceiptDialog> {
  bool _printing = false;

  /// Shown when the print failed; the sale itself is already recorded.
  String? _error;

  PosReceipt get receipt => widget.receipt;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.check_circle_outline),
          SizedBox(width: 10),
          Text('Transaction complete'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Reference: ${receipt.reference}'),
              Text('Receipt: ${receipt.officialReceiptNumber}'),
              // The receipt carries the wire CODE; the cashier reads the label.
              // A legacy row holds the label already, and labelFor returns it as-is.
              Text('Payment: ${TenderMethod.labelFor(receipt.paymentMethod)}'),
              const Divider(height: 28),
              ...receipt.lines.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          // Z1 (D18): the product and its variant are two parts
                          // of one line, joined by a middle dot.
                          '${line.productName} · ${line.variantName}\n${formatQuantity(line.quantity)} ${line.unit}',
                        ),
                      ),
                      Text(formatPeso(line.total)),
                    ],
                  ),
                ),
              ),
              const Divider(),
              _amountRow('Total', receipt.total),
              _amountRow('Paid', receipt.amountPaid),
              // An underpaid named-customer sale owes the shortfall as utang; printing
              // it as negative change reads like money the till handed back.
              if (receipt.change < 0)
                _amountRow('Balance due (utang)', -receipt.change)
              else
                _amountRow('Change', receipt.change),
              const SizedBox(height: 12),
              const Text(
                'Inventory quantities were updated in the current app session.',
              ),
              if (_error case final message?) ...[
                const SizedBox(height: 12),
                Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: _printing ? null : _print,
          icon: const Icon(Icons.print_outlined, size: 18),
          label: const Text('Print receipt'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('New transaction'),
        ),
      ],
    );
  }

  Future<void> _print() async {
    setState(() {
      _printing = true;
      _error = null;
    });
    try {
      await (widget.printer ?? const PdfReceiptPrinter()).print(receipt);
    } catch (error) {
      // A refused print keeps the dialog: the cashier retries or moves on.
      if (mounted) setState(() => _error = 'Could not print the receipt: $error');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Widget _amountRow(String label, double value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(formatPeso(value)),
      ],
    ),
  );
}
