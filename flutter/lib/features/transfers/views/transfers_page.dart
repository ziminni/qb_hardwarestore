import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/stock_transfer.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/features/transfers/viewmodels/transfers_viewmodel.dart';
import 'package:client/features/transfers/widgets/stock_transfer_dialog.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Which role shell draws the same transfers body (Phase 9 F3).
///
/// All three are the accounts that may move stock — Stock Manager, Store
/// Manager, Admin (`IsInventoryRole`). A Cashier has no transfers screen at all:
/// the server answers 403 to the list and to the write, so a read-only page
/// would be nothing but failures.
enum TransfersShell { inventory, sales }

/// Transfers in the Stock Manager's shell (inventory sidebar index 15,
/// APPENDED so no earlier tab moves).
class InventoryTransfersPage extends StatelessWidget {
  const InventoryTransfersPage({super.key, this.viewmodel, this.products});

  final TransfersViewmodel? viewmodel;

  /// The catalogue the dialog picks lines from, injected by tests so a screen
  /// can be rendered without a server.
  final ProductsRepository? products;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => (viewmodel ?? TransfersViewmodel())..load(),
    child: _TransfersBody(shell: TransfersShell.inventory, products: products),
  );
}

/// Transfers in the Store Manager's shell (sales sidebar index 11, APPENDED).
class SalesTransfersPage extends StatelessWidget {
  const SalesTransfersPage({super.key, this.viewmodel, this.products});

  final TransfersViewmodel? viewmodel;
  final ProductsRepository? products;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => (viewmodel ?? TransfersViewmodel())..load(),
    child: _TransfersBody(shell: TransfersShell.sales, products: products),
  );
}

/// The one screen body, shared by the three shells so the rules cannot drift
/// between roles.
class _TransfersBody extends StatefulWidget {
  const _TransfersBody({required this.shell, this.products});

  final TransfersShell shell;
  final ProductsRepository? products;

  @override
  State<_TransfersBody> createState() => _TransfersBodyState();
}

class _TransfersBodyState extends State<_TransfersBody> {
  String _query = '';

  /// The catalogue, kept after the first successful read: the dialog is opened
  /// repeatedly in a stock-taking session, and re-reading the whole catalogue
  /// for every slip would be a slow way to pick the same product again.
  List<Product>? _catalogue;

  ProductsRepository get _products =>
      widget.products ?? ProductsRepository(ProductsService());

