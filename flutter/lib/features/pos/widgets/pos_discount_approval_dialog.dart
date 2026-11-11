import 'package:client/data/services/discount_approval_service.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';

/// Asks a Store Manager or Admin to stand at the till and sign off a discount
/// above the Admin's cap (Phase 4 F4, decision 18).
///
/// Two rules the code below enforces rather than documents:
///
/// * The password is written to the request body and nowhere else: it is not
///   stored in a viewmodel, not kept after the dialog closes, not logged and not
///   put in the approval token. The server verifies it and answers with a token.
/// * The approver's ROLE is checked on the server. A cashier who somehow knows
///   another cashier's password still cannot approve, because a cashier does not
///   hold the approving role.
///
/// Pops with the token string on approval, or null when the manager closes it.
class PosDiscountApprovalDialog extends StatefulWidget {
  const PosDiscountApprovalDialog({
    super.key,
    required this.percent,
    required this.reason,
    this.service,
  });

  /// The discount, as a share of the gross, that is being approved.
  final double percent;

  /// The reason the cashier wrote, sent with the request and audited by the server.
  final String reason;

  /// Injected by tests; the app builds the real one.
  final DiscountApprovalService? service;

  @override
  State<PosDiscountApprovalDialog> createState() =>
      _PosDiscountApprovalDialogState();
}

class _PosDiscountApprovalDialogState extends State<PosDiscountApprovalDialog> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    // The password lives in this controller and dies with the dialog: nothing
    // outside keeps a copy.
    _password.clear();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final percent = widget.percent.toStringAsFixed(2);
    return AppDialog(
      icon: Icons.admin_panel_settings_outlined,
      title: 'Manager approval needed',
      subtitle:
          'This discount is $percent%, above the cashier cap. A Store Manager or '
          'Admin signs it off here.',
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _approve,
          child: Text(_submitting ? 'Approving' : 'Approve discount'),
        ),
      ],
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _username,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Approver username'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Enter a username' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) {
                if (!_submitting) _approve();
              },
              decoration: const InputDecoration(labelText: 'Password'),
              validator: (value) =>
                  (value ?? '').isEmpty ? 'Enter a password' : null,
            ),
            if (_error case final message?) ...[
              const SizedBox(height: 12),
              Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'The password is checked by the server and is not saved.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final approval = await (widget.service ?? DiscountApprovalService())
          .request(
            username: _username.text.trim(),
            password: _password.text,
            percent: widget.percent,
            reason: widget.reason,
          );
      if (!mounted) return;
      Navigator.pop(context, approval.token);
    } on DiscountApprovalException catch (error) {
      // The password stays OUT of the message: the server's refusal is about the
      // credentials as a pair, and echoing what was typed would put it on screen.
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = error.message;
        });
      }
    } finally {
      // Clear the field after every attempt, refused or not.
      _password.clear();
    }
  }
}
