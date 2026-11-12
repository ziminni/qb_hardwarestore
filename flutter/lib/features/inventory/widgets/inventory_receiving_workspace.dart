import 'dart:math' as math;

import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/receiving_viewmodel.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/empty_state.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// One quantity as the screen writes it: `10` for a whole number, `2.50` when a
/// line is sold by weight. Server quantities are decimals, so a plain
/// `toStringAsFixed(0)` would round 2.5 kilos to 3.
String receivingQtyLabel(double value) => value == value.roundToDouble()
    ? formatCount(value.round())
    : value.toStringAsFixed(2);

/// One PO-unit count with the unit the order named: `2 BAG`.
///
/// A line from a server that predates units names none, and then the number is
/// written alone rather than labelled with a guessed unit.
String poQtyLabel(double qty, PurchaseOrderItem item) => item.unitCode.isEmpty
    ? receivingQtyLabel(qty)
    : '${receivingQtyLabel(qty)} ${item.unitCode}';

/// `2 BAG = 50 KG` — what a counted line becomes in stock, or '' when the line
/// is already counted in base units (factor 1, or no unit on the wire).
///
/// This is a LABEL, never a conversion the client performs on the payload: the
/// server multiplies by the factor when it turns the receipt into batches.
String poConversionLabel(
  PurchaseOrderItem item,
  double qty, {
  String baseUomCode = '',
}) {
  if (item.unitCode.isEmpty || item.baseFactor == 1) return '';
  final base = baseUomCode.isEmpty ? 'base units' : baseUomCode;
  return '${formatQuantity(qty)} ${item.unitCode} = '
      '${formatQuantity(qty * item.baseFactor)} $base';
}

/// Receiving a purchase order, as the three steps it really is: pick the order,
/// record what arrived, then process the receipt into FIFO stock.
///
/// The steps are always on screen and each one says whether it is done, next, or
/// still waiting. The old screen showed "Process into stock" only after the
/// receipt had been recorded, so a reader who stopped after the first button had
/// no way to see that stock was not updated yet (plan 08, problem 1).
///
/// The order list and the receipt sit side by side once the window is wide
/// enough to hold both (`twoPaneBreakpoint`) and stack below it, narrow first.
class InventoryReceivingWorkspace extends StatelessWidget {
  const InventoryReceivingWorkspace({
    super.key,
    required this.viewmodel,
    this.onPrintLabels,
  });

  final ReceivingViewmodel viewmodel;

  /// Offered once the receipt is processed. The page owns the label picker,
  /// because that is a different feature (`features/labels`).
  final VoidCallback? onPrintLabels;

  /// The picker sits beside the steps above this content width and above them
  /// below it. 960 px is where a 340 px list leaves the steps enough room for a
  /// 44 px stepper beside a product name.
  static const double twoPaneBreakpoint = 960;

  @override
  Widget build(BuildContext context) {
    if (viewmodel.isLoading && !viewmodel.hasOrders) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final failure = viewmodel.loadError;
    // A failed FIRST load is one banner with the way out, never an empty order
    // book: "nothing is waiting" is a fact a failed read has not established.
    if (failure != null && !viewmodel.hasOrders) {
      return ErrorBanner(message: failure, onRetry: viewmodel.load);
    }

    final suppliers = context.watch<SuppliersPurchasesViewmodel?>()?.suppliers;
    final supplierNames = <int, String>{
      for (final supplier in suppliers ?? const <Supplier>[])
        supplier.id: supplier.companyName,
    };

    final selected = viewmodel.selected;
    final picker = _OrderPicker(
      viewmodel: viewmodel,
      supplierNames: supplierNames,
    );
    // A new key per order: the quantity boxes and the delivery receipt number
    // belong to the order they were filled in for, not to the screen.
    final steps = _ReceiptSteps(
      key: ValueKey('receiving-steps-${selected?.id}'),
      viewmodel: viewmodel,
      supplierName: selected == null
          ? null
          : supplierNames[selected.supplierId],
      onPrintLabels: onPrintLabels,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (failure != null) ...[
          // A failed refresh keeps the orders it already had and says why above
          // them.
          ErrorBanner(message: failure, onRetry: viewmodel.load),
          const SizedBox(height: AppSpacing.md),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < twoPaneBreakpoint) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  picker,
                  const SizedBox(height: AppSpacing.md),
                  steps,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 340, child: picker),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: steps),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Done / now / waiting, the three states a step can be in.
enum _StepState { done, now, waiting }

/// One numbered step: what it is, and where it stands.
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.label, required this.state});

  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final (word, tone) = switch (state) {
      _StepState.done => ('Done', StatusTone.success),
      _StepState.now => ('Now', StatusTone.info),
      _StepState.waiting => ('Waiting', StatusTone.neutral),
    };
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        StatusBadge(label: word, tone: tone),
      ],
    );
  }
}

