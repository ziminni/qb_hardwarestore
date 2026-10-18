import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/features/inventory/viewmodels/receiving_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The receiving screen (decision 17): list purchase orders, record a goods
/// receipt with received quantities, process it into FIFO batches.
///
/// Stock ENTERS through here — every other screen only moves or shows it.
class InventoryReceivingPage extends StatelessWidget {
  const InventoryReceivingPage({super.key, this.viewmodel});

  /// Injected by tests so a state can be rendered WITHOUT a server.
  final ReceivingViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => (viewmodel ?? ReceivingViewmodel())..load(),
      child: const _ReceivingView(),
    );
  }
}

class _ReceivingView extends StatelessWidget {
  const _ReceivingView();

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<ReceivingViewmodel>();
    return InventorySkeletonLayout(
      title: 'Receiving',
      subtitle: 'Receive purchase orders into FIFO stock.',
      selectedNavigationIndex: 10,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: viewmodel.isLoading && !viewmodel.hasOrders
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (viewmodel.loadError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Text(
                      viewmodel.loadError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                // Fixed height, not Expanded: the inventory shell lays its
                // content out in an unbounded vertical scrollable, where flex
                // has no meaning (same constraint as the admin Reports screen).
                SizedBox(
                  height: 900,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 320,
                        child: ListView(
                          children: [
                            for (final order in viewmodel.orders)
                              ListTile(
                                selected: viewmodel.selected?.id == order.id,
                                title: Text('PO-${order.id} · ${order.status}'),
                                subtitle: Text('${order.items.length} line(s)'),
                                onTap: () => viewmodel.select(order),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: _OrderDetail(viewmodel: viewmodel)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _OrderDetail extends StatefulWidget {
  const _OrderDetail({required this.viewmodel});

  final ReceivingViewmodel viewmodel;

  @override
  State<_OrderDetail> createState() => _OrderDetailState();
}

class _OrderDetailState extends State<_OrderDetail> {
  final _controllers = <int, TextEditingController>{};
  final _deliveryController = TextEditingController();

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _deliveryController.dispose();
    super.dispose();
  }

  TextEditingController _controllerFor(int poItemId) =>
      _controllers.putIfAbsent(poItemId, TextEditingController.new);

  @override
  Widget build(BuildContext context) {
    final viewmodel = widget.viewmodel;
    final order = viewmodel.selected;
    if (order == null) {
      return const Center(
        child: Text('Select a purchase order to receive it.'),
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PO-${order.id} · ${order.status}',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final item in order.items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.variantName} — ordered ${item.orderedQty}, received ${item.receivedQty}',
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: TextField(
                      key: Key('receiving-qty-${item.id}'),
                      controller: _controllerFor(item.id),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Received qty',
                      ),
                      onChanged: (text) {
                        final parsed = double.tryParse(text.trim());
                        if (parsed != null) {
                          viewmodel.setQty(item.id, parsed);
                        } else {
                          viewmodel.clearQty(item.id);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: 220,
            child: TextField(
              controller: _deliveryController,
              decoration: const InputDecoration(
                labelText: 'Delivery receipt no.',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (viewmodel.actionError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                viewmodel.actionError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (viewmodel.lastReceiptId == null)
            FilledButton(
              onPressed: viewmodel.isActing
                  ? null
                  : () => viewmodel.recordReceipt(),
              child: const Text('Record receipt'),
            )
          else if (!viewmodel.isProcessed) ...[
            Text('Receipt #${viewmodel.lastReceiptId} recorded.'),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              onPressed: viewmodel.isActing
                  ? null
                  : () async {
                      final ok = await viewmodel.processReceipt();
                      if (!context.mounted || !ok) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${viewmodel.lastBatches.length} batch(es) created.',
                          ),
                        ),
                      );
                    },
              child: const Text('Process into stock'),
            ),
          ] else ...[
            Text(
              '${viewmodel.lastBatches.length} batch(es) created from receipt '
              '#${viewmodel.lastReceiptId}.',
            ),
          ],
        ],
      ),
    );
  }
}
