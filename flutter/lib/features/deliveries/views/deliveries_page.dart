import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/delivery.dart';
import 'package:client/features/deliveries/viewmodels/deliveries_viewmodel.dart';
import 'package:client/features/deliveries/widgets/delivery_slip_document.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';

/// Hands a delivery slip to the platform.
///
/// An interface for the same reason as `ReceiptPrinter`: a widget test asserts
/// WHAT would be printed without the printing plugin or a printer.
abstract class DeliverySlipPrinter {
  Future<void> print(Delivery delivery);
}

/// The real one: the OS print dialog, on the 80 mm roll the receipt uses.
class PdfDeliverySlipPrinter implements DeliverySlipPrinter {
  const PdfDeliverySlipPrinter();

  @override
  Future<void> print(Delivery delivery) {
    return Printing.layoutPdf(
      name: delivery.documentNo,
      format: deliverySlipPageFormat,
      onLayout: (_) => buildDeliverySlipPdfWithOpenSans(delivery),
    );
  }
}

/// Which role shell the same screen body is drawn in.
///
/// Status moves are writable by the Store Manager, Admin and Stock Manager — the
/// three accounts that reach this screen at all. A Cashier has no deliveries
/// page: the server scopes a cashier to their OWN slips but refuses a move with
/// 403, so a view that could only be read is not offered (decision 18 leaves it
/// to the brief, and the sidebar stays as it was).
enum DeliveriesShell { inventory, sales, admin }

/// The delivery schedule in the Stock Manager's shell (inventory sidebar index
/// 14, APPENDED so no earlier tab moves).
class InventoryDeliveriesPage extends StatelessWidget {
  const InventoryDeliveriesPage({super.key, this.viewmodel, this.printer});

  /// Injected by tests so a state can be rendered without a server.
  final DeliveriesViewmodel? viewmodel;
  final DeliverySlipPrinter? printer;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => (viewmodel ?? DeliveriesViewmodel())..load(),
    child: _DeliveriesBody(shell: DeliveriesShell.inventory, printer: printer),
  );
}

/// The delivery schedule in the Store Manager's sales shell (sales sidebar index
/// 10, APPENDED).
class SalesDeliveriesPage extends StatelessWidget {
  const SalesDeliveriesPage({super.key, this.viewmodel, this.printer});

  final DeliveriesViewmodel? viewmodel;
  final DeliverySlipPrinter? printer;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => (viewmodel ?? DeliveriesViewmodel())..load(),
    child: _DeliveriesBody(shell: DeliveriesShell.sales, printer: printer),
  );
}

/// The delivery schedule in the Admin shell (admin sidebar index 9, APPENDED).
class AdminDeliveriesPage extends StatelessWidget {
  const AdminDeliveriesPage({super.key, this.viewmodel, this.printer});

  final DeliveriesViewmodel? viewmodel;
  final DeliverySlipPrinter? printer;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => (viewmodel ?? DeliveriesViewmodel())..load(),
    child: _DeliveriesBody(shell: DeliveriesShell.admin, printer: printer),
  );
}

/// The one screen body, shared by the three shells so the rules and the numbers
/// cannot drift between roles.
class _DeliveriesBody extends StatefulWidget {
  const _DeliveriesBody({required this.shell, this.printer});

  final DeliveriesShell shell;
  final DeliverySlipPrinter? printer;

  @override
  State<_DeliveriesBody> createState() => _DeliveriesBodyState();
}

class _DeliveriesBodyState extends State<_DeliveriesBody> {
  static const String _anyStatus = 'All statuses';

  DeliveryStatus? _status;
  DateTime? _from;
  DateTime? _to;
  String _query = '';

  /// One print at a time: the OS dialog is modal, so a second press while it is
  /// open would queue the same slip twice.
  bool _printing = false;

  DeliverySlipPrinter get _printer =>
      widget.printer ?? const PdfDeliverySlipPrinter();

  Future<void> _start(Delivery delivery) async {
    final state = context.read<DeliveriesViewmodel>();
    final moved = await state.start(delivery.id);
    if (!mounted) return;
    if (moved) {
      _say('${delivery.documentNo} is out for delivery.');
    }
  }

