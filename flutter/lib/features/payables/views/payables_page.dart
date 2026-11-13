import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/supplier_payables.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/payables/viewmodels/payables_viewmodel.dart';
import 'package:client/features/payables/widgets/supplier_bill_details_dialog.dart';
import 'package:client/features/payables/widgets/supplier_cheque_queue_tab.dart';
import 'package:client/features/payables/widgets/supplier_credit_notes_tab.dart';
import 'package:client/features/payables/widgets/supplier_pay_dialog.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Which role shell the same screen body is drawn in.
///
/// The shell is also the AUTHORITY (decision 18): a supplier payment is writable
/// by the Store Manager and Admin only, and those two are exactly the accounts
/// whose active area is `sales` or `admin`. A Stock Manager reads this screen in
/// the inventory shell and is never offered a Pay control, which matches the
/// server's 403 rather than discovering it.
enum PayablesShell { inventory, sales, admin }

/// Supplier payables in the Stock Manager's shell (inventory sidebar index 13,
/// APPENDED so no earlier tab moves). Read-only here.
class InventoryPayablesPage extends StatelessWidget {
  const InventoryPayablesPage({super.key, this.viewmodel});

  /// Injected by tests so a state can be rendered without a server.
  final PayablesViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => (viewmodel ?? PayablesViewmodel())..load(),
    child: const _PayablesBody(shell: PayablesShell.inventory),
  );
}

/// Supplier payables in the Store Manager's sales shell (sales sidebar index 9,
/// APPENDED). The manager records payments here.
class SalesPayablesPage extends StatelessWidget {
  const SalesPayablesPage({super.key, this.viewmodel});

  final PayablesViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => (viewmodel ?? PayablesViewmodel())..load(),
    child: const _PayablesBody(shell: PayablesShell.sales),
  );
}

/// Supplier payables in the Admin shell (admin sidebar index 8, APPENDED).
class AdminPayablesPage extends StatelessWidget {
  const AdminPayablesPage({super.key, this.viewmodel});

  final PayablesViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => (viewmodel ?? PayablesViewmodel())..load(),
    child: const _PayablesBody(shell: PayablesShell.admin),
  );
}

/// The one screen body, shared by the three shells so the numbers and the rules
/// cannot drift between roles.
class _PayablesBody extends StatefulWidget {
  const _PayablesBody({required this.shell});

  final PayablesShell shell;

  @override
  State<_PayablesBody> createState() => _PayablesBodyState();
}

class _PayablesBodyState extends State<_PayablesBody> {
  static const String _anyStatus = 'All statuses';
  static const String _overdueChip = 'Overdue only';

  SupplierBillStatus? _status;
  bool _overdueOnly = false;
  int? _supplierId;

  /// Which tab is showing: Bills, Credit notes, Supplier cheques.
  int _tab = 0;

  /// Recording a payment is the Store Manager's and Admin's job; the server
  /// answers 403 to anyone else, so the control is not rendered.
  bool get _canPay => widget.shell != PayablesShell.inventory;

