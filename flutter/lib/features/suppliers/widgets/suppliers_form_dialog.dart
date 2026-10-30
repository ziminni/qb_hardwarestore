import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';

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
  @override
  void dispose() {
    _company.dispose();
    _contact.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    icon: Icons.local_shipping_outlined,
    title: widget.supplier == null ? 'Add Supplier' : 'Edit Supplier',
    subtitle:
        widget.supplier?.companyName ?? 'Register a vendor for purchase orders',
    width: 560,
    content: Form(
      key: _key,
      child: Column(
        children: [
          const DialogSectionLabel('Company'),
          TextFormField(
            controller: _company,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Company Name',
              prefixIcon: Icon(Icons.business_outlined),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter the company name.'
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _address,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Address',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const DialogSectionLabel('Contact'),
          TextFormField(
            controller: _contact,
            decoration: const InputDecoration(
              labelText: 'Contact Person',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                ),
              ),
            ],
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
            ),
          );
        },
        child: const Text('Save Supplier'),
      ),
    ],
  );
}
