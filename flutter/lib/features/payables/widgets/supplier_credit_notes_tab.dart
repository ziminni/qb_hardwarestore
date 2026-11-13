import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/supplier_returns.dart';
import 'package:client/features/payables/viewmodels/payables_viewmodel.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The credit this shop is owed (Phase 8 F3, decision 20 #1).
///
/// A note is minted by a supplier return and is append-only: the only figure
/// that ever moves is what is LEFT, when a manager spends it on a bill. So the
/// three money columns answer the only question this tab has — how much was it
/// worth, how much is already spent, how much can still be spent.
///
/// [supplierId] follows the page's supplier filter; null shows every supplier.
class SupplierCreditNotesTab extends StatefulWidget {
  const SupplierCreditNotesTab({super.key, this.supplierId});

  final int? supplierId;

  @override
  State<SupplierCreditNotesTab> createState() => _SupplierCreditNotesTabState();
}

class _SupplierCreditNotesTabState extends State<SupplierCreditNotesTab> {
  @override
  void initState() {
    super.initState();
    // Read once, when the tab is first opened: a note page nobody visits costs
    // no request.
    context.read<PayablesViewmodel>().ensureCreditNotes();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PayablesViewmodel>();
    final rows = [
      for (final note in state.creditNotes)
        if (widget.supplierId == null || note.supplierId == widget.supplierId)
          note,
    ];

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: DataPanel<SupplierCreditNote>(
        title: 'Credit notes',
        count: rows.length,
        rows: rows,
        isLoading: state.isLoadingCreditNotes && rows.isEmpty,
        error: state.creditNotesError,
        onRetry: state.ensureCreditNotes,
        emptyMessage: widget.supplierId != null && state.creditNotes.isNotEmpty
            ? 'This supplier holds no credit notes.'
            : 'No supplier credit notes yet. A credit note is written when '
                  'goods go back to a supplier.',
        rowKey: (note) => ValueKey('payables-credit-note.${note.id}'),
        columns: [
          DataPanelColumn<SupplierCreditNote>(
            label: 'Note',
            flex: 2,
            cell: (note) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.number,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (note.createdAt != null)
                  Text(
                    'Written ${formatDate(note.createdAt!)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          DataPanelColumn<SupplierCreditNote>(
            label: 'Supplier',
            flex: 3,
            cell: (note) => Text(
              note.supplierName.isEmpty
                  ? 'No supplier on file'
                  : note.supplierName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          DataPanelColumn<SupplierCreditNote>(
            label: 'Total',
            numeric: true,
            flex: 2,
            cell: (note) => Text(formatPeso(note.totalAmount)),
          ),
          DataPanelColumn<SupplierCreditNote>(
            label: 'Applied',
            numeric: true,
            flex: 2,
            cell: (note) => Text(formatPeso(note.appliedAmount)),
          ),
          DataPanelColumn<SupplierCreditNote>(
            label: 'Remaining',
            numeric: true,
            flex: 2,
            cell: (note) => Text(
              formatPeso(note.remainingAmount),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                // Spent credit is history; credit still to spend is the figure
                // a manager acts on, so only that one is inked.
                color: note.isOpen
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
          DataPanelColumn<SupplierCreditNote>(
            label: 'From bill',
            flex: 2,
            cell: (note) => Text(
              note.sourceBillId == null
                  ? 'No bill on file'
                  : 'Bill #${note.sourceBillId}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
