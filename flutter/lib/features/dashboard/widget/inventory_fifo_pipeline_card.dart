import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/shared/widgets/stitch_ui.dart';
import 'package:flutter/material.dart';

/// Real-time **Active FIFO Pipeline Queue** card matching the Stitch FIFO
/// command suite visual design (`28_stock_manager_fifo.png`).
///
/// Reads live `inventory.batches` (where `currentQty > 0`), groups them by
/// `variantId`, and sorts each variant's lots oldest `createdAt` first (true
/// FIFO outflow order). Allows switching between any stocked SKU/variant and
/// displays up to 3 visual FIFO pipeline stage cards with depletion bars,
/// landed COGS/unit, remaining FIFO value, and batch age in days.
class InventoryFifoPipelineCard extends StatefulWidget {
  const InventoryFifoPipelineCard({super.key, required this.inventory});

  final InventoryViewmodel inventory;

  @override
  State<InventoryFifoPipelineCard> createState() =>
      _InventoryFifoPipelineCardState();
}

class _FifoVariantOption {
  const _FifoVariantOption({
    required this.variantId,
    required this.displayName,
    required this.sku,
    required this.category,
    required this.location,
    required this.uom,
    required this.minStockThreshold,
    required this.batches,
    required this.totalQty,
    required this.totalValue,
  });

  final int variantId;
  final String displayName;
  final String sku;
  final String category;
  final String location;
  final String uom;
  final double minStockThreshold;
  final List<InventoryBatch> batches;
  final double totalQty;
  final double totalValue;

  double get weightedAvgCost => totalQty > 0 ? totalValue / totalQty : 0;
}

class _InventoryFifoPipelineCardState extends State<InventoryFifoPipelineCard> {
  int? _selectedVariantId;

  List<_FifoVariantOption> _buildOptions(InventoryViewmodel inventory) {
    final grouped = <int, List<InventoryBatch>>{};
    for (final batch in inventory.batches) {
      if (batch.currentQty <= 0) continue;
      grouped.putIfAbsent(batch.variantId, () => []).add(batch);
    }
    if (grouped.isEmpty) return const [];

    final variantMeta =
        <
          int,
          ({
            String name,
            String sku,
            String category,
            String location,
            String uom,
            double minThreshold,
          })
        >{};

    for (final product in inventory.products) {
      final category = product.categoryName.isEmpty
          ? 'Uncategorized'
          : product.categoryName;
      final productLocation = product.storedAtName.isEmpty
          ? 'Main Store'
          : product.storedAtName;
      for (final variant in product.variants) {
        final name = '${product.baseName} ${variant.variantName}'.trim();
        final location = variant.storedAtName.isNotEmpty
            ? variant.storedAtName
            : productLocation;
        final uom = variant.baseUomCode.isEmpty ? 'unit' : variant.baseUomCode;
        variantMeta[variant.id] = (
          name: name.isEmpty ? 'Variant #${variant.id}' : name,
          sku: variant.sku,
          category: category,
          location: location,
          uom: uom,
          minThreshold: variant.minStockThreshold,
        );
      }
    }

    final options = <_FifoVariantOption>[];
    for (final entry in grouped.entries) {
      final batches = [...entry.value]
        ..sort((a, b) {
          final aDate = a.createdAt;
          final bDate = b.createdAt;
          if (aDate != null && bDate != null) {
            final cmp = aDate.compareTo(bDate);
            if (cmp != 0) return cmp;
          } else if (aDate != null) {
            return -1;
          } else if (bDate != null) {
            return 1;
          }
          return a.id.compareTo(b.id);
        });

      var totalQty = 0.0;
      var totalValue = 0.0;
      for (final b in batches) {
        totalQty += b.currentQty;
        totalValue += b.currentQty * b.unitCostLanded;
      }

      final meta = variantMeta[entry.key];
      options.add(
        _FifoVariantOption(
          variantId: entry.key,
          displayName: meta?.name ?? 'Variant #${entry.key}',
          sku: meta?.sku ?? '',
          category: meta?.category ?? 'Uncategorized',
          location: meta?.location ?? 'Main Store',
          uom: meta?.uom ?? 'unit',
          minStockThreshold: meta?.minThreshold ?? 0,
          batches: batches,
          totalQty: totalQty,
          totalValue: totalValue,
        ),
      );
    }

    // Default to the variant with the most active batches, tie-broken by
    // highest total FIFO value, then variant id.
    options.sort((a, b) {
      final byCount = b.batches.length.compareTo(a.batches.length);
      if (byCount != 0) return byCount;
      final byValue = b.totalValue.compareTo(a.totalValue);
      if (byValue != 0) return byValue;
      return a.variantId.compareTo(b.variantId);
    });
    return options;
  }

