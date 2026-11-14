import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';

/// Writes off what is not going to happen (Phase 7 F1, decision 19 #4).
///
/// A cancellation is a manager's reasoned act: the sentence is what survives
/// everyone's memory of why the customer backed out, so the confirm button does
/// nothing until one is typed, and the server refuses an empty reason with
/// `SALES_ORDER_REASON_REQUIRED` even if this dialog is bypassed.
///
/// [onSubmit] returns null when the server accepted the cancellation, or the
/// refusal to show. A refusal keeps this dialog OPEN with the reason intact —
/// "the goods are already on their way" is a fact the manager has to read before
/// deciding what to do instead.
class SalesOrderCancelDialog extends StatefulWidget {
  const SalesOrderCancelDialog({
    super.key,
    required this.orderNumber,
    required this.onSubmit,
  });

  final String orderNumber;
  final Future<SalesServiceException?> Function(String reason) onSubmit;

  @override
  State<SalesOrderCancelDialog> createState() => _SalesOrderCancelDialogState();
}

class _SalesOrderCancelDialogState extends State<SalesOrderCancelDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  bool _submitting = false;
  String? _refusal;

  /// The server's `cancel_reason` column is 255; refused here first so a long
  /// sentence is an answer, not a round trip into a 400.
  static const int _maxReason = 255;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _refusal = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    final refusal = await widget.onSubmit(_reason.text.trim());
    if (!mounted) return;
    if (refusal == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _submitting = false;
      _refusal = refusal.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.block_outlined,
      title: 'Cancel sales order',
      subtitle:
          'Order ${widget.orderNumber} is written off. Nothing already rung '
          'into a sale is touched.',
      width: 560,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('so-cancel-reason'),
              controller: _reason,
              autofocus: true,
              maxLength: _maxReason,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Why is this order not going ahead?',
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'A cancellation needs a reason: it goes into the audit '
                        'trail.'
                  : null,
            ),
            if (_refusal case final refusal?) ...[
              const SizedBox(height: AppSpacing.md),
              ErrorBanner(message: refusal),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Keep the order'),
        ),
        FilledButton(
          key: const ValueKey('so-cancel-confirm'),
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Cancelling…' : 'Cancel order'),
        ),
      ],
    );
  }
}
