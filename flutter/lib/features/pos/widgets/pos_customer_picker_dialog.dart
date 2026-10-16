import 'package:client/core/constants/app_colors.dart';
import 'package:client/data/models/customer.dart';
import 'package:flutter/material.dart';

/// The picker's answer.
///
/// A wrapper rather than a bare `Customer?` because `null` already means "the cashier
/// cancelled" when a dialog pops, and decision 14 needs THREE outcomes: cancelled (change
/// nothing), anonymous (the default sale), and a named account. Overloading null would make
/// "go back to anonymous" indistinguishable from "never mind".
class PosCustomerSelection {
  const PosCustomerSelection({this.customer});

  /// The anonymous choice: a walk-in, reusing the seeded placeholder, creating nothing.
  const PosCustomerSelection.anonymous() : customer = null;

  /// A named account.
  const PosCustomerSelection.of(Customer this.customer);

  final Customer? customer;

  bool get isAnonymous => customer == null;
}

/// Choose who a sale is for, or record a new customer on the spot.
///
/// Decision 14: the default is ANONYMOUS and the counter never asks an anonymous buyer for
/// anything. "New customer" records a **name and type only** - the cashier is not asked for a
/// TIN, contact details or a credit limit, because credit control is not the till's job.
class PosCustomerPickerDialog extends StatefulWidget {
  const PosCustomerPickerDialog({
    super.key,
    required this.customers,
    required this.loadError,
    required this.onCreate,
  });

  /// The live customer list, already loaded by the caller.
  final List<Customer> customers;

  /// Set when the list could not be loaded, so the dialog can say so rather than look empty.
  final String? loadError;

  /// Records a customer and returns it, or returns an error message on failure.
  final Future<(Customer?, String?)> Function(String name, CustomerType type)
  onCreate;

  @override
  State<PosCustomerPickerDialog> createState() => _PosCustomerPickerDialogState();
}

class _PosCustomerPickerDialogState extends State<PosCustomerPickerDialog> {
  String _query = '';
  bool _creating = false;

  final _nameController = TextEditingController();
  CustomerType _type = CustomerType.regular;
  String? _createError;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  List<Customer> get _visible {
    final query = _query.trim().toLowerCase();
    // The Walk-in placeholder is offered as the explicit Anonymous row instead, so it does
    // not appear twice and a cashier cannot pick it as if it were a real account.
    final named = widget.customers.where((c) => !c.isWalkIn);
    if (query.isEmpty) return named.toList();
    return named
        .where((c) => c.name.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _createError = 'Enter the customer\'s name.');
      return;
    }
    setState(() {
      _saving = true;
      _createError = null;
    });
    final (created, error) = await widget.onCreate(name, _type);
    if (!mounted) return;
    if (created == null) {
      setState(() {
        _saving = false;
        _createError = error ?? 'The customer could not be recorded.';
      });
      return;
    }
    Navigator.pop(context, PosCustomerSelection.of(created));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Who is this sale for?'),
      content: SizedBox(
        width: 420,
        child: _creating ? _buildCreateForm(context) : _buildPicker(context),
      ),
      actions: _creating
          ? [
              TextButton(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                        _creating = false;
                        _createError = null;
                      }),
                child: const Text('Back'),
              ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Recording…' : 'Save and use'),
              ),
            ]
          : [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, const PosCustomerSelection.anonymous()),
                child: const Text('Walk-in (anonymous)'),
              ),
              TextButton(
                onPressed: () => setState(() => _creating = true),
                child: const Text('New customer'),
              ),
            ],
    );
  }

  Widget _buildPicker(BuildContext context) {
    final error = widget.loadError;
    if (error != null) {
      return Text(error, style: const TextStyle(color: AppColors.error));
    }
    final visible = _visible;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Search customers',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'No customer matches. Record one with "New customer".',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final customer = visible[index];
                return ListTile(
                  dense: true,
                  title: Text(customer.name),
                  subtitle: Text(customer.type.label),
                  onTap: () => Navigator.pop(
                    context,
                    PosCustomerSelection.of(customer),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildCreateForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: 14),
        const Text('Type', style: TextStyle(fontWeight: FontWeight.w600)),
        // All FOUR types, including Construction Firm: the model and the migration carry it,
        // and this project has two business entities.
        Wrap(
          spacing: 8,
          children: [
            for (final type in CustomerType.values)
              if (type != CustomerType.unknown)
                ChoiceChip(
                  label: Text(type.label),
                  selected: _type == type,
                  onSelected: (_) => setState(() => _type = type),
                ),
          ],
        ),
        if (_createError != null) ...[
          const SizedBox(height: 12),
          Text(_createError!, style: const TextStyle(color: AppColors.error)),
        ],
      ],
    );
  }
}