  Future<void> _deliver(Delivery delivery) async {
    final state = context.read<DeliveriesViewmodel>();
    final moved = await state.deliver(delivery.id);
    if (!mounted) return;
    if (moved) _say('${delivery.documentNo} is delivered.');
  }

  Future<void> _fail(Delivery delivery) async {
    final state = context.read<DeliveriesViewmodel>();
    state.clearActionError();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _FailureReasonDialog(delivery: delivery),
    );
    if (reason == null || !mounted) return;
    final moved = await state.fail(delivery.id, reason);
    if (!mounted) return;
    if (moved) _say('${delivery.documentNo} is marked failed.');
  }

  Future<void> _print(Delivery delivery) async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      await _printer.print(delivery);
    } catch (error) {
      // The trip is already recorded; only the paper failed.
      if (mounted) _say('Could not print the delivery slip: $error');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  void _say(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DeliveriesViewmodel>();
    final rows = state.filtered(
      status: _status,
      dateFrom: _from,
      dateTo: _to,
      query: _query,
    );
    final filtered =
        _status != null || _from != null || _to != null || _query.isNotEmpty;
    final refusal = state.actionError;

    final content = ListView(
      padding: EdgeInsets.zero,
      children: [
        _filters(),
        const SizedBox(height: AppSpacing.md),
        if (refusal != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: ErrorBanner(
              message: refusal,
              onRetry: state.clearActionError,
            ),
          ),
        _table(state, rows, filtered),
      ],
    );

    return switch (widget.shell) {
      DeliveriesShell.inventory => InventorySkeletonLayout(
        title: 'Deliveries',
        subtitle: 'The delivery schedule: what goes out, when, and by whom.',
        selectedNavigationIndex: 14,
        scrollable: false,
        onNavigationSelected: (index) => navigateInventory(context, index),
        child: content,
      ),
      DeliveriesShell.sales => SalesSkeletonLayout(
        title: 'Deliveries',
        subtitle: 'The delivery schedule: what goes out, when, and by whom.',
        selectedNavigationIndex: 10,
        scrollable: false,
        onNavigationSelected: (index) => navigateSales(context, index),
        child: content,
      ),
      DeliveriesShell.admin => AdminSkeletonLayout(
        title: 'Deliveries',
        subtitle: 'The delivery schedule: what goes out, when, and by whom.',
        selectedNavigationIndex: 9,
        scrollable: false,
        // The admin shell navigates from its own tuple list, so it needs no
        // callback here.
        child: content,
      ),
    };
  }

  Widget _filters() {
    final chips = [
      _anyStatus,
      for (final status in DeliveryStatus.values) status.label,
    ];
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [
        SizedBox(
          width: 320,
          child: FilterBar(
            searchHint: 'Find a delivery or customer',
            onSearchChanged: (value) => setState(() => _query = value),
            options: chips,
            selected: _status == null ? chips.first : _status!.label,
            onSelected: (chip) => setState(() {
              final index = chips.indexOf(chip);
              _status = index <= 0 ? null : DeliveryStatus.values[index - 1];
            }),
          ),
        ),
        OutlinedButton.icon(
          key: const ValueKey('deliveries-from-date'),
          onPressed: () => _pickDate(isFrom: true),
          icon: const Icon(Icons.event, size: 18),
          label: Text(_from == null ? 'From date' : formatDate(_from!)),
        ),
        OutlinedButton.icon(
          key: const ValueKey('deliveries-to-date'),
          onPressed: () => _pickDate(isFrom: false),
          icon: const Icon(Icons.event, size: 18),
          label: Text(_to == null ? 'To date' : formatDate(_to!)),
        ),
        if (_from != null || _to != null)
          TextButton(
            onPressed: () => setState(() {
              _from = null;
              _to = null;
            }),
            child: const Text('Clear dates'),
          ),
      ],
    );
  }

  Widget _table(DeliveriesViewmodel state, List<Delivery> rows, bool filtered) {
    return DataPanel<Delivery>(
      title: 'Delivery schedule',
      count: rows.length,
      rows: rows,
      isLoading: state.isLoading && state.deliveries.isEmpty,
      error: state.deliveries.isEmpty ? state.loadError : null,
      onRetry: state.load,
      emptyMessage: filtered
          ? 'No deliveries match these filters.'
          : 'No deliveries yet. A delivery is created when a sale or a sales '
                'order is marked Deliver.',
      rowKey: (delivery) => ValueKey('delivery.${delivery.id}'),
      columns: [
        DataPanelColumn<Delivery>(
          label: 'Document',
          flex: 2,
          cell: (delivery) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                delivery.documentNo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                delivery.sourceLabel,
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
        DataPanelColumn<Delivery>(
          label: 'Customer',
          flex: 3,
          cell: (delivery) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                delivery.customerName.isEmpty
                    ? 'No customer on file'
                    : delivery.customerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (delivery.contactPhone.isNotEmpty)
                Text(
                  delivery.contactPhone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
            ],
          ),
        ),
        DataPanelColumn<Delivery>(
          label: 'Date',
          flex: 2,
          cell: (delivery) =>
              Text(formatDate(delivery.scheduledDate), maxLines: 2),
        ),
        DataPanelColumn<Delivery>(
          label: 'Status',
          flex: 2,
          cell: (delivery) => StatusBadge(
            label: delivery.status.label,
            tone: _tone(delivery.status),
          ),
        ),
        DataPanelColumn<Delivery>(
          label: 'Fee',
          numeric: true,
          flex: 2,
          cell: (delivery) => Text(formatPeso(delivery.fee)),
        ),
        DataPanelColumn<Delivery>(
          label: 'Actions',
          flex: 3,
          cell: (delivery) => _actions(state, delivery),
        ),
      ],
    );
  }

  /// Start / Delivered / Failed, only where the status allows the move.
  ///
  /// A finished slip has no move left, so it says so instead of showing a button
  /// the server answers 409 to. Every button is disabled while ITS row is on the
  /// wire, which is what stops a double click becoming a second POST.
  Widget _actions(DeliveriesViewmodel state, Delivery delivery) {
    final busy = state.isMoving(delivery.id);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (delivery.status.canStart)
          TextButton(
            key: ValueKey('delivery-start-${delivery.id}'),
            onPressed: busy ? null : () => _start(delivery),
            child: const Text('Start'),
          ),
        if (delivery.status.canDeliver)
          TextButton(
            key: ValueKey('delivery-delivered-${delivery.id}'),
            onPressed: busy ? null : () => _deliver(delivery),
            child: const Text('Delivered'),
          ),
        if (delivery.status.canFail)
          TextButton(
            key: ValueKey('delivery-failed-${delivery.id}'),
            onPressed: busy ? null : () => _fail(delivery),
            child: const Text('Failed'),
          ),
        if (delivery.status.isFinished)
          Text(
            delivery.status == DeliveryStatus.delivered
                ? 'Delivered'
                : 'Failed',
            maxLines: 1,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        IconButton(
          key: ValueKey('delivery-slip-${delivery.id}'),
          tooltip: 'Print delivery slip',
          onPressed: _printing ? null : () => _print(delivery),
          icon: const Icon(Icons.print_outlined, size: 18),
        ),
      ],
    );
  }
}

StatusTone _tone(DeliveryStatus status) => switch (status) {
  DeliveryStatus.scheduled => StatusTone.neutral,
  DeliveryStatus.outForDelivery => StatusTone.warning,
  DeliveryStatus.delivered => StatusTone.success,
  DeliveryStatus.failed => StatusTone.error,
};

/// Why the trip failed. The reason is REQUIRED — the server stores it on the
/// row and refuses a bare failure (`DELIVERY_REASON_REQUIRED`).
class _FailureReasonDialog extends StatefulWidget {
  const _FailureReasonDialog({required this.delivery});

  final Delivery delivery;

  @override
  State<_FailureReasonDialog> createState() => _FailureReasonDialogState();
}

class _FailureReasonDialogState extends State<_FailureReasonDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Mark ${widget.delivery.documentNo} failed'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: TextFormField(
            key: const ValueKey('delivery-failure-reason'),
            controller: _reason,
            autofocus: true,
            maxLength: 255,
            decoration: const InputDecoration(
              labelText: 'Why did the goods not land?',
            ),
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'A failed delivery needs a reason.'
                : null,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, _reason.text.trim());
          },
          child: const Text('Mark failed'),
        ),
      ],
    );
  }
}
