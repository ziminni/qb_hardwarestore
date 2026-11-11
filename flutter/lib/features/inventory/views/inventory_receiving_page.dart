import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/receiving_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/inventory/widgets/inventory_receiving_workspace.dart';
import 'package:client/features/labels/delivery_labels.dart';
import 'package:client/features/labels/label_document.dart';
import 'package:client/features/labels/label_print_dialog.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The receiving screen (decision 17, Phase 4 Task 4): list the purchase orders
/// that can be received, record a goods receipt with received quantities,
/// process it into FIFO batches, and look up the deliveries already received.
///
/// Stock ENTERS through here, every other screen only moves or shows it. That is
/// why the two writes are two visible steps (`InventoryReceivingWorkspace`):
/// recording a receipt sets `received_qty` and creates no stock; processing it
/// creates the FIFO batches.
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

  /// Pre-fills the label picker from what this delivery actually created.
  ///
  /// The base unit of each delivered variant gets copies = the quantity received
  /// when it is a countable unit (m/kg get one sticker), and the variant's other
  /// units start at 0 because they were not what arrived (decision 14).
  Future<void> _printDeliveryLabels() async {
    final viewmodel = context.read<ReceivingViewmodel>();
    final inventory = context.read<InventoryViewmodel>();
    final requests = <LabelRequest>[
      for (final batch in viewmodel.lastBatches)
        if (inventory.variantFor(batch.variantId) case final variant?)
          ...deliveryLabelRequests(
            productName: _productNameFor(inventory, batch.variantId),
            variantName: variant.variantName,
            sellingUnits: variant.sellingUoms,
            receivedQty: batch.initialQty,
          ),
    ];
    if (!mounted) return;
    if (requests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('These batches have no selling units.')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => LabelPrintDialog(requests: requests, allowSkip: true),
    );
  }

  String _productNameFor(InventoryViewmodel inventory, int variantId) {
    for (final record in inventory.stockRecords) {
      if (record.variant.id == variantId) return record.product.baseName;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<ReceivingViewmodel>();
    return InventorySkeletonLayout(
      title: 'Receiving',
      subtitle: 'Receive purchase orders into FIFO stock.',
      selectedNavigationIndex: 8,
      onNavigationSelected: (index) => navigateInventory(context, index),
      // The delivery history can hold every receipt ever booked, so that tab
      // gives its panel a bounded slot and the rows build lazily. The order
      // workspace is a handful of panels and keeps the page's own scroll.
      scrollable: !_showHistory,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Purchase orders'),
                  icon: Icon(Icons.move_to_inbox_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Received deliveries'),
                  icon: Icon(Icons.history),
                ),
              ],
              selected: {_showHistory},
              onSelectionChanged: (values) =>
                  setState(() => _showHistory = values.first),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_showHistory)
            Expanded(child: _ReceiptHistory(viewmodel: viewmodel))
          else
            InventoryReceivingWorkspace(
              viewmodel: viewmodel,
              onPrintLabels: _printDeliveryLabels,
            ),
        ],
      ),
    );
  }
}

/// `GET /api/v1/goods-receipts/`: every delivery already booked in.
///
/// Append-only on the server (no PATCH, no DELETE), so a row's only action is to
/// look at it.
class _ReceiptHistory extends StatelessWidget {
  const _ReceiptHistory({required this.viewmodel});

  final ReceivingViewmodel viewmodel;

  @override
  Widget build(BuildContext context) {
    final receipts = viewmodel.receipts;
    return DataPanel<GoodsReceiptRecord>(
      columns: [
        DataPanelColumn<GoodsReceiptRecord>(
          label: 'Received',
          flex: 2,
          cell: (receipt) => Text(
            receipt.receiveDate == null
                ? 'Not dated'
                : formatDate(receipt.receiveDate!),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DataPanelColumn<GoodsReceiptRecord>(
          label: 'PO',
          flex: 2,
          cell: (receipt) => Text('PO-${receipt.poId}'),
        ),
        DataPanelColumn<GoodsReceiptRecord>(
          label: 'DR No.',
          flex: 3,
          cell: (receipt) => Text(
            receipt.deliveryReceiptNo.isEmpty
                ? 'Not given'
                : receipt.deliveryReceiptNo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DataPanelColumn<GoodsReceiptRecord>(
          label: 'Received by',
          flex: 3,
          cell: (receipt) => Text(
            receipt.receivedByName.isEmpty
                ? 'Not recorded'
                : receipt.receivedByName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DataPanelColumn<GoodsReceiptRecord>(
          label: 'Lines',
          flex: 2,
          numeric: true,
          cell: (receipt) => Text(formatCount(receipt.lines.length)),
        ),
        DataPanelColumn<GoodsReceiptRecord>(
          label: 'Status',
          flex: 2,
          cell: (receipt) => StatusBadge(
            label: receipt.isProcessed ? 'In stock' : 'Recorded',
            tone: receipt.isProcessed ? StatusTone.success : StatusTone.warning,
          ),
        ),
        DataPanelColumn<GoodsReceiptRecord>(
          label: 'Actions',
          flex: 2,
          cell: (receipt) => IconButton(
            tooltip: 'View delivery',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => GoodsReceiptDetailsSheet(receipt: receipt),
            ),
            icon: const Icon(Icons.visibility_outlined, size: 18),
          ),
        ),
      ],
      rows: receipts,
      emptyMessage: 'No deliveries have been received yet.',
      isLoading: viewmodel.isLoadingReceipts && receipts.isEmpty,
      error: viewmodel.receiptsError,
      onRetry: viewmodel.loadReceipts,
    );
  }
}

/// One delivery, read-only.
///
/// Read-only is the contract, not a preference: goods receipts are append-only
/// (there is no PATCH and no DELETE on the route), so the only honest thing a
/// sheet can offer is Close.
class GoodsReceiptDetailsSheet extends StatelessWidget {
  const GoodsReceiptDetailsSheet({super.key, required this.receipt});

  final GoodsReceiptRecord receipt;

  @override
  Widget build(BuildContext context) {
    final receipt = this.receipt;
    return AppDialog(
      icon: Icons.local_shipping_outlined,
      title: 'Delivery #${receipt.id} · PO-${receipt.poId}',
      subtitle: receipt.processedAt == null
          ? 'Recorded, not processed into stock yet'
          : 'Processed into stock',
      width: 560,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          DetailRow(
            label: 'Received',
            value: receipt.receiveDate == null
                ? 'Date not recorded'
                : formatDateTime(receipt.receiveDate!),
          ),
          DetailRow(
            label: 'Received by',
            value: receipt.receivedByName.isEmpty
                ? 'Not recorded'
                : receipt.receivedByName,
          ),
          DetailRow(
            label: 'Delivery receipt',
            value: receipt.deliveryReceiptNo.isEmpty
                ? 'Not given'
                : receipt.deliveryReceiptNo,
          ),
          DetailRow(
            label: 'Processed',
            value: receipt.processedAt == null
                ? 'Not processed into stock yet'
                : formatDateTime(receipt.processedAt!),
          ),
          if (receipt.notes.isNotEmpty)
            DetailRow(label: 'Notes', value: receipt.notes),
          const SizedBox(height: AppSpacing.xl),
          DialogSectionLabel('Lines (${receipt.lines.length})'),
          if (receipt.lines.isEmpty)
            const Text('This receipt carried no line detail.')
          else
            for (final line in receipt.lines)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(line.variantName),
                trailing: Text(receivingQtyLabel(line.qty)),
              ),
        ],
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