  Future<void> _pay(SupplierBill bill) async {
    final state = context.read<PayablesViewmodel>();
    state.clearPayError();
    // The supplier's open credit is what the dialog may offer; a screen that has
    // not read it yet reads it now (once — a retry after a failure).
    await state.ensureCreditNotes();
    if (!mounted) return;
    final recorded = await showDialog<bool>(
      context: context,
      builder: (_) => SupplierPayDialog(
        bill: bill,
        creditNotes: state.openCreditNotesFor(bill.supplierId),
        onSubmit: (request) => state.pay(
          bill: bill,
          amount: request.amount,
          method: request.method,
          reference: request.reference,
          chequeNumber: request.chequeNumber,
          chequeBank: request.chequeBank,
          chequeDate: request.chequeDate,
          creditNoteId: request.creditNoteId,
        ),
      ),
    );
    if (recorded == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment recorded against bill #${bill.id}.')),
      );
    }
  }

  Future<void> _openBill(SupplierBill bill) async {
    final state = context.read<PayablesViewmodel>();
    // A CREDIT row names the note it spent, so the notes are read before the
    // history is drawn (a failure here still leaves the rows readable by id).
    await state.ensureCreditNotes();
    if (!mounted) return;
    final wantsPay = await showDialog<bool>(
      context: context,
      builder: (_) => SupplierBillDetailsDialog(
        bill: bill,
        canPay: _canPay,
        creditNotes: state.creditNotes,
      ),
    );
    if (wantsPay == true && mounted) await _pay(bill);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PayablesViewmodel>();
    final bills = state.filteredBills(
      supplierId: _supplierId,
      status: _status,
      overdueOnly: _overdueOnly,
    );
    final failure = state.loadError;
    final staleRows = failure != null && bills.isNotEmpty;
    final filtered = _status != null || _overdueOnly || _supplierId != null;

    final content = ListView(
      padding: EdgeInsets.zero,
      children: [
        _filters(state),
        const SizedBox(height: AppSpacing.md),
        if (staleRows)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: ErrorBanner(message: failure, onRetry: state.load),
          ),
        _summaryTable(state),
        const SizedBox(height: AppSpacing.lg),
        // Bills | Credit notes | Supplier cheques — TABS, not sidebar entries:
        // every earlier index (13 / 9 / 8) stays exactly where it was.
        //
        // No TabBarView: it demands a height of its own, and this page scrolls
        // as one list (the shape it had before the tabs). Only the selected
        // tab is built, exactly like TabBarView.
        DefaultTabController(
          length: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TabBar(
                onTap: (index) => setState(() => _tab = index),
                tabs: const [
                  Tab(key: ValueKey('payables-tab-bills'), text: 'Bills'),
                  Tab(
                    key: ValueKey('payables-tab-credit-notes'),
                    text: 'Credit notes',
                  ),
                  Tab(
                    key: ValueKey('payables-tab-cheques'),
                    text: 'Supplier cheques',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              switch (_tab) {
                1 => SupplierCreditNotesTab(supplierId: _supplierId),
                2 => SupplierChequeQueueTab(canDecide: _canPay),
                _ => _billsTable(state, bills, filtered),
              },
            ],
          ),
        ),
      ],
    );

    return switch (widget.shell) {
      PayablesShell.inventory => InventorySkeletonLayout(
        title: 'Payables',
        subtitle: 'What the shop owes each supplier, and when it is due.',
        selectedNavigationIndex: 13,
        scrollable: false,
        onNavigationSelected: (index) => navigateInventory(context, index),
        child: content,
      ),
      PayablesShell.sales => SalesSkeletonLayout(
        title: 'Payables',
        subtitle: 'What the shop owes each supplier, and when it is due.',
        selectedNavigationIndex: 9,
        scrollable: false,
        onNavigationSelected: (index) => navigateSales(context, index),
        child: content,
      ),
      PayablesShell.admin => AdminSkeletonLayout(
        title: 'Payables',
        subtitle: 'What the shop owes each supplier, and when it is due.',
        selectedNavigationIndex: 8,
        scrollable: false,
        // The admin shell navigates from its own tuple list, so it needs no
        // callback here.
        child: content,
      ),
    };
  }

  Widget _filters(PayablesViewmodel state) {
    final chips = [
      _anyStatus,
      for (final status in SupplierBillStatus.values) status.label,
    ];
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [
        SizedBox(
          width: 320,
          child: FilterBar(
            searchHint: 'Find a bill or supplier',
            options: chips,
            selected: _status == null ? chips.first : _status!.label,
            onSelected: (chip) => setState(() {
              final index = chips.indexOf(chip);
              _status = index <= 0
                  ? null
                  : SupplierBillStatus.values[index - 1];
            }),
            extraOptions: const [_overdueChip],
            extraSelected: _overdueOnly ? _overdueChip : null,
            onExtraSelected: (_) =>
                setState(() => _overdueOnly = !_overdueOnly),
          ),
        ),
        if (state.suppliers.isNotEmpty)
          DropdownButton<int?>(
            key: const ValueKey('payables-supplier-filter'),
            value: _supplierId,
            hint: const Text('All suppliers'),
            items: [
              const DropdownMenuItem<int?>(child: Text('All suppliers')),
              for (final supplier in state.suppliers)
                DropdownMenuItem<int?>(
                  value: supplier.supplierId,
                  child: Text(supplier.supplierName),
                ),
            ],
            onChanged: (value) => setState(() => _supplierId = value),
          ),
      ],
    );
  }

  Widget _summaryTable(PayablesViewmodel state) {
    return DataPanel<SupplierPayable>(
      title: 'Owed per supplier',
      count: state.suppliers.length,
      rows: state.suppliers,
      isLoading: state.isLoading && state.suppliers.isEmpty,
      error: state.bills.isEmpty ? state.loadError : null,
      onRetry: state.load,
      emptyMessage:
          'No supplier bills yet. A bill is written when a goods receipt is '
          'processed.',
      rowKey: (row) => ValueKey('payables-supplier.${row.supplierId}'),
      columns: [
        DataPanelColumn<SupplierPayable>(
          label: 'Supplier',
          flex: 3,
          cell: (row) => Text(
            row.supplierName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DataPanelColumn<SupplierPayable>(
          label: 'Bills',
          numeric: true,
          cell: (row) => Text(formatCount(row.billCount)),
        ),
        DataPanelColumn<SupplierPayable>(
          label: 'Original',
          numeric: true,
          flex: 2,
          cell: (row) => Text(formatPeso(row.original)),
        ),
        DataPanelColumn<SupplierPayable>(
          label: 'Paid',
          numeric: true,
          flex: 2,
          cell: (row) => Text(formatPeso(row.paid)),
        ),
        DataPanelColumn<SupplierPayable>(
          label: 'Balance',
          numeric: true,
          flex: 2,
          cell: (row) => Text(formatPeso(row.balance)),
        ),
        DataPanelColumn<SupplierPayable>(
          label: 'Overdue',
          numeric: true,
          flex: 2,
          cell: (row) => Text(
            formatPeso(row.overdue),
            style: TextStyle(
              color: row.overdue > 0 ? AppColors.errorText : null,
            ),
          ),
        ),
        // Its OWN column, never subtracted from the balance: credit the shop
        // holds is not a debt, and a negative balance would read as one.
        DataPanelColumn<SupplierPayable>(
          label: 'Unapplied credit',
          numeric: true,
          flex: 2,
          cell: (row) => Text(
            formatPeso(row.unappliedCredit),
            style: TextStyle(
              color: row.unappliedCredit > 0
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _billsTable(
    PayablesViewmodel state,
    List<SupplierBill> bills,
    bool filtered,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: DataPanel<SupplierBill>(
        title: 'Bills',
        count: bills.length,
        rows: bills,
        isLoading: state.isLoading && bills.isEmpty,
        error: state.bills.isEmpty ? state.loadError : null,
        onRetry: state.load,
        emptyMessage: filtered
            ? 'No supplier bills match these filters.'
            : 'No supplier bills yet. A bill is written when a goods receipt is '
                  'processed, so nothing is owed until then.',
        onRowTap: _openBill,
        rowKey: (bill) => ValueKey('payables-bill.${bill.id}'),
        columns: [
          DataPanelColumn<SupplierBill>(
            label: 'Bill',
            flex: 2,
            cell: (bill) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bill #${bill.id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Received ${formatDate(bill.receivedDate)}',
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
          DataPanelColumn<SupplierBill>(
            label: 'Supplier',
            flex: 3,
            cell: (bill) => Text(
              bill.supplierName.isEmpty
                  ? 'No supplier on file'
                  : bill.supplierName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          DataPanelColumn<SupplierBill>(
            label: 'Due',
            flex: 2,
            cell: (bill) => Text(
              formatDate(bill.dueDate),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          DataPanelColumn<SupplierBill>(
            label: 'Total',
            numeric: true,
            flex: 2,
            cell: (bill) => Text(formatPeso(bill.totalAmount)),
          ),
          DataPanelColumn<SupplierBill>(
            label: 'Balance',
            numeric: true,
            flex: 2,
            cell: (bill) => Text(
              formatPeso(bill.balanceAmount),
              style: TextStyle(
                color: bill.balanceAmount > 0 ? AppColors.errorText : null,
              ),
            ),
          ),
          DataPanelColumn<SupplierBill>(
            label: 'Status',
            flex: 2,
            cell: (bill) => bill.isOverdue
                ? const StatusBadge(label: 'Overdue', tone: StatusTone.error)
                : StatusBadge(
                    label: bill.status.label,
                    tone: bill.status == SupplierBillStatus.paid
                        ? StatusTone.success
                        : bill.status == SupplierBillStatus.partial
                        ? StatusTone.warning
                        : StatusTone.neutral,
                  ),
          ),
          DataPanelColumn<SupplierBill>(
            label: 'Actions',
            flex: 2,
            cell: (bill) => bill.canPay && _canPay
                ? IconButton(
                    tooltip: 'Record a payment',
                    onPressed: () => _pay(bill),
                    icon: const Icon(Icons.payments_outlined, size: 18),
                  )
                : Text(
                    bill.canPay
                        ? 'Read only'
                        : bill.status == SupplierBillStatus.paid
                        ? 'Settled'
                        : 'No balance',
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
