import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/printing/roll_printer.dart';
import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/bodega/widgets/receipt_scanner.dart'
    show cameraScanAvailable, scanReceiptWithCamera;
import 'package:client/features/pos/widgets/receipt_document.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Opens [PosAttachOrDialog] with the app's real service, camera scan and roll
/// printer (store-ops Phase 1).
///
/// One helper so the till and the manager's sales sheet open the SAME dialog: a
/// second copy would drift from this one's 409 handling and reprint path.
Future<void> openAttachOrDialog(BuildContext context) async {
  // Compared by role CODE, never label (the Phase 4 lesson): 'sales' is the
  // Store Manager area and 'admin' is the Admin one - the two roles the server
  // admits to `replace: true`.
  final auth = Provider.of<AuthViewmodel?>(context, listen: false);
  final canReplace = auth?.hasAnyArea(const {'sales', 'admin'}) ?? false;
  await showDialog<void>(
    context: context,
    builder: (_) => PosAttachOrDialog(
      canReplace: canReplace,
      scanSlip: cameraScanAvailable
          ? (dialogContext) => scanReceiptWithCamera(dialogContext)
          : null,
      attach: ({required number, required invoiceNo, required replace}) =>
          PosRepository(PosService()).attachInvoice(
            number: number,
            invoiceNo: invoiceNo,
            replace: replace,
          ),
    ),
  );
}

/// Attaches the paper BIR Official Receipt's Invoice number to a sale the
/// customer brought back (store-ops Phase 1).
///
/// The customer may come back days later holding the Order Slip. The cashier
/// types (or scans) the OS number and the Invoice number written on the paper
/// OR, the sale is tagged, and the slip can be reprinted with
/// `OR Invoice No.` on it.
///
/// Injected callbacks rather than a service, for the same reason
/// `PosReceiptDialog` takes a `ReceiptPrinter`: a widget test asserts what the
/// dialog sends and shows without a server and without a printer.
class PosAttachOrDialog extends StatefulWidget {
  const PosAttachOrDialog({
    super.key,
    required this.attach,
    this.scanSlip,
    this.canReplace = false,
    this.onReprint,
  });

  /// Sends the request and answers the FULL tagged sale.
  final Future<PosCheckoutResult> Function({
    required String number,
    required String invoiceNo,
    required bool replace,
  })
  attach;

  /// Camera QR scan, offered only where the platform has it (Android). A USB
  /// scanner needs no button: it types into the focused field.
  final Future<String?> Function(BuildContext context)? scanSlip;

  /// True for a Store Manager / Admin: only they may REPLACE a number that is
  /// already on the slip, and the server refuses it (403) for anyone else.
  final bool canReplace;

  /// Injected by tests; the app prints through the same roll path as checkout.
  final void Function(PosCheckoutResult sale)? onReprint;

  static const numberFieldKey = ValueKey('attach-or-number-field');
  static const invoiceFieldKey = ValueKey('attach-or-invoice-field');
  static const replaceCheckboxKey = ValueKey('attach-or-replace');
  static const reprintKey = ValueKey('attach-or-reprint');

  @override
  State<PosAttachOrDialog> createState() => _PosAttachOrDialogState();
}

class _PosAttachOrDialogState extends State<PosAttachOrDialog> {
  final _number = TextEditingController();
  final _invoice = TextEditingController();
  bool _replace = false;
  bool _submitting = false;
  String? _error;
  String? _errorCode;

  /// The number already on the slip, when the server refused a second one.
  String? _existingInvoiceNo;
  PosCheckoutResult? _tagged;

  @override
  void dispose() {
    _number.dispose();
    _invoice.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final scanned = await widget.scanSlip?.call(context);
    if (!mounted || scanned == null) return;
    final cleaned = scanned.trim();
    if (cleaned.isEmpty) return;
    _number.text = cleaned;
  }

