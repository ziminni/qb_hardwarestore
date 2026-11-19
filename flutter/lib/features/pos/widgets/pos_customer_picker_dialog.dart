import 'package:client/core/constants/app_colors.dart';
import 'package:client/data/models/customer.dart';
import 'package:client/data/services/customer_profile_store.dart';
import 'package:client/shared/widgets/status_badge.dart';
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
    this.onCreate,
    this.includeSavedProfiles = false,
    this.onManageCustomers,
  });

  /// The live customer list, already loaded by the caller.
  final List<Customer> customers;

  /// Set when the list could not be loaded, so the dialog can say so rather than look empty.
  final String? loadError;

  /// Optional legacy create callback (customer creation now lives on the
  /// dedicated Cashier Customers page).
  final Future<(Customer?, String?)> Function(String name, CustomerType type)?
  onCreate;

  /// When true, merges [customers] with locally stored regular customer
  /// profiles from [CustomerProfileStore] (such as Mang Kanor and Manang Rosa).
  final bool includeSavedProfiles;

  /// Optional callback to open the full Cashier Customers page (`/pos/customers`).
  final VoidCallback? onManageCustomers;

  @override
  State<PosCustomerPickerDialog> createState() =>
      _PosCustomerPickerDialogState();
}

class _PosCustomerPickerDialogState extends State<PosCustomerPickerDialog> {
  String _query = '';

  List<Customer> get _allNamed {
    if (!widget.includeSavedProfiles) {
      return widget.customers.where((c) => !c.isWalkIn).toList();
    }
    return [
      for (final entry in CustomerProfileStore.instance.mergeCustomers(
        widget.customers,
      ))
        entry.customer,
    ];
  }

  List<Customer> get _visible {
    final query = _query.trim().toLowerCase();
    // The Walk-in placeholder is offered as the explicit Anonymous row instead, so it does
    // not appear twice and a cashier cannot pick it as if it were a real account.
    final named = _allNamed;
    if (query.isEmpty) return named;
    return named.where((c) {
      if (c.name.toLowerCase().contains(query)) return true;
      final profile = CustomerProfileStore.instance.resolveFor(c);
      if (profile == null) return false;
      return profile.phone.toLowerCase().contains(query) ||
          profile.address.toLowerCase().contains(query) ||
          (profile.discountBadgeLabel?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Who is this sale for?'),
      content: SizedBox(
        width: 420,
        child: _buildPicker(context),
      ),
      actions: [
        if (widget.onManageCustomers != null)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              widget.onManageCustomers!();
            },
            icon: const Icon(Icons.people_outline_rounded, size: 18),
            label: const Text('Customers page'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            const PosCustomerSelection.anonymous(),
          ),
          child: const Text('Walk-in (anonymous)'),
        ),
      ],
    );
  }

  Widget _buildPicker(BuildContext context) {
    final error = widget.loadError;
    if (error != null && !widget.includeSavedProfiles) {
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
              'No customer matches. Add regular customers on the Customers page.',
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
                final profile = CustomerProfileStore.instance.resolveFor(
                  customer,
                );
                final contactText = profile?.wireContactDetails ?? '';
                final subtitleText = contactText.isNotEmpty
                    ? '${customer.type.label} · $contactText'
                    : customer.type.label;
                return ListTile(
                  dense: true,
                  title: Text(customer.name),
                  subtitle: Text(
                    subtitleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: profile?.discountBadgeLabel != null
                      ? StatusBadge(
                          label: profile!.discountBadgeLabel!,
                          tone: StatusTone.success,
                        )
                      : null,
                  onTap: () =>
                      Navigator.pop(context, PosCustomerSelection.of(customer)),
                );
              },
            ),
          ),
      ],
    );
  }
}