  void _say(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _record() async {
    final state = context.read<TransfersViewmodel>();
    if (state.isRecording) return;
    state.clearActionError();

    final catalogue = _catalogue ?? await _loadCatalogue();
    if (!mounted || catalogue == null) return;
    if (state.activeLocations.isEmpty) {
      _say(
        'There are no active shelves to move stock between. An Admin adds one '
        'under Storage locations.',
      );
      return;
    }

    final recorded = await showDialog<StockTransfer>(
      context: context,
      builder: (_) => StockTransferDialog(
        viewmodel: state,
        locations: state.locations,
        products: catalogue,
      ),
    );
    if (!mounted || recorded == null) return;
    _say(
      '${recorded.number} moved ${formatQuantity(recorded.movedBaseQty)} '
      'from ${recorded.fromLocationName} to ${recorded.toLocationName}.',
    );
  }

  Future<List<Product>?> _loadCatalogue() async {
    try {
      final snapshot = await _products.loadCatalogue();
      if (!mounted) return null;
      return _catalogue = snapshot.products;
    } on ProductsServiceException catch (error) {
      if (mounted) _say(error.message);
      return null;
    }
  }

  Future<void> _showSlip(StockTransfer transfer) => showDialog<void>(
    context: context,
    builder: (_) => _TransferSlipDialog(transfer: transfer),
  );

  List<StockTransfer> _visible(List<StockTransfer> transfers) {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return transfers;
    return [
      for (final transfer in transfers)
        if (transfer.number.toLowerCase().contains(needle) ||
            transfer.routeLabel.toLowerCase().contains(needle) ||
            transfer.remarks.toLowerCase().contains(needle) ||
            transfer.userName.toLowerCase().contains(needle) ||
            transfer.lines.any(
              (line) => line.label.toLowerCase().contains(needle),
            ))
          transfer,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TransfersViewmodel>();
    final rows = _visible(state.transfers);
    final refusal = state.loadError ?? state.locationError ?? state.actionError;

    final content = ListView(
      padding: EdgeInsets.zero,
      children: [
        _toolbar(state),
        const SizedBox(height: AppSpacing.md),
        if (refusal != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: ErrorBanner(message: refusal, onRetry: state.load),
          ),
        _table(state, rows),
      ],
    );

    const title = 'Transfers';
    const subtitle =
        'Move stock between Store and Bodega shelves — balances update automatically on both sides.';
    return switch (widget.shell) {
      TransfersShell.inventory => InventorySkeletonLayout(
        title: title,
        subtitle: subtitle,
        selectedNavigationIndex: 13,
        scrollable: false,
        onNavigationSelected: (index) => navigateInventory(context, index),
        child: content,
      ),
      TransfersShell.sales => SalesSkeletonLayout(
        title: title,
        subtitle: subtitle,
        // Looked up, never literal: Quotations occupied 2 until its hide
        // shifted every later row (Transfers 11 -> 10).
        selectedNavigationIndex: AppDestinations.indexOf(
          'transfers',
          AppAreas.sales,
        ),
        scrollable: false,
        onNavigationSelected: (index) => navigateSales(context, index),
        child: content,
      ),
    };
  }

  Widget _toolbar(TransfersViewmodel state) {
    return Row(
      children: [
        SizedBox(
          width: 340,
          height: 40,
          child: TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: 'Find a slip, shelf or product',
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ),
        const Spacer(),
        SizedBox(
          height: 40,
          child: FilledButton.icon(
            key: const ValueKey('transfers-record'),
            onPressed: state.isRecording ? null : _record,
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: const Text('Record transfer'),
          ),
        ),
      ],
    );
  }

  Widget _table(TransfersViewmodel state, List<StockTransfer> rows) {
    return DataPanel<StockTransfer>(
      title: 'Transfer slips',
      count: rows.length,
      rows: rows,
      isLoading: state.isLoading && state.transfers.isEmpty,
      error: state.transfers.isEmpty ? state.loadError : null,
      onRetry: state.load,
      emptyMessage: _query.trim().isEmpty
          ? 'No stock has moved between shelves yet.'
          : 'No transfer matches that search.',
      rowKey: (transfer) => ValueKey('transfer.${transfer.id}'),
      columns: [
        DataPanelColumn<StockTransfer>(
          label: 'Slip',
          flex: 3,
          cell: (transfer) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                transfer.number,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (transfer.remarks.isNotEmpty)
                Text(
                  transfer.remarks,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        DataPanelColumn<StockTransfer>(
          label: 'Route',
          flex: 3,
          cell: (transfer) {
            final toBodega = transfer.toLocationName.toLowerCase().contains(
              'bodega',
            );
            final bg = toBodega ? AppColors.warningTint : AppColors.successTint;
            final fg = toBodega ? AppColors.warningText : AppColors.successText;
            return Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swap_horiz_rounded, size: 14, color: fg),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        transfer.routeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        DataPanelColumn<StockTransfer>(
          label: 'Moved',
          flex: 2,
          numeric: true,
          cell: (transfer) => Text(
            '${transfer.lineCount} '
            '${transfer.lineCount == 1 ? 'line' : 'lines'} · '
            '${formatQuantity(transfer.movedBaseQty)}',
            maxLines: 2,
          ),
        ),
        DataPanelColumn<StockTransfer>(
          label: 'Recorded',
          flex: 3,
          cell: (transfer) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                transfer.userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                transfer.createdAt == null
                    ? ''
                    : formatDateTime(transfer.createdAt!),
                maxLines: 2,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        DataPanelColumn<StockTransfer>(
          label: 'Actions',
          flex: 2,
          cell: (transfer) => TextButton(
            key: ValueKey('transfer-slip-${transfer.id}'),
            onPressed: () => _showSlip(transfer),
            child: const Text('View slip'),
          ),
        ),
      ],
    );
  }
}

/// One recorded slip, whole: where the stock went and what each line moved.
///
/// A dialog rather than a printed PDF because the slip is the RECORD of a shelf
/// state, not a document a customer carries. Nothing here is editable — the
/// route is append-only, so a mistake is corrected by moving the stock back.
class _TransferSlipDialog extends StatelessWidget {
  const _TransferSlipDialog({required this.transfer});

  final StockTransfer transfer;

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.receipt_long_rounded,
      title: transfer.number,
      subtitle: transfer.routeLabel,
      width: 620,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.xs,
            children: [
              Text('Recorded by ${transfer.userName}'),
              if (transfer.createdAt != null)
                Text(formatDateTime(transfer.createdAt!)),
              Text('${formatQuantity(transfer.movedBaseQty)} of stock moved'),
            ],
          ),
          if (transfer.remarks.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              transfer.remarks,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          for (final line in transfer.lines) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              line.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              '${formatQuantity(line.qty)} ${line.unit} · '
              '${formatQuantity(line.baseQty)} of stock'
              '${line.moves.length > 1 ? ' · drawn from ${line.moves.length} lots, oldest first' : ''}',
              maxLines: 3,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (transfer.lines.isEmpty)
            const Text('This slip recorded no lines.'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