  Future<void> _submit() async {
    final number = _number.text.trim();
    final invoiceNo = _invoice.text.trim();
    if (number.isEmpty) {
      setState(() {
        _error = 'Type the OS number printed on the slip.';
        _errorCode = null;
      });
      return;
    }
    if (invoiceNo.isEmpty) {
      setState(() {
        _error = 'Type the Invoice number written on the paper OR.';
        _errorCode = null;
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _errorCode = null;
      _existingInvoiceNo = null;
    });
    try {
      final sale = await widget.attach(
        number: number,
        invoiceNo: invoiceNo,
        replace: _replace,
      );
      if (!mounted) return;
      setState(() {
        _tagged = sale;
        _submitting = false;
      });
    } on PosServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.message;
        _errorCode = error.code;
        // The server names the number already on the slip; a manager needs to
        // read it back to the customer before replacing it.
        _existingInvoiceNo = error.code == 'INVOICE_ALREADY_TAGGED'
            ? _invoiceFromMessage(error.message)
            : null;
      });
    }
  }

  /// `This sale is already tagged with OR invoice no. BIR-0001. Ask a Store …`
  static String? _invoiceFromMessage(String message) {
    final match = RegExp(r'invoice no\.\s*(\S+?)\.').firstMatch(message);
    return match?.group(1);
  }

  void _reprint(PosCheckoutResult sale) {
    final injected = widget.onReprint;
    if (injected != null) {
      injected(sale);
      return;
    }
    // The app's own path: the same ESC/POS slip the till prints after a sale.
    RollPrinter().print(
      buildReceiptEscPos(sale.toReceipt()),
      job: sale.orNumber,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tagged = _tagged;
    return AlertDialog(
      title: const Text('Attach OR invoice'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: tagged == null ? _form() : _done(tagged),
        ),
      ),
      actions: tagged == null
          ? [
              TextButton(
                onPressed: _submitting ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting ? 'Attaching…' : 'Attach'),
              ),
            ]
          : [
              FilledButton(
                key: PosAttachOrDialog.reprintKey,
                onPressed: () => _reprint(tagged),
                child: const Text('Reprint slip'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
    );
  }

  Widget _form() {
    final conflict = _errorCode == 'INVOICE_ALREADY_TAGGED';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: PosAttachOrDialog.numberFieldKey,
          controller: _number,
          // Auto-focused so a USB QR scanner - which types like a keyboard -
          // lands here with no click.
          autofocus: true,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'OS number or transaction no.',
            helperText: 'Printed on the Order Slip the customer is holding.',
            suffixIcon: widget.scanSlip == null
                ? null
                : IconButton(
                    tooltip: 'Scan the OS QR code',
                    onPressed: _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: PosAttachOrDialog.invoiceFieldKey,
          controller: _invoice,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'OR / Invoice no.',
            helperText: 'The number written on the paper Official Receipt (OR).',
          ),
        ),
        if (conflict && widget.canReplace) ...[
          const SizedBox(height: AppSpacing.sm),
          CheckboxListTile(
            key: PosAttachOrDialog.replaceCheckboxKey,
            value: _replace,
            onChanged: (value) => setState(() => _replace = value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Replace the number already on this slip'),
          ),
        ],
        if (conflict && !widget.canReplace) ...[
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'A Store Manager or an Admin has to replace an invoice number '
            'that is already on a slip.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            _error!,
            style: const TextStyle(color: AppColors.error, fontSize: 13),
          ),
          if (_existingInvoiceNo != null)
            Text(
              'On the slip now: ${_existingInvoiceNo!}',
              style: const TextStyle(fontSize: 13),
            ),
        ],
      ],
    );
  }

  Widget _done(PosCheckoutResult sale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${sale.transactionNo} · OS ${sale.orNumber}'),
        Text('Total ${formatPeso(sale.grandTotal)}'),
        Text(
          'OR Invoice No.: ${sale.invoiceNo}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
