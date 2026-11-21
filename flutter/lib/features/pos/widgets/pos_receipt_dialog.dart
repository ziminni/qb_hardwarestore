import 'package:client/core/format/format.dart';
import 'package:client/core/printing/roll_printer.dart';
import 'package:client/data/models/pos_transaction.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/features/pos/widgets/receipt_document.dart';
import 'package:flutter/material.dart';

/// Hands a receipt PDF to the platform.
///
/// An interface for the same reason as `LabelPrinter`: a widget test asserts
/// WHAT would be printed without the printing plugin or a printer.
abstract class ReceiptPrinter {
  Future<void> print(PosReceipt receipt);
}

/// The real one: ESC/POS straight to the receipt printer chosen in Settings,
/// with no print dialog and no driver in between.
///
/// Not the OS print dialog: a PDF sent through a generic driver reached a
/// thermal printer as PostScript, which it printed as text down most of a roll.
class RollReceiptPrinter implements ReceiptPrinter {
  const RollReceiptPrinter();

  @override
  Future<void> print(PosReceipt receipt) => RollPrinter().print(
    buildReceiptEscPos(receipt),
    job: receipt.officialReceiptNumber,
  );
}

class PosReceiptDialog extends StatefulWidget {
  const PosReceiptDialog({super.key, required this.receipt, this.printer});
  final PosReceipt receipt;

  /// Injected by tests; the app uses [RollReceiptPrinter].
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
  void initState() {
    super.initState();
    // Owner 2026-11-19: the receipt prints by itself once the sale is in,
    // unless the cashier turned that off in Settings. Only the app's own
    // printer does this (a test injects its printer and prints by hand), and
    // only once a receipt printer is chosen, so a till without one is never
    // greeted by an error on every sale.
    if (widget.printer == null) _autoPrint();
  }

  Future<void> _autoPrint() async {
    try {
      if (!await RollPrinter.autoPrint()) return;
      if (await RollPrinter.saved() == null) return;
    } catch (_) {
      // The setting could not be read: print nothing by itself, and let the
      // cashier press Print receipt as before.
      return;
    }
    if (mounted) await _print();
  }

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
                      if (line.discountAmount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  line.discount?.reason.trim().isNotEmpty == true
                                      ? '  Line discount (${line.discount!.reason.trim()})'
                                      : '  Line discount',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              Text(
                                '−${formatPeso(line.discountAmount)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      // Owner 2026-11-19: no "Pick up at" line; the staff know
                      // where their goods are kept.
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
    // Owner 2026-11-19: a "Printing receipt…" window while the job goes out,
    // removed by its own route once the print is done or refused.
    final navigator = Navigator.of(context);
    final printerName = (await _savedPrinterName()) ?? '';
    if (!mounted) return;
    final printingRoute = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PrintingReceiptDialog(printerName: printerName),
    );
    navigator.push(printingRoute);
    try {
      await Future.wait([
        (widget.printer ?? const RollReceiptPrinter()).print(receipt),
        // Long enough to read on the real printer, which answers in a blink;
        // a test's injected printer gets no timer.
        if (widget.printer == null)
          Future<void>.delayed(const Duration(milliseconds: 1200)),
      ]);
    } catch (error) {
      // A refused print keeps the dialog: the cashier retries or moves on.
      if (mounted) {
        setState(() => _error = 'Could not print the receipt: $error');
      }
    } finally {
      if (printingRoute.isActive) navigator.removeRoute(printingRoute);
      if (mounted) setState(() => _printing = false);
    }
  }

  /// The receipt printer's name for the printing window; null in a test or
  /// when the setting cannot be read.
  Future<String?> _savedPrinterName() async {
    if (widget.printer != null) return null;
    try {
      return (await RollPrinter.saved())?.name;
    } catch (_) {
      return null;
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

/// The "Printing receipt…" window: a spinner, the words, and which printer.
class _PrintingReceiptDialog extends StatelessWidget {
  const _PrintingReceiptDialog({required this.printerName});
  final String printerName;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        key: const ValueKey('pos-printing-receipt'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.print_outlined, size: 40),
              const SizedBox(height: 16),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 16),
              const Text(
                'Printing receipt…',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              if (printerName.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'On $printerName',
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
