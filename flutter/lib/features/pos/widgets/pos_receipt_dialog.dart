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
              Text(
                'Payment: ${receipt.isSplit ? 'Split (${receipt.payments.length} tenders)' : TenderMethod.labelFor(receipt.paymentMethod)}',
              ),
              const Divider(height: 28),
              ...receipt.lines.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
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
                      // Phase 5 B4: where THIS line is picked up. Hidden when the
                      // sale recorded no place: an invented "Store" would tell the
                      // customer to collect goods from somewhere nobody chose.
                      if (line.storedAtName.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Pick up at ${line.storedAtName.trim()}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              // Lines, then the discount, then what was owed: the same order the
              // paper receipt prints (decision 18).
              if (receipt.discountAmount > 0)
                _amountRow(
                  receiptDiscountLabel(receipt.discountReason),
                  -receipt.discountAmount,
                ),
              // The fee added AFTER the discount (decision 18). Hidden at 0 so a
              // carried-out sale prints no charge line.
              if (receipt.deliveryFee > 0)
                _amountRow('Delivery charge', receipt.deliveryFee),
              _amountRow('Total', receipt.total),
              if (receipt.vatRegistered) ...[
                _amountRow('Vatable sales', receipt.vatableSales),
                _amountRow(receiptVatLabel(receipt.vatRate), receipt.vatAmount),
              ] else
                _textRow('VAT', 'Non-VAT'),
              // Every tender on its own line: a split sale must never be
              // summarised into one method, and a cheque says it is PENDING.
              for (final payment in receipt.payments)
                _textRow(
                  payment.isPending
                      ? '${TenderMethod.labelFor(payment.method)} '
                            '${payment.chequeNumber.isEmpty ? '' : '${payment.chequeNumber} '}'
                            '(pending)'
                      : TenderMethod.labelFor(payment.method),
                  formatPeso(payment.amount),
                ),
              // Money RECEIVED: the tenders the server calls money in hand, so a
              // pending cheque is not printed as paid.
              _amountRow('Paid', receipt.paidNow),
              // Money in hand and a cheque the bank has not honoured are two
              // different facts; adding them would claim a debt was settled.
              if (receipt.pendingChequeTotal > 0)
                _amountRow(
                  'Cheque pending (not paid yet)',
                  receipt.pendingChequeTotal,
                ),
              // An underpaid sale owes the shortfall as utang; printing it as
              // negative change reads like money the till handed back.
              if (receipt.balanceDue > 0)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        receipt.pendingChequeTotal > 0
                            ? 'Balance due (held by the cheque)'
                            : 'Balance due (utang)',
                      ),
                    ),
                    Text(formatPeso(receipt.balanceDue)),
                  ],
                )
              else
                // QA High (Phase 4 close): the SERVER's `change_given`, never the
                // till's own recomputation from the tender rows.
                _amountRow('Change', receipt.changeGiven),
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
      if (mounted) {
        setState(() => _error = 'Could not print the receipt: $error');
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Widget _amountRow(String label, double value) =>
      _textRow(label, formatPeso(value));

  Widget _textRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value),
      ],
    ),
  );
}
