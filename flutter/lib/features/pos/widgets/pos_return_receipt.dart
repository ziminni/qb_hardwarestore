import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/printing/roll_printer.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:client/data/models/returns.dart';
import 'package:client/features/pos/widgets/receipt_document.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:flutter/material.dart';

/// Hands a Return Slip to the thermal printer (injectable for tests).
abstract class ReturnSlipPrinter {
  Future<void> print(ReturnSlipData slip);
}

/// Real 58 mm ESC/POS printer implementation for Return Slips.
class RollReturnSlipPrinter implements ReturnSlipPrinter {
  const RollReturnSlipPrinter();

  @override
  Future<void> print(ReturnSlipData slip) => RollPrinter().print(
    buildReturnSlipEscPos(slip),
    job: slip.returnNo,
  );
}

/// The posted return receipt, drawn straight from the server's `ReturnResult`.
///
/// Supports auto-printing (when enabled in Settings and a printer is saved)
/// and manual reprinting so the customer copy matches Store Manager -> Returns
/// & Refunds.
class PosReturnReceipt extends StatefulWidget {
  const PosReturnReceipt({
    super.key,
    required this.result,
    required this.lines,
    required this.onStartAnother,
    this.transactionNo,
    this.customerName,
    this.cashierName,
    this.reason,
    this.printer,
  });

  final ReturnResult result;
  final String? transactionNo;
  final String? customerName;
  final String? cashierName;
  final String? reason;
  final List<({String name, String uom, double qty})> lines;
  final VoidCallback onStartAnother;

  /// Injected by tests; production uses [RollReturnSlipPrinter].
  final ReturnSlipPrinter? printer;

  @override
  State<PosReturnReceipt> createState() => _PosReturnReceiptState();
}

class _PosReturnReceiptState extends State<PosReturnReceipt> {
  bool _printing = false;
  String? _printError;
  late final DateTime _postedAt = appClock.now();

  ReturnSlipData _buildSlipData() {
    final refund = widget.result.refund;
    return ReturnSlipData(
      returnNo: widget.result.returnNo,
      transactionNo: widget.transactionNo,
      customerName: widget.customerName,
      cashierName: widget.cashierName,
      reason: widget.reason,
      printedAt: _postedAt,
      lines: widget.lines,
      returnValue: refund.returnValue,
      debtReduced: refund.debtReduced,
      cashRefund: refund.cashRefund,
      refundMethod: refund.refundMethod,
      ledgerId: refund.ledgerId,
      ledgerBalance: refund.ledgerBalance ?? 0,
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.printer == null) _autoPrint();
  }

  Future<void> _autoPrint() async {
    try {
      if (!await RollPrinter.autoPrint()) return;
      if (await RollPrinter.saved() == null) return;
    } catch (_) {
      return;
    }
    if (mounted) await _printSlip();
  }

  Future<void> _printSlip() async {
    setState(() {
      _printing = true;
      _printError = null;
    });
    try {
      await (widget.printer ?? const RollReturnSlipPrinter()).print(
        _buildSlipData(),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _printError = 'Could not print the return slip: $error');
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final refund = widget.result.refund;
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.successText),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Return posted: ${widget.result.returnNo}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.successText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (widget.transactionNo case final original?) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Against $original',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
          if (widget.lines.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            for (final line in widget.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        line.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      '${formatQuantity(line.qty)} ${line.uom}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          Text('Return value ${formatPeso(refund.returnValue)}'),
          const SizedBox(height: AppSpacing.xs),
          Text('Utang reduced ${formatPeso(refund.debtReduced)}'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Cash refunded ${formatPeso(refund.cashRefund)} '
            '(${refund.refundMethod})',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (refund.ledgerId != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('Ledger still owes ${formatPeso(refund.ledgerBalance ?? 0)}'),
          ],
          if (_printError case final message?) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('print-return-slip'),
                onPressed: _printing ? null : _printSlip,
                icon: _printing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print_outlined, size: 18),
                label: Text(_printing ? 'Printing…' : 'Print return slip'),
              ),
              OutlinedButton(
                onPressed: widget.onStartAnother,
                child: const Text('Start another return'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