/// Step 1: the purchase orders waiting for a delivery.
class _OrderPicker extends StatelessWidget {
  const _OrderPicker({required this.viewmodel, required this.supplierNames});

  final ReceivingViewmodel viewmodel;

  /// Supplier names by id. Empty when the suppliers list has not been loaded
  /// (the receiving screen does not fetch it); the row then names the order by
  /// what it does know instead of inventing a supplier.
  final Map<int, String> supplierNames;

  @override
  Widget build(BuildContext context) {
    final orders = viewmodel.orders;
    final selectedId = viewmodel.selected?.id;
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepHeader(
            label: '1 Pick a purchase order',
            state: selectedId == null ? _StepState.now : _StepState.done,
          ),
          const SizedBox(height: AppSpacing.md),
          if (orders.isEmpty)
            const EmptyState(
              icon: Icons.inbox_outlined,
              message:
                  'No order is waiting to be received. Only ORDERED or '
                  'PARTIAL purchase orders can be received.',
            )
          else
            for (var index = 0; index < orders.length; index++) ...[
              if (index > 0) const SizedBox(height: AppSpacing.sm),
              _OrderRow(
                order: orders[index],
                supplierName: supplierNames[orders[index].supplierId],
                selected: selectedId == orders[index].id,
                onTap: () => viewmodel.select(orders[index]),
              ),
            ],
        ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.order,
    required this.supplierName,
    required this.selected,
    required this.onTap,
  });

  final PurchaseOrderRecord order;
  final String? supplierName;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lines = order.items.length;
    final ordered = order.items.fold<double>(
      0,
      (sum, item) => sum + item.orderedQty,
    );
    final supplier = supplierName;
    final detail = supplier == null
        ? '${lines == 1 ? '1 line' : '${formatCount(lines)} lines'} · '
              '${receivingQtyLabel(ordered)} ordered'
        : '$supplier · ${receivingQtyLabel(ordered)} ordered';
    return Material(
      color: selected ? AppColors.selected : AppColors.cardBackground,
      borderRadius: BorderRadius.circular(AppRadii.medium),
      child: InkWell(
        key: Key('receiving-order-${order.id}'),
        borderRadius: BorderRadius.circular(AppRadii.medium),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: Border.all(
              color: selected ? AppColors.brandGold : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    'PO-${order.id}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  StatusBadge(
                    label: order.status,
                    tone: order.status == 'PARTIAL'
                        ? StatusTone.warning
                        : StatusTone.info,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                detail,
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
      ),
    );
  }
}

/// Steps 2 and 3 for the picked order: count what arrived and record it, then
/// turn the receipt into stock and print its labels.
class _ReceiptSteps extends StatefulWidget {
  const _ReceiptSteps({
    super.key,
    required this.viewmodel,
    required this.supplierName,
    required this.onPrintLabels,
  });

  final ReceivingViewmodel viewmodel;
  final String? supplierName;
  final VoidCallback? onPrintLabels;

  @override
  State<_ReceiptSteps> createState() => _ReceiptStepsState();
}

class _ReceiptStepsState extends State<_ReceiptSteps> {
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
      _controllers.putIfAbsent(
        poItemId,
        () => TextEditingController(
          text: switch (widget.viewmodel.qtyFor(poItemId)) {
            final qty? => receivingQtyLabel(qty),
            null => '',
          },
        ),
      );

  /// One unit up or down from what is typed. The box is the state; the stepper
  /// only writes into it.
  void _step(PurchaseOrderItem item, double delta) {
    final current = widget.viewmodel.qtyFor(item.id) ?? 0;
    final next = math.max(0.0, current + delta);
    _controllerFor(item.id).text = receivingQtyLabel(next);
    widget.viewmodel.setQty(item.id, next);
  }

