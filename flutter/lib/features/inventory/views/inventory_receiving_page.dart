import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/features/inventory/viewmodels/receiving_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The receiving screen (decision 17, Phase 4 Task 4): list the purchase orders
/// that can be received, record a goods receipt with received quantities,
/// process it into FIFO batches, and look up the deliveries already received.
///
/// Stock ENTERS through here — every other screen only moves or shows it.
class InventoryReceivingPage extends StatelessWidget {
  const InventoryReceivingPage({super.key, this.viewmodel});

  /// Injected by tests so a state can be rendered WITHOUT a server.
  final ReceivingViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => (viewmodel ?? ReceivingViewmodel())
        ..load()
        ..loadReceipts(),
      child: const _ReceivingView(),
    );
  }
}

class _ReceivingView extends StatefulWidget {
  const _ReceivingView();

  @override
  State<_ReceivingView> createState() => _ReceivingViewState();
}

class _ReceivingViewState extends State<_ReceivingView> {
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<ReceivingViewmodel>();
    return InventorySkeletonLayout(
      title: 'Receiving',
      subtitle: 'Receive purchase orders into FIFO stock.',
      selectedNavigationIndex: 8,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Purchase orders')),
              ButtonSegment(value: true, label: Text('Received deliveries')),
            ],
            selected: {_showHistory},
            onSelectionChanged: (values) =>
                setState(() => _showHistory = values.first),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_showHistory)
            _ReceiptHistory(viewmodel: viewmodel)
          else
            _OrderWorkspace(viewmodel: viewmodel),
        ],
      ),
    );
  }
}

class _OrderWorkspace extends StatelessWidget {
  const _OrderWorkspace({required this.viewmodel});

  final ReceivingViewmodel viewmodel;

  @override
  Widget build(BuildContext context) {
    if (viewmodel.isLoading && !viewmodel.hasOrders) {
      return const SizedBox(
        height: 400,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (viewmodel.loadError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              viewmodel.loadError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        // Fixed height, not Expanded: the inventory shell lays its content out in
        // an unbounded vertical scrollable, where flex has no meaning (same
        // constraint as the admin Reports screen).
        SizedBox(
          height: 620,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 320,
                // A failed read is not an empty order book: with the error line
                // above already saying what went wrong, the empty copy is
                // withheld so it cannot claim nothing is waiting (F2 sweep).
                child: viewmodel.orders.isEmpty && viewmodel.loadError == null
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.lg),
                        child: Text(
                          'No order is waiting to be received. Only ORDERED or '
                          'PARTIAL purchase orders can be received.',
                        ),
                      )
                    : ListView(
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
                  : () => viewmodel.recordReceipt(
                      deliveryReceiptNo: _deliveryController.text.trim(),
                    ),
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

/// `GET /api/v1/goods-receipts/` — every delivery already booked in.
class _ReceiptHistory extends StatelessWidget {
  const _ReceiptHistory({required this.viewmodel});

  final ReceivingViewmodel viewmodel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (viewmodel.isLoadingReceipts && viewmodel.receipts.isEmpty) {
      return const SizedBox(
        height: 400,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (viewmodel.receiptsError case final error?) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(error, style: TextStyle(color: colors.error)),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: viewmodel.loadReceipts,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (viewmodel.receipts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Text('No deliveries have been received yet.'),
      );
    }
    String date(DateTime? value) => value == null
        ? '—'
        : '${value.year}-${value.month.toString().padLeft(2, '0')}-'
              '${value.day.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(colors.secondaryContainer),
          columns: const [
            DataColumn(label: Text('Received')),
            DataColumn(label: Text('PO')),
            DataColumn(label: Text('DR No.')),
            DataColumn(label: Text('Received by')),
            DataColumn(label: Text('Lines')),
            DataColumn(label: Text('Qty')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Actions')),
          ],
          rows: [
            for (final receipt in viewmodel.receipts)
              DataRow(
                cells: [
                  DataCell(Text(date(receipt.receiveDate))),
                  DataCell(Text('PO-${receipt.poId}')),
                  DataCell(
                    Text(
                      receipt.deliveryReceiptNo.isEmpty
                          ? '—'
                          : receipt.deliveryReceiptNo,
                    ),
                  ),
                  DataCell(
                    Text(
                      receipt.receivedByName.isEmpty
                          ? '—'
                          : receipt.receivedByName,
                    ),
                  ),
                  DataCell(Text('${receipt.lines.length}')),
                  DataCell(Text(receipt.totalQty.toStringAsFixed(0))),
                  DataCell(Text(receipt.isProcessed ? 'In stock' : 'Recorded')),
                  DataCell(
                    IconButton(
                      tooltip: 'View delivery',
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) =>
                            GoodsReceiptDetailsSheet(receipt: receipt),
                      ),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// One delivery, read-only.
///
/// Read-only is the contract, not a preference: goods receipts are append-only —
/// there is no PATCH and no DELETE on the route — so the only honest thing a
/// sheet can offer is Close.
class GoodsReceiptDetailsSheet extends StatelessWidget {
  const GoodsReceiptDetailsSheet({super.key, required this.receipt});

  final GoodsReceiptRecord receipt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String date(DateTime? value) => value == null
        ? '—'
        : '${value.year}-${value.month.toString().padLeft(2, '0')}-'
              '${value.day.toString().padLeft(2, '0')} '
              '${value.hour.toString().padLeft(2, '0')}:'
              '${value.minute.toString().padLeft(2, '0')}';
    return AlertDialog(
      title: Text('Delivery #${receipt.id} · PO-${receipt.poId}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Received ${date(receipt.receiveDate)}'),
              Text(
                'Received by ${receipt.receivedByName.isEmpty ? '—' : receipt.receivedByName}',
              ),
              Text(
                'Delivery receipt: '
                '${receipt.deliveryReceiptNo.isEmpty ? '—' : receipt.deliveryReceiptNo}',
              ),
              Text('Processed: ${date(receipt.processedAt)}'),
              if (receipt.notes.isNotEmpty) Text('Notes: ${receipt.notes}'),
              const Divider(height: AppSpacing.xxl),
              Text('Lines', style: theme.textTheme.titleSmall),
              if (receipt.lines.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.sm),
                  child: Text('This receipt carried no line detail.'),
                )
              else
                for (final line in receipt.lines)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(line.variantName),
                    trailing: Text(line.qty.toStringAsFixed(0)),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
