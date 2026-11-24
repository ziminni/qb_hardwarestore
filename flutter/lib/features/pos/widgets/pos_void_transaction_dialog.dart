import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:flutter/material.dart';

/// Confirmation dialog to void a completed POS sale with a required reason.
///
/// Owns its [TextEditingController] in State so disposal happens safely after
/// the route exit animation finishes.
Future<bool> showVoidTransactionDialog(
  BuildContext context, {
  required InventorySale sale,
  PosService? service,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _VoidTransactionDialog(
      sale: sale,
      service: service ?? PosService(),
    ),
  );
  return result ?? false;
}

class _VoidTransactionDialog extends StatefulWidget {
  const _VoidTransactionDialog({required this.sale, required this.service});

  final InventorySale sale;
  final PosService service;

  @override
  State<_VoidTransactionDialog> createState() => _VoidTransactionDialogState();
}

class _VoidTransactionDialogState extends State<_VoidTransactionDialog> {
  final _reasonController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final saleId = widget.sale.id;
    if (saleId == null) {
      setState(() => _error = 'This transaction cannot be voided.');
      return;
    }
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Enter a reason for voiding this transaction.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.service.voidTransaction(saleId, reason: reason);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PosServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not void this transaction. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;
    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.block_rounded,
              color: AppColors.error,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Text(
              'Void Transaction',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        sale.transactionNo,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        formatPeso(sale.amountDue),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${sale.customer}${sale.orNumber.isNotEmpty ? ' · ${sale.orNumber}' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Voiding restores deducted stock batches, removes any uncollected utang balance, and deducts this sale from shift totals.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('void-reason-input'),
              controller: _reasonController,
              enabled: !_submitting,
              autofocus: true,
              maxLength: 255,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason for voiding *',
                hintText: 'e.g. Wrong item rung, customer cancelled at counter',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const ValueKey('void-confirm-button'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.block_rounded, size: 18),
          label: Text(_submitting ? 'Voiding...' : 'Confirm Void'),
        ),
      ],
    );
  }
}
