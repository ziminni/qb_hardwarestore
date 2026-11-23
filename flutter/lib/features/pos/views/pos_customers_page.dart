import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/data/models/customer.dart';
import 'package:client/data/services/customer_profile_store.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/empty_state.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

enum _CustomerFilter {
  all('All'),
  seniorOrPwd('Senior / PWD'),
  withDiscount('With Discount'),
  regular('Regular'),
  contractor('Contractor'),
  firm('Construction Firm');

  const _CustomerFilter(this.label);
  final String label;
}

/// Cashier Customers page (`/pos/customers`):
///
/// Manages regular customer accounts and their saved transaction presets so
/// choosing a customer in "Who is this sale for?" automatically populates:
/// * **Discount section** (e.g., Mang Kanor → Senior Citizen 20% discount)
/// * **Utang details** (e.g., Manang Rosa → Name, Contact number, Address)
/// * **Delivery details** (Contact name, Contact phone, Delivery address)
/// while keeping every transaction input field editable.
class PosCustomersPage extends StatefulWidget {
  const PosCustomersPage({super.key, this.viewmodel});

  final PosTransactionViewmodel? viewmodel;

  @override
  State<PosCustomersPage> createState() => _PosCustomersPageState();
}

class _PosCustomersPageState extends State<PosCustomersPage> {
  final TextEditingController _searchController = TextEditingController();
  _CustomerFilter _filter = _CustomerFilter.all;
  String _query = '';
  bool _isLoading = false;

  late final PosTransactionViewmodel _transaction = _resolveTransaction();
  PosTransactionViewmodel? _ownedTransaction;

