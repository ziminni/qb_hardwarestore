import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';

/// Who you buy from: the shared dialog frame around five plain fields.
///
/// Nothing about the form itself changed when it joined the family. It still
/// returns the [Supplier] the page writes to the server, still keeps an edited
/// supplier's id and active flag, and still refuses an empty company name with
/// the same sentence.
class SuppliersFormDialog extends StatefulWidget {
  const SuppliersFormDialog({super.key, this.supplier});
  final Supplier? supplier;
  @override
  State<SuppliersFormDialog> createState() => _SuppliersFormDialogState();
}

class _SuppliersFormDialogState extends State<SuppliersFormDialog> {
  final _key = GlobalKey<FormState>();
  late final _company = TextEditingController(
    text: widget.supplier?.companyName ?? '',
  );
  late final _contact = TextEditingController(
    text: widget.supplier?.contactPerson ?? '',
  );
  late final _phone = TextEditingController(text: widget.supplier?.phone ?? '');
  late final _email = TextEditingController(text: widget.supplier?.email ?? '');
  late final _address = TextEditingController(
    text: widget.supplier?.address ?? '',
  );

  /// The payment window a bill's due date is built from (Phase 5 B2). Blank
  /// means 0, the server's own default: due on receipt.
  late final _termsDays = TextEditingController(
    text: (widget.supplier?.termsDays ?? 0) == 0
        ? ''
        : '${widget.supplier!.termsDays}',
  );
  @override
  void dispose() {
    _company.dispose();
    _contact.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _termsDays.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    icon: Icons.storefront_outlined,
    title: widget.supplier == null ? 'Add Supplier' : 'Edit Supplier',
    subtitle: 'The company you order materials from.',
    width: 560,
    content: Form(
      key: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const DialogSectionLabel('Supplier details'),
          TextFormField(
            controller: _company,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Company Name'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter the company name.'
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _contact,
            decoration: const InputDecoration(labelText: 'Contact Person'),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _address,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Address'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const ValueKey('supplier-terms-days'),
            controller: _termsDays,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Payment terms (days)',
              helperText:
                  'A bill falls due this many days after the goods arrive. '
                  'Leave blank for due on receipt.',
              helperMaxLines: 2,
            ),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return null;
              final parsed = int.tryParse(text);
              if (parsed == null) return 'Enter a whole number of days.';
              if (parsed < 0) return 'Payment terms must be 0 or more days.';
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          // Neutral guidance: a deactivated supplier disappears from the order
          // form's list, which surprises a user who expects a delete action.
          const InfoBanner(
            message:
                'Purchase orders and Receiving only offer active suppliers.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_key.currentState!.validate()) return;
          Navigator.pop(
            context,
            Supplier(
              id: widget.supplier?.id ?? 0,
              companyName: _company.text.trim(),
              contactPerson: _contact.text.trim(),
              phone: _phone.text.trim(),
              email: _email.text.trim(),
              address: _address.text.trim(),
              isActive: widget.supplier?.isActive ?? true,
              termsDays: int.tryParse(_termsDays.text.trim()) ?? 0,
            ),
          );
        },
        child: const Text('Save Supplier'),
      ),
    ],
  );
}
