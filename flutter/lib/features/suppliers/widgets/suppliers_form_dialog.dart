import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/supplier.dart';
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
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.supplier == null ? 'Add Supplier' : 'Edit Supplier'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Form(
          key: _key,
          child: Column(
            children: [
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
            ],
          ),
        ),
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
