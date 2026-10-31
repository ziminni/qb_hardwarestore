import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/features/suppliers/widgets/purchases_details_dialog.dart';
import 'package:client/features/suppliers/widgets/purchases_form_dialog.dart';
import 'package:client/features/suppliers/widgets/purchases_table.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Purchases screen (decision D-02, Phase 4 Task 4).
///
/// "New purchase order" creates a real order on the server with its lines nested
/// in the POST, and the row actions are the server's own transitions: `place/`
/// from DRAFT, `cancel/` while nothing has been received. Before this the button
/// was removed entirely because the dialog's Save could only have mutated a local
/// list — the `addPurchase` mock this screen deleted in Phase 1.
///
/// Status filtering stays client-side — the list is one page-set of the whole PO
/// book and chips over it are cheaper than a round trip per tap.
class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});
  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  static const String _allChip = 'All statuses';

  String _query = '';
  PurchaseStatus? _status;

  @override
  void initState() {
    super.initState();
    // Load on open; both tabs share one app-scoped viewmodel, so whichever opens
    // last refreshes both lists.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SuppliersPurchasesViewmodel>().load();
    });
  }

  void _announce(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _newOrder() async {
    final state = context.read<SuppliersPurchasesViewmodel>();
    final inventory = context.read<InventoryViewmodel>();
    // The product picker is built from the shared catalogue, which this screen
    // does not own and never loaded. Fetch it first rather than opening a picker
    // with no rows and no explanation (F2 page sweep).
    if (!inventory.hasLoaded) {
      await inventory.load();
      if (!mounted) return;
    }
    final result = await showDialog<PurchaseOrderFormResult>(
      context: context,
      builder: (_) => PurchasesFormDialog(
        suppliers: state.suppliers,
        products: inventory.products,
        costFor: (variantId) => inventory.costFor(variantId) ?? 0,
      ),
    );
    if (result == null || !mounted) return;
    final error = await state.createPurchaseOrder(
      result.draft,
      place: result.place,
    );
    _announce(error ?? (result.place ? 'Order placed.' : 'Draft saved.'));
  }

  Future<void> _confirmCancel(PurchaseOrder order) async {
    final state = context.read<SuppliersPurchasesViewmodel>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Cancel PO-${order.id}?'),
        content: const Text(
          'A cancelled order cannot be received. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final error = await state.cancelOrder(order);
    _announce(error ?? 'PO-${order.id} cancelled.');
  }

  Future<void> _place(PurchaseOrder order) async {
    final state = context.read<SuppliersPurchasesViewmodel>();
    final error = await state.placeOrder(order);
    _announce(error ?? 'PO-${order.id} placed.');
  }

  /// The goods are recorded on Receiving, which owns the receipt and the stock
  /// it creates, so this only takes the reader there.
  void _receive(PurchaseOrder order) => navigateInventory(context, 8);

  void _openDetails(PurchaseOrder order) => showDialog<void>(
    context: context,
    builder: (_) => PurchasesDetailsDialog(order: order),
  );

  /// `All statuses 3`, `Ordered 2`, ... over the orders the search left.
  ///
  /// A count is shown even when it is zero: "Draft 0" says there is nothing
  /// waiting to be placed, which an absent chip cannot.
  List<String> _chips(List<PurchaseOrder> searched) => [
    '$_allChip ${formatCount(searched.length)}',
    for (final status in PurchaseStatus.values)
      '${status.label} '
          '${formatCount(searched.where((o) => o.status == status).length)}',
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SuppliersPurchasesViewmodel>();
    // The search narrows first, so a chip's count is the number of rows the
    // reader will see if they tap it.
    final searched = state.filteredPurchases(query: _query);
    final chips = _chips(searched);
    final orders = _status == null
        ? searched
        : searched.where((order) => order.status == _status).toList();
    final selectedChip = _status == null
        ? chips.first
        : chips[PurchaseStatus.values.indexOf(_status!) + 1];

    final failure = state.loadError;
    final pending = state.isLoading;
    // A failed refresh keeps the rows it already had and says why above them.
    final staleRows = failure != null && orders.isNotEmpty;
    final filtered = _query.isNotEmpty || _status != null;

    return InventorySkeletonLayout(
      title: 'Purchases',
      subtitle: 'Plan and monitor supplier purchase orders.',
      selectedNavigationIndex: 6,
      // The list owns the scrolling: rows build only as they come on screen.
      scrollable: false,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FilterBar(
                  searchHint: 'Search PO or supplier',
                  onSearchChanged: (value) => setState(() => _query = value),
                  options: chips,
                  selected: selectedChip,
                  onSelected: (chip) => setState(() {
                    final index = chips.indexOf(chip);
                    _status = index <= 0
                        ? null
                        : PurchaseStatus.values[index - 1];
                  }),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton.icon(
                onPressed: _newOrder,
                icon: const Icon(Icons.add),
                label: const Text('New purchase order'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (staleRows)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: ErrorBanner(message: failure, onRetry: state.load),
            ),
          Expanded(
            // Top aligned and only as tall as its content: with nothing to
            // scroll, a panel stretched down the page is a white void (or, on a
            // failure, a red one). With rows, DataPanel still fills the slot and
            // builds only the rows on screen.
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: double.infinity,
                child: PurchasesTable(
                  orders: orders,
                  onView: _openDetails,
                  onPlace: _place,
                  onCancel: _confirmCancel,
                  onReceive: _receive,
                  emptyMessage: filtered
                      ? 'No purchase orders match these filters.'
                      : 'No purchase orders yet.',
                  // The spinner is for a first load with nothing to show: a
                  // reload over rows must not take them away.
                  isLoading: pending && orders.isEmpty,
                  error: staleRows ? null : failure,
                  onRetry: state.load,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