  @override
  Widget build(BuildContext context) {
    final options = _buildOptions(widget.inventory);

    if (options.isEmpty) {
      return StitchSectionCard(
        key: const ValueKey('inventory-fifo-pipeline-card'),
        overline: 'FIFO Landed Cost Engine',
        title: 'Active FIFO Pipeline Queue',
        subtitle: 'Oldest active stock lot depletes first on every sale.',
        icon: Icons.layers_outlined,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: StitchColors.surfaceCanvas,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: StitchColors.cardBorder),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 18,
                color: StitchColors.inkMuted,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No active FIFO batches on hand yet. Receive stock to populate the FIFO outflow queue.',
                  style: TextStyle(fontSize: 13, color: StitchColors.inkMuted),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final selected = options.firstWhere(
      (o) => o.variantId == _selectedVariantId,
      orElse: () => options.first,
    );
    final stages = selected.batches.take(3).toList(growable: false);
    final hiddenCount = selected.batches.length - stages.length;

    return StitchSectionCard(
      key: const ValueKey('inventory-fifo-pipeline-card'),
      overline: 'FIFO Landed Cost Engine',
      title: 'Active FIFO Pipeline Queue',
      subtitle:
          'Order of dispatch enforced at cashier & stock outflow · oldest landed batch depletes first.',
      icon: Icons.layers_outlined,
      trailing: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          StitchPill(
            label:
                'Total on hand: ${formatQuantity(selected.totalQty)} ${selected.uom}',
            tone: StitchTone.primary,
          ),
          StitchPill(
            label:
                '${selected.batches.length} active ${selected.batches.length == 1 ? 'batch' : 'batches'}',
            tone: StitchTone.neutral,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SelectedVariantHeader(
            selected: selected,
            options: options,
            onChanged: (variantId) {
              if (variantId == null) return;
              setState(() => _selectedVariantId = variantId);
            },
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 820 || stages.length == 1) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < stages.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _FifoStageCard(
                        position: i + 1,
                        batch: stages[i],
                        uom: selected.uom,
                      ),
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < stages.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(
                      child: _FifoStageCard(
                        position: i + 1,
                        batch: stages[i],
                        uom: selected.uom,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          if (hiddenCount > 0) ...[
            const SizedBox(height: 10),
            Text(
              '+$hiddenCount more queued ${hiddenCount == 1 ? 'batch' : 'batches'} behind FIFO Pos #3.',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: StitchColors.inkMuted,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _FifoAccountingNote(selected: selected),
        ],
      ),
    );
  }
}

class _SelectedVariantHeader extends StatelessWidget {
  const _SelectedVariantHeader({
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  final _FifoVariantOption selected;
  final List<_FifoVariantOption> options;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final skuLabel = selected.sku.isNotEmpty
        ? selected.sku
        : 'VAR-${selected.variantId}';

    final info = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: StitchColors.primaryTint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.inventory_2_outlined,
            size: 20,
            color: StitchColors.primary,
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
                children: [
                  StitchPill(label: skuLabel, tone: StitchTone.primary),
                  StitchPill(
                    label: selected.category,
                    tone: StitchTone.neutral,
                  ),
                  StitchPill(
                    label: selected.location,
                    tone: StitchTone.success,
                    icon: Icons.storefront_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                selected.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: StitchColors.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Min buffer: ${formatQuantity(selected.minStockThreshold)} ${selected.uom} · '
                'Weighted landed avg: ${formatPeso(selected.weightedAvgCost)}/${selected.uom} · '
                'FIFO value: ${formatPeso(selected.totalValue)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: StitchColors.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final selector = SizedBox(
      width: 280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'SWITCH SKU / VARIANT',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: StitchColors.inkMuted,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: StitchColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: StitchColors.cardBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                key: const ValueKey('inventory-fifo-sku-dropdown'),
                value: selected.variantId,
                isExpanded: true,
                isDense: true,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: StitchColors.ink,
                ),
                items: [
                  for (final option in options)
                    DropdownMenuItem<int>(
                      value: option.variantId,
                      child: Text(
                        '${option.displayName} (${option.batches.length})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: StitchColors.surfaceCanvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StitchColors.cardBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 700) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 12),
                selector,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: info),
              const SizedBox(width: 16),
              selector,
            ],
          );
        },
      ),
    );
  }
}

class _FifoStageCard extends StatelessWidget {
  const _FifoStageCard({
    required this.position,
    required this.batch,
    required this.uom,
  });

  final int position;
  final InventoryBatch batch;
  final String uom;

  @override
  Widget build(BuildContext context) {
    final (
      Color accentColor,
      Color bgColor,
      StitchTone pillTone,
      String stageLabel,
      IconData stageIcon,
      String footerText,
    ) = switch (position) {
      1 => (
        StitchColors.danger,
        const Color(0xFFFFFAFA),
        StitchTone.danger,
        'FIFO POS #1 · NEXT TO OUTFLOW',
        Icons.local_fire_department_rounded,
        'Active outflow lot · Depletes first',
      ),
      2 => (
        StitchColors.primary,
        const Color(0xFFF8FAFF),
        StitchTone.primary,
        'FIFO POS #2 · QUEUED',
        Icons.schedule_rounded,
        'Unlocks automatically when Pos #1 hits 0',
      ),
      _ => (
        StitchColors.success,
        const Color(0xFFF7FDF9),
        StitchTone.success,
        'FIFO POS #3 · FRESH RESERVE',
        Icons.verified_outlined,
        'Queued reserve · Protected behind Pos #2',
      ),
    };

    final ageDays = batch.createdAt == null
        ? null
        : DateTime.now().difference(batch.createdAt!).inDays.clamp(0, 99999);
    final ageLabel = ageDays == null
        ? 'AGE N/A'
        : '$ageDays ${ageDays == 1 ? 'DAY' : 'DAYS'} OLD';
    final ageTone = position == 1
        ? StitchTone.danger
        : (position == 2 ? StitchTone.primary : StitchTone.success);

    final remainingRatio = batch.initialQty > 0
        ? (batch.currentQty / batch.initialQty).clamp(0.0, 1.0)
        : 1.0;
    final depletedPct = ((1.0 - remainingRatio) * 100).clamp(0.0, 100.0);
    final remainingValue = batch.currentQty * batch.unitCostLanded;

    return StitchAccentBox(
      accentColor: accentColor,
      backgroundColor: bgColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StitchPill(label: stageLabel, tone: pillTone, icon: stageIcon),
              StitchPill(label: ageLabel, tone: ageTone),
            ],
          ),
          const SizedBox(height: 12),
          _MetaRow(label: 'BATCH REF', value: 'Batch #${batch.id}', bold: true),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'RECEIVED DATE',
            value: batch.createdAt != null
                ? formatDate(batch.createdAt!)
                : 'Not recorded',
          ),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'REMAINING / INITIAL',
            value:
                '${formatQuantity(batch.currentQty)} / ${formatQuantity(batch.initialQty)} $uom',
            bold: true,
            valueColor: position == 1 ? StitchColors.danger : StitchColors.ink,
          ),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'LANDED COGS (FIFO)',
            value: '${formatPeso(batch.unitCostLanded)} / $uom',
            bold: true,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Depleted: ${depletedPct.toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: StitchColors.inkMuted,
                ),
              ),
              Text(
                '${formatPeso(remainingValue)} left',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: StitchColors.ink,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: remainingRatio,
              minHeight: 6,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: StitchColors.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: StitchColors.cardBorder),
            ),
            child: Text(
              footerText,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: position == 1
                    ? StitchColors.dangerInk
                    : StitchColors.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: StitchColors.inkMuted,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: valueColor ?? StitchColors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _FifoAccountingNote extends StatelessWidget {
  const _FifoAccountingNote({required this.selected});

  final _FifoVariantOption selected;

  @override
  Widget build(BuildContext context) {
    final first = selected.batches.first;
    final second = selected.batches.length > 1 ? selected.batches[1] : null;
    final explanation = second != null
        ? 'When a sale or stock outflow occurs, COGS is deducted at '
              '${formatPeso(first.unitCostLanded)} (Batch #${first.id}) until all '
              '${formatQuantity(first.currentQty)} remaining ${selected.uom} are depleted. '
              'Only then does the ledger roll to ${formatPeso(second.unitCostLanded)} '
              '(Batch #${second.id}).'
        : 'When a sale or stock outflow occurs, COGS is deducted at '
              '${formatPeso(first.unitCostLanded)} (Batch #${first.id}) in strict '
              'oldest-first FIFO order until all ${formatQuantity(first.currentQty)} '
              'remaining ${selected.uom} are depleted.';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StitchColors.primarySoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: StitchColors.primaryTint),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: StitchColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: StitchColors.inkMuted,
                ),
                children: [
                  const TextSpan(
                    text: 'How FIFO COGS deduction operates here: ',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: StitchColors.primary,
                    ),
                  ),
                  TextSpan(text: explanation),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