  PosTransactionViewmodel _resolveTransaction() {
    final injected = widget.viewmodel;
    if (injected != null) return injected;
    try {
      return context.read<PosTransactionViewmodel>();
    } on ProviderNotFoundException {
      return _ownedTransaction = PosTransactionViewmodel(
        InventoryViewmodel(),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    CustomerProfileStore.instance.addListener(_onStoreChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refresh();
    });
  }

  @override
  void dispose() {
    CustomerProfileStore.instance.removeListener(_onStoreChanged);
    _searchController.dispose();
    _ownedTransaction?.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    await CustomerProfileStore.instance.ensureLoaded();
    try {
      await _transaction.loadCustomers();
    } catch (_) {
      // Uninitialized transport in isolated widget tests: keep local profiles.
    }
    if (mounted) setState(() => _isLoading = false);
  }

  List<({Customer customer, CustomerProfile profile})> get _mergedEntries =>
      CustomerProfileStore.instance.mergeCustomers(_transaction.customers);

  List<({Customer customer, CustomerProfile profile})> get _filteredEntries {
    final q = _query.trim().toLowerCase();
    return _mergedEntries.where((entry) {
      final p = entry.profile;
      final matchesFilter = switch (_filter) {
        _CustomerFilter.all => true,
        _CustomerFilter.seniorOrPwd =>
          p.discountType == CustomerDiscountType.seniorCitizen ||
              p.discountType == CustomerDiscountType.pwd,
        _CustomerFilter.withDiscount => p.hasDiscount,
        _CustomerFilter.regular => entry.customer.type == CustomerType.regular,
        _CustomerFilter.contractor =>
          entry.customer.type == CustomerType.contractor,
        _CustomerFilter.firm =>
          entry.customer.type == CustomerType.constructionFirm,
      };
      if (!matchesFilter) return false;
      if (q.isEmpty) return true;
      return entry.customer.name.toLowerCase().contains(q) ||
          p.phone.toLowerCase().contains(q) ||
          p.address.toLowerCase().contains(q) ||
          p.idNumber.toLowerCase().contains(q) ||
          (p.discountBadgeLabel?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Future<void> _openCustomerForm({
    CustomerProfile? initial,
    Customer? existingCustomer,
  }) async {
    final result =
        await showDialog<({CustomerProfile profile, bool useInSale})>(
          context: context,
          builder: (_) => _CustomerProfileFormDialog(
            initial: initial,
            existingCustomer: existingCustomer,
          ),
        );
    if (result == null || !mounted) return;

    final savedCustomer = await _transaction.saveCustomerProfile(
      result.profile,
      previousName: initial?.name,
      selectForCurrentSale: result.useInSale,
    );
    if (result.useInSale) {
      await _transaction.loadLedgerForSelection();
    }
    if (!mounted) return;
    final discountNote = result.profile.discountBadgeLabel != null
        ? ' · ${result.profile.discountBadgeLabel}'
        : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.useInSale
              ? 'Saved ${savedCustomer.name}$discountNote and selected for current sale.'
              : 'Saved customer profile for ${savedCustomer.name}$discountNote.',
        ),
      ),
    );
  }

  Future<void> _useInSale(Customer customer, CustomerProfile profile) async {
    _transaction.selectCustomer(customer);
    await _transaction.loadLedgerForSelection();
    if (!mounted) return;

    final autoFilled = <String>[
      if (profile.discountBadgeLabel != null)
        'Discount (${profile.discountBadgeLabel})',
      if (profile.hasContactInfo) 'Utang & Delivery contact details',
    ];
    final details = autoFilled.isEmpty
        ? 'Selected for current sale.'
        : 'Auto-fills: ${autoFilled.join(' + ')}.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${customer.name} selected. $details'),
      ),
    );
  }

  void _goToTill() {
    try {
      context.go(AppRoutes.posDashboard);
    } catch (_) {
      // Fallback for isolated widget tests without GoRouter.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PosTransactionViewmodel>.value(
      value: _transaction,
      child: Builder(
        builder: (context) {
          final transaction = context.watch<PosTransactionViewmodel>();
          final p = AppPalette.of(context);
          final allEntries = _mergedEntries;
          final filtered = _filteredEntries;
          final discountCount =
              allEntries.where((e) => e.profile.hasDiscount).length;
          final contactReadyCount =
              allEntries.where((e) => e.profile.hasContactInfo).length;

          return DashboardShell(
            title: 'Customers',
            subtitle:
                'Regular customers, standing discounts, utang & delivery presets',
            selectedNavigationIndex: 9,
            navigationItems: posNavigationItems,
            onNavigationSelected: (i) => navigatePos(context, i),
            actions: [
              IconButton(
                key: const ValueKey('pos-customers-refresh'),
                tooltip: 'Refresh customers',
                onPressed: _isLoading ? null : _refresh,
                icon: const Icon(Icons.refresh_rounded, size: 19),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const ValueKey('pos-customers-add-btn'),
                onPressed: () => _openCustomerForm(),
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: AppColors.brandBlack,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text(
                  'Add customer',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildActiveBuyerBanner(context, transaction, p),
                const SizedBox(height: 16),
                _buildSummaryStrip(
                  context,
                  p,
                  totalCount: allEntries.length,
                  discountCount: discountCount,
                  contactReadyCount: contactReadyCount,
                ),
                const SizedBox(height: 16),
                FilterBar(
                  searchController: _searchController,
                  onSearchChanged: (value) => setState(() => _query = value),
                  searchHint:
                      'Search by customer name, phone, address, or Senior / PWD discount…',
                  optionsLabel: 'FILTER',
                  options: [
                    for (final chip in _CustomerFilter.values) chip.label,
                  ],
                  selected: _filter.label,
                  onSelected: (label) {
                    final matched = _CustomerFilter.values
                        .where((c) => c.label == label)
                        .firstOrNull;
                    if (matched != null) {
                      setState(() => _filter = matched);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: p.cardBackground,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: p.border),
                  ),
                  child: filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: EmptyState(
                            icon: Icons.people_outline_rounded,
                            message: _query.trim().isNotEmpty
                                ? 'No matching customers. Try clearing your search or add a new regular customer.'
                                : 'Add regular customers to auto-fill discounts, utang, and delivery details.',
                            actionLabel: 'Add customer',
                            onAction: () => _openCustomerForm(),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTableHeader(p),
                            Divider(height: 1, color: p.border),
                            for (var i = 0; i < filtered.length; i++) ...[
                              if (i > 0) Divider(height: 1, color: p.border),
                              _buildCustomerRow(
                                context,
                                p,
                                transaction,
                                filtered[i].customer,
                                filtered[i].profile,
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildActiveBuyerBanner(
    BuildContext context,
    PosTransactionViewmodel transaction,
    AppPalette p,
  ) {
    final buyer = transaction.selectedCustomer;
    final profile = transaction.selectedCustomerProfile;
    final isNamed = buyer != null && !buyer.isWalkIn;

    return Container(
      key: const ValueKey('pos-active-sale-buyer-banner'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isNamed ? p.selected : p.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isNamed ? p.accent : p.border,
          width: isNamed ? 1.5 : 1,
        ),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isNamed ? p.accent : p.surfaceMuted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isNamed
                      ? Icons.person_pin_rounded
                      : Icons.person_outline_rounded,
                  color: isNamed ? AppColors.brandBlack : p.textSecondary,
                ),
              ),
              const SizedBox(width: 14),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'WHO IS THIS SALE FOR',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.9,
                            color: isNamed ? p.accentInk : p.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusBadge(
                          label: isNamed ? buyer.type.label : 'Anonymous',
                          tone: isNamed
                              ? StatusTone.info
                              : StatusTone.neutral,
                        ),
                        if (profile?.discountBadgeLabel != null) ...[
                          const SizedBox(width: 6),
                          StatusBadge(
                            label: profile!.discountBadgeLabel!,
                            tone: StatusTone.success,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      transaction.customerLabel,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isNamed
                          ? _activeAutoFillSummary(profile)
                          : 'Choose a regular customer below to automatically fill in Discount, Utang, and Delivery details.',
                      style: TextStyle(fontSize: 12.5, color: p.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (isNamed)
                OutlinedButton.icon(
                  key: const ValueKey('pos-customers-clear-buyer'),
                  onPressed: () {
                    transaction.selectCustomer(null);
                    transaction.loadLedgerForSelection();
                  },
                  icon: const Icon(Icons.person_off_outlined, size: 17),
                  label: const Text('Switch to Walk-in'),
                ),
              FilledButton.icon(
                key: const ValueKey('pos-customers-go-till'),
                onPressed: _goToTill,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandBlack,
                  foregroundColor: AppColors.brandWhite,
                ),
                icon: const Icon(Icons.point_of_sale_outlined, size: 17),
                label: const Text('Go to New transaction'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _activeAutoFillSummary(CustomerProfile? profile) {
    if (profile == null) return 'Selected for current sale.';
    final parts = <String>[
      if (profile.discountBadgeLabel != null)
        'Auto-discount: ${profile.effectiveDiscountReason}',
      if (profile.phone.trim().isNotEmpty) 'Phone: ${profile.phone.trim()}',
      if (profile.address.trim().isNotEmpty)
        'Address: ${profile.address.trim()}',
    ];
    if (parts.isEmpty) {
      return 'Name auto-fills Utang & Delivery forms (all fields stay editable).';
    }
    return '${parts.join(' · ')} (editable in checkout)';
  }

  Widget _buildSummaryStrip(
    BuildContext context,
    AppPalette p, {
    required int totalCount,
    required int discountCount,
    required int contactReadyCount,
  }) {
    Widget card({
      required IconData icon,
      required String label,
      required String value,
      required String caption,
    }) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: p.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: p.accentInk),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: p.textPrimary,
                    ),
                  ),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: p.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            children: [
              card(
                icon: Icons.people_alt_outlined,
                label: 'REGULAR CUSTOMERS',
                value: '$totalCount',
                caption: 'Ready in "Who is this sale for?"',
              ),
              const SizedBox(height: 10),
              card(
                icon: Icons.sell_outlined,
                label: 'AUTO-DISCOUNT PROFILES',
                value: '$discountCount',
                caption: 'Senior Citizen, PWD & regular presets',
              ),
              const SizedBox(height: 10),
              card(
                icon: Icons.local_shipping_outlined,
                label: 'UTANG & DELIVERY READY',
                value: '$contactReadyCount',
                caption: 'Pre-fills name, phone & address',
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: card(
                icon: Icons.people_alt_outlined,
                label: 'REGULAR CUSTOMERS',
                value: '$totalCount',
                caption: 'Ready in "Who is this sale for?"',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: card(
                icon: Icons.sell_outlined,
                label: 'AUTO-DISCOUNT PROFILES',
                value: '$discountCount',
                caption: 'Senior Citizen, PWD & regular presets',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: card(
                icon: Icons.local_shipping_outlined,
                label: 'UTANG & DELIVERY READY',
                value: '$contactReadyCount',
                caption: 'Pre-fills name, phone & address',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTableHeader(AppPalette p) {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
      color: p.textSecondary,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      color: p.surfaceMuted,
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('CUSTOMER & TYPE', style: style)),
          Expanded(
            flex: 3,
            child: Text('STANDING DISCOUNT (AUTO-FILL)', style: style),
          ),
          Expanded(
            flex: 4,
            child: Text('UTANG & DELIVERY DETAILS (AUTO-FILL)', style: style),
          ),
          SizedBox(
            width: 240,
            child: Text(
              'ACTIONS',
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerRow(
    BuildContext context,
    AppPalette p,
    PosTransactionViewmodel transaction,
    Customer customer,
    CustomerProfile profile,
  ) {
    final isSelected =
        transaction.selectedCustomer != null &&
        !transaction.selectedCustomer!.isWalkIn &&
        (transaction.selectedCustomer!.id == customer.id ||
            transaction.selectedCustomer!.name.trim().toLowerCase() ==
                customer.name.trim().toLowerCase());

    final initials = customer.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return Container(
      key: ValueKey('pos-customer-row-${customer.name}'),
      color: isSelected ? p.selected.withValues(alpha: 0.45) : null,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          // 1. Customer & Type
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: isSelected ? p.accent : p.surfaceMuted,
                  child: Text(
                    initials.isEmpty ? '?' : initials,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? AppColors.brandBlack : p.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            customer.name,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary,
                            ),
                          ),
                          if (isSelected)
                            const StatusBadge(
                              label: 'Active in sale',
                              tone: StatusTone.info,
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        customer.type.label,
                        style: TextStyle(fontSize: 12, color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 2. Standing Discount preset
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: profile.discountBadgeLabel != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StatusBadge(
                          label: profile.discountBadgeLabel!,
                          tone: StatusTone.success,
                        ),
                        if (profile.idNumber.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              'ID: ${profile.idNumber.trim()}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: p.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    )
                  : Text(
                      'No standing discount',
                      style: TextStyle(fontSize: 12.5, color: p.textSecondary),
                    ),
            ),
          ),
          // 3. Utang & Delivery Contact Details
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.phone_outlined,
                        size: 14,
                        color: profile.phone.trim().isNotEmpty
                            ? p.accentInk
                            : p.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          profile.phone.trim().isNotEmpty
                              ? profile.phone.trim()
                              : 'No phone number saved',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: profile.phone.trim().isNotEmpty
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: profile.phone.trim().isNotEmpty
                                ? p.textPrimary
                                : p.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: profile.address.trim().isNotEmpty
                            ? p.accentInk
                            : p.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          profile.address.trim().isNotEmpty
                              ? profile.address.trim()
                              : 'No address saved',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: profile.address.trim().isNotEmpty
                                ? p.textPrimary
                                : p.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 4. Actions
          SizedBox(
            width: 240,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton(
                  key: ValueKey('pos-customer-edit-${customer.name}'),
                  onPressed: () => _openCustomerForm(
                    initial: profile,
                    existingCustomer: customer,
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: const Text('Edit'),
                ),
                FilledButton(
                  key: ValueKey('pos-customer-use-${customer.name}'),
                  onPressed: isSelected
                      ? null
                      : () => _useInSale(customer, profile),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    backgroundColor: AppColors.brandBlack,
                    foregroundColor: AppColors.brandWhite,
                  ),
                  child: Text(isSelected ? 'Selected' : 'Use in sale'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerProfileFormDialog extends StatefulWidget {
  const _CustomerProfileFormDialog({
    this.initial,
    this.existingCustomer,
  });

  final CustomerProfile? initial;
  final Customer? existingCustomer;

  @override
  State<_CustomerProfileFormDialog> createState() =>
      _CustomerProfileFormDialogState();
}

class _CustomerProfileFormDialogState
    extends State<_CustomerProfileFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _idNumberController;
  late final TextEditingController _discountValueController;
  late final TextEditingController _discountReasonController;

  late CustomerType _type;
  late CustomerDiscountType _discountType;
  bool _useInSale = true;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _nameController = TextEditingController(text: init?.name ?? '');
    _phoneController = TextEditingController(text: init?.phone ?? '');
    _addressController = TextEditingController(text: init?.address ?? '');
    _idNumberController = TextEditingController(text: init?.idNumber ?? '');
    _discountValueController = TextEditingController(
      text: init != null && init.effectiveDiscountValue > 0
          ? (init.effectiveDiscountValue ==
                    init.effectiveDiscountValue.roundToDouble()
                ? init.effectiveDiscountValue.toInt().toString()
                : init.effectiveDiscountValue.toStringAsFixed(2))
          : '20',
    );
    _discountReasonController = TextEditingController(
      text: init?.discountReason ?? '',
    );
    _type = init?.type ?? CustomerType.regular;
    if (_type == CustomerType.unknown || _type == CustomerType.walkIn) {
      _type = CustomerType.regular;
    }
    _discountType = init?.discountType ?? CustomerDiscountType.none;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _idNumberController.dispose();
    _discountValueController.dispose();
    _discountReasonController.dispose();
    super.dispose();
  }

  void _selectDiscountType(CustomerDiscountType next) {
    setState(() {
      _discountType = next;
      if (next == CustomerDiscountType.seniorCitizen) {
        _discountValueController.text = '20';
        if (_discountReasonController.text.trim().isEmpty ||
            _discountReasonController.text.startsWith('PWD')) {
          _discountReasonController.text = 'Senior Citizen (20%)';
        }
      } else if (next == CustomerDiscountType.pwd) {
        _discountValueController.text = '20';
        if (_discountReasonController.text.trim().isEmpty ||
            _discountReasonController.text.startsWith('Senior Citizen')) {
          _discountReasonController.text = 'PWD (20%)';
        }
      }
    });
  }

  CustomerProfile _buildDraft() {
    final parsedValue =
        double.tryParse(_discountValueController.text.trim()) ?? 0;
    return CustomerProfile(
      customerId: widget.existingCustomer?.id ?? widget.initial?.customerId,
      name: _nameController.text.trim(),
      type: _type,
      phone: _phoneController.text.trim(),
      address: _addressController.text.trim(),
      discountType: _discountType,
      discountValue: switch (_discountType) {
        CustomerDiscountType.none => 0,
        CustomerDiscountType.seniorCitizen || CustomerDiscountType.pwd => 20,
        CustomerDiscountType.customPercent ||
        CustomerDiscountType.customAmount => parsedValue,
      },
      discountReason: _discountReasonController.text.trim(),
      idNumber: _idNumberController.text.trim(),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop((profile: _buildDraft(), useInSale: _useInSale));
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final isEditing = widget.initial != null;
    final preview = _buildDraft();

    return AppDialog(
      icon: isEditing
          ? Icons.manage_accounts_outlined
          : Icons.person_add_alt_1_rounded,
      title: isEditing ? 'Edit Customer Profile' : 'Add Regular Customer',
      subtitle:
          'Saved details automatically fill in Discount, Utang, and Delivery forms when chosen in "Who is this sale for?".',
      width: 560,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const ValueKey('pos-customer-form-name'),
              controller: _nameController,
              autofocus: !isEditing,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Customer full name',
                hintText: 'e.g. Mang Kanor or Manang Rosa',
                prefixIcon: Icon(Icons.person_outline_rounded, size: 19),
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Enter the customer\'s name.'
                  : null,
            ),
            const SizedBox(height: 14),
            Text(
              'CUSTOMER TYPE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: p.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final type in const [
                  CustomerType.regular,
                  CustomerType.contractor,
                  CustomerType.constructionFirm,
                ])
                  ChoiceChip(
                    label: Text(type.label),
                    selected: _type == type,
                    onSelected: (_) => setState(() => _type = type),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('pos-customer-form-phone'),
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Contact number (Phone)',
                      hintText: 'e.g. 0917-412-8890',
                      prefixIcon: Icon(Icons.phone_outlined, size: 19),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('pos-customer-form-id-number'),
                    controller: _idNumberController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Senior / PWD ID No. (optional)',
                      hintText: 'e.g. OSCA-20419',
                      prefixIcon: Icon(Icons.badge_outlined, size: 19),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('pos-customer-form-address'),
              controller: _addressController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Address (for Utang & Delivery)',
                hintText: 'e.g. 142 Mabini St., Brgy. San Jose',
                prefixIcon: Icon(Icons.location_on_outlined, size: 19),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'STANDING DISCOUNT PRESET (AUTO-FILLS DISCOUNT SECTION)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: p.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final preset in CustomerDiscountType.values)
                  ChoiceChip(
                    key: ValueKey('pos-customer-discount-chip-${preset.name}'),
                    label: Text(preset.label),
                    selected: _discountType == preset,
                    onSelected: (_) => _selectDiscountType(preset),
                  ),
              ],
            ),
            if (_discountType == CustomerDiscountType.customPercent ||
                _discountType == CustomerDiscountType.customAmount) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey('pos-customer-form-discount-value'),
                      controller: _discountValueController,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            _discountType == CustomerDiscountType.customAmount
                            ? 'Discount amount (₱)'
                            : 'Discount percent (%)',
                      ),
                      validator: (value) {
                        final parsed = double.tryParse((value ?? '').trim());
                        if (parsed == null || parsed <= 0) {
                          return 'Enter a value > 0';
                        }
                        if (_discountType ==
                                CustomerDiscountType.customPercent &&
                            parsed > 100) {
                          return 'Max 100%';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      key: const ValueKey('pos-customer-form-discount-reason'),
                      controller: _discountReasonController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Discount reason',
                        hintText: 'e.g. Regular Contractor (5%)',
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AUTO-FILL PREVIEW IN NEW TRANSACTION',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '• Discount section: ${preview.hasDiscount ? '${preview.discountBadgeLabel} (${preview.effectiveDiscountReason})' : 'None (regular price)'}',
                    style: TextStyle(fontSize: 12.5, color: p.textPrimary),
                  ),
                  Text(
                    '• Utang & Delivery forms: ${preview.name.isEmpty ? 'Customer name' : preview.name}'
                    '${preview.phone.isNotEmpty ? ' · ${preview.phone}' : ''}'
                    '${preview.address.isNotEmpty ? ' · ${preview.address}' : ''}'
                    ' (editable)',
                    style: TextStyle(fontSize: 12.5, color: p.textPrimary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const ValueKey('pos-customer-form-use-now'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _useInSale,
              onChanged: (v) => setState(() => _useInSale = v ?? true),
              title: const Text(
                'Select this customer for the current sale right away',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const ValueKey('pos-customer-form-save'),
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brandBlack,
            foregroundColor: AppColors.brandWhite,
          ),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(isEditing ? 'Save changes' : 'Save customer'),
        ),
      ],
    );
  }
}