  Future<void> _process() async {
    final ok = await widget.viewmodel.processReceipt();
    if (!mounted || !ok) return;
    final batches = widget.viewmodel.lastBatches.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${batches == 1 ? '1 batch' : '$batches batches'} created.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = widget.viewmodel;
    final order = viewmodel.selected;
    final receiptId = viewmodel.lastReceiptId;
    final processed = viewmodel.isProcessed;
    final supplier = widget.supplierName;
    final lines = order?.items.length ?? 0;
    final ordered =
        order?.items.fold<double>(0, (sum, item) => sum + item.orderedQty) ?? 0;
    final received =
        order?.items.fold<double>(0, (sum, item) => sum + item.receivedQty) ??
        0;
    final batches = viewmodel.lastBatches.length;

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (order == null)
            const Text(
              'Select a purchase order to receive it.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'PO-${order.id} · ${order.status}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                StatusBadge(
                  label: order.status,
                  tone: order.status == 'PARTIAL'
                      ? StatusTone.warning
                      : StatusTone.info,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              [
                ?supplier,
                lines == 1 ? '1 line' : '${formatCount(lines)} lines',
                '${receivingQtyLabel(ordered)} ordered',
                '${receivingQtyLabel(received)} received',
              ].join(' · '),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _StepHeader(
            label: '2 Record receipt',
            state: order == null
                ? _StepState.waiting
                : receiptId == null
                ? _StepState.now
                : _StepState.done,
          ),
          const SizedBox(height: AppSpacing.md),
          if (order == null)
            const Text(
              'Pick a purchase order first. Count what arrived here, then '
              'record it.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            )
          else if (receiptId == null) ...[
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _ReceiptLineRow(
                  item: item,
                  controller: _controllerFor(item.id),
                  onChanged: (text) {
                    final parsed = double.tryParse(text.trim());
                    if (parsed == null) {
                      viewmodel.clearQty(item.id);
                    } else {
                      viewmodel.setQty(item.id, parsed);
                    }
                  },
                  onStep: (delta) => _step(item, delta),
                ),
              ),
            TextField(
              controller: _deliveryController,
              decoration: const InputDecoration(
                labelText: 'Delivery receipt no.',
                helperText: 'Optional. Printed on the delivery labels.',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (viewmodel.actionError != null) ...[
              ErrorBanner(message: viewmodel.actionError!),
              const SizedBox(height: AppSpacing.md),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: viewmodel.isActing || !viewmodel.hasQuantities
                    ? null
                    : () => viewmodel.recordReceipt(
                        deliveryReceiptNo: _deliveryController.text.trim(),
                      ),
                child: const Text('Record receipt'),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Count at least one line to record the receipt.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ] else
            Text(
              'Receipt #$receiptId recorded. Now process it into stock so the '
              'counts can be sold.',
              style: const TextStyle(fontSize: 14),
            ),
          const Divider(height: AppSpacing.xxl),
          _StepHeader(
            label: '3 Process into stock',
            state: processed
                ? _StepState.done
                : order == null || receiptId == null
                ? _StepState.waiting
                : _StepState.now,
          ),
          const SizedBox(height: AppSpacing.md),
          if (processed) ...[
            Text(
              '${batches == 1 ? '1 batch' : '$batches batches'} created from '
              'receipt #$receiptId.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: widget.onPrintLabels,
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print labels for this delivery'),
              ),
            ),
          ] else ...[
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed:
                    order == null || receiptId == null || viewmodel.isActing
                    ? null
                    : _process,
                child: const Text('Process into stock'),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Creates FIFO batches from the recorded quantities. Stock only '
              'moves after this.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// One purchase order line: what was ordered, what already arrived, and a box
/// with a stepper for what arrived this time.
class _ReceiptLineRow extends StatelessWidget {
  const _ReceiptLineRow({
    required this.item,
    required this.controller,
    required this.onChanged,
    required this.onStep,
  });

  final PurchaseOrderItem item;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<double> onStep;

  @override
  Widget build(BuildContext context) {
    // The base unit's code is catalogue data, not PO data: the line knows its
    // own unit, and the helper names what it lands as in stock.
    final baseUomCode =
        context
            .watch<InventoryViewmodel?>()
            ?.variantFor(item.variantId)
            ?.baseUomCode ??
        '';
    final typed = double.tryParse(controller.text.trim());
    final conversion = typed == null
        ? ''
        : poConversionLabel(item, typed, baseUomCode: baseUomCode);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.variantName,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Ordered ${poQtyLabel(item.orderedQty, item)} · already received '
            '${poQtyLabel(item.receivedQty, item)}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // The box takes the width it needs and the stepper stays beside it, so
          // a long product name above never squeezes the number out of sight.
          Row(
            children: [
              IconButton.outlined(
                tooltip: 'One less',
                onPressed: () => onStep(-1),
                icon: const Icon(Icons.remove, size: 18),
              ),
              SizedBox(
                width: 128,
                child: TextField(
                  key: Key('receiving-qty-${item.id}'),
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    hintText: '0',
                    suffixText: item.unitCode.isEmpty ? null : item.unitCode,
                    helperText: conversion.isEmpty ? null : conversion,
                    helperMaxLines: 2,
                    isDense: true,
                  ),
                  onChanged: onChanged,
                ),
              ),
              IconButton.outlined(
                tooltip: 'One more',
                onPressed: () => onStep(1),
                icon: const Icon(Icons.add, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
