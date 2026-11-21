import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/bodega.dart';
import 'package:client/features/bodega/mobile/arrival_report.dart';
import 'package:client/features/bodega/mobile/bodega_mobile_widgets.dart';
import 'package:client/features/bodega/viewmodels/bodega_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Arrivals: supplier deliveries the stocker sent to the Bodega. The ones to
/// check come first; tapping one opens its report.
class BodegaArrivalsTab extends StatelessWidget {
  const BodegaArrivalsTab({super.key, required this.onRefresh, this.takePhoto});

  final Future<void> Function() onRefresh;
  final PhotoTaker? takePhoto;

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<BodegaViewmodel>();
    final pending = viewmodel.pendingDeliveries;
    final checked = viewmodel.checkedDeliveries.take(10).toList();
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const ValueKey('bodega-arrivals'),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SectionHeader(title: 'To check (${pending.length})'),
          if (pending.isEmpty)
            const MobileCard(
              child: EmptyNote('No arrivals waiting. You are all caught up.'),
            )
          else
            for (final delivery in pending)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ArrivalTile(delivery: delivery, takePhoto: takePhoto),
              ),
          if (checked.isNotEmpty) ...[
            const SectionHeader(title: 'Recently checked'),
            for (final delivery in checked)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ArrivalTile(delivery: delivery, takePhoto: takePhoto),
              ),
          ],
        ],
      ),
    );
  }
}

/// One delivery: number, supplier, item count, and whether it waits.
class ArrivalTile extends StatelessWidget {
  const ArrivalTile({super.key, required this.delivery, this.takePhoto});

  final BodegaDelivery delivery;
  final PhotoTaker? takePhoto;

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.read<BodegaViewmodel>();
    final items = delivery.lines.length;
    return MobileCard(
      child: ListTile(
        key: ValueKey('arrival-${delivery.id}'),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider<BodegaViewmodel>.value(
              value: viewmodel,
              child: ArrivalReportScreen(
                deliveryId: delivery.id,
                takePhoto: takePhoto ?? takePhotoWithCamera,
              ),
            ),
          ),
        ),
        leading: CircleAvatar(
          backgroundColor: delivery.isPending
              ? AppColors.warningTint
              : AppColors.successTint,
          child: Icon(
            delivery.isPending ? Icons.fiber_new_outlined : Icons.task_alt,
            color: delivery.isPending
                ? AppColors.warningText
                : AppColors.successText,
          ),
        ),
        title: Text(
          delivery.number,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (delivery.supplierName.isNotEmpty) delivery.supplierName,
            '$items item${items == 1 ? '' : 's'}',
            if (delivery.createdAt != null) formatDate(delivery.createdAt!),
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: delivery.isPending
            ? const Text(
                'Check',
                style: TextStyle(
                  color: AppColors.brandGoldText,
                  fontWeight: FontWeight.w700,
                ),
              )
            : const Icon(Icons.chevron_right),
      ),
    );
  }
}

/// One delivery's report: per item a photo, Complete / Damaged / Missing, an
/// optional quantity and a note; then Submit. A checked delivery opens
/// read-only, with the checker's photos and counts.
class ArrivalReportScreen extends StatefulWidget {
  const ArrivalReportScreen({
    super.key,
    required this.deliveryId,
    required this.takePhoto,
  });

  final int deliveryId;
  final PhotoTaker takePhoto;

  @override
  State<ArrivalReportScreen> createState() => _ArrivalReportScreenState();
}

class _ArrivalReportScreenState extends State<ArrivalReportScreen> {
  ArrivalReport? _report;
  String? _error;
  String? _progress;

  BodegaDelivery? _delivery(BodegaViewmodel viewmodel) {
    for (final delivery in viewmodel.deliveries) {
      if (delivery.id == widget.deliveryId) return delivery;
    }
    return null;
  }

  Future<void> _photo(ItemReport item) async {
    final taken = await widget.takePhoto();
    if (taken == null || !mounted) return;
    setState(() {
      item.photoBytes = taken.bytes;
      _error = null;
    });
  }

  Future<void> _submit(BodegaViewmodel viewmodel) async {
    final report = _report!;
    String? problem;
    final confirmation = report.confirmation((message) => problem = message);
    if (confirmation == null) {
      setState(() => _error = problem);
      return;
    }
    setState(() => _error = null);
    // Photos first, while the delivery still waits: the server refuses a
    // photo once the verdict is in.
    final toUpload = [
      for (final item in report.items)
        if (item.photoBytes != null) item,
    ];
    for (var i = 0; i < toUpload.length; i++) {
      final item = toUpload[i];
      setState(
        () => _progress = 'Uploading photo ${i + 1} of ${toUpload.length}…',
      );
      final ok = await viewmodel.uploadLinePhoto(
        report.deliveryId,
        item.line.id,
        item.photoBytes!,
        filename: 'line-${item.line.id}.jpg',
      );
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _progress = null;
          _error = viewmodel.actionError;
        });
        return;
      }
      item.photoBytes = null;
    }
    setState(() => _progress = 'Saving the report…');
    final checked = await viewmodel.confirmDelivery(
      report.deliveryId,
      confirmation,
    );
    if (!mounted) return;
    setState(() => _progress = null);
    if (checked == null) {
      setState(() => _error = viewmodel.actionError);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${checked.number} checked into the Bodega.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<BodegaViewmodel>();
    final delivery = _delivery(viewmodel);
    if (delivery != null && delivery.isPending) {
      _report ??= ArrivalReport(delivery);
    }
    final busy = _progress != null || viewmodel.isSaving;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.brandBlack,
        foregroundColor: AppColors.brandWhite,
        title: Text(delivery?.number ?? 'Arrival'),
      ),
      body: delivery == null
          ? const EmptyNote('This delivery is no longer listed.')
          : ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 24),
              children: [
                MobileCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        delivery.supplierName.isEmpty
                            ? 'Supplier delivery'
                            : delivery.supplierName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          'To ${delivery.locationName}',
                          if (delivery.receivedByName.isNotEmpty)
                            'received by ${delivery.receivedByName}',
                          if (delivery.createdAt != null)
                            formatDateTime(delivery.createdAt!),
                        ].join(' · '),
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      if (!delivery.isPending) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Checked by ${delivery.checkedByName.isEmpty ? 'the checker' : delivery.checkedByName}'
                          '${delivery.checkedAt == null ? '' : ' · ${formatDateTime(delivery.checkedAt!)}'}',
                          style: const TextStyle(color: AppColors.successText),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                if (_report case final report? when delivery.isPending)
                  for (final item in report.items)
                    _ItemCard(
                      item: item,
                      enabled: !busy,
                      onPhoto: () => _photo(item),
                      onChanged: () => setState(() => _error = null),
                    )
                else
                  for (final line in delivery.lines) _CheckedLine(line: line),
              ],
            ),
      bottomNavigationBar: delivery == null || !delivery.isPending
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error case final error?)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          error,
                          key: const ValueKey('report-error'),
                          style: const TextStyle(color: AppColors.errorText),
                        ),
                      ),
                    if (_progress case final progress?)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(progress),
                      ),
                    FilledButton.icon(
                      key: const ValueKey('submit-report'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandBlack,
                        foregroundColor: AppColors.brandWhite,
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: busy ? null : () => _submit(viewmodel),
                      icon: const Icon(Icons.task_alt),
                      label: const Text('Submit report'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _ItemCard extends StatefulWidget {
  const _ItemCard({
    required this.item,
    required this.enabled,
    required this.onPhoto,
    required this.onChanged,
  });

  final ItemReport item;
  final bool enabled;
  final VoidCallback onPhoto;
  final VoidCallback onChanged;

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  late final _qty = TextEditingController(text: widget.item.qtyText);
  late final _remarks = TextEditingController(text: widget.item.remarks);

  @override
  void dispose() {
    _qty.dispose();
    _remarks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final line = item.line;
    final delivered = '${formatQuantity(line.deliveredQty)} ${line.unit}';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: MobileCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          key: ValueKey('item-${line.id}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    line.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  delivered,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _PhotoBox(
              key: ValueKey('photo-${line.id}'),
              bytes: item.photoBytes,
              url: line.photoUrl,
              onTap: widget.enabled ? widget.onPhoto : null,
            ),
            const SizedBox(height: 10),
            SegmentedButton<ItemCondition>(
              key: ValueKey('condition-${line.id}'),
              showSelectedIcon: false,
              segments: [
                for (final condition in ItemCondition.values)
                  ButtonSegment(value: condition, label: Text(condition.label)),
              ],
              selected: {item.condition},
              onSelectionChanged: widget.enabled
                  ? (picked) {
                      setState(() => item.condition = picked.single);
                      widget.onChanged();
                    }
                  : null,
            ),
            if (item.condition != ItemCondition.complete) ...[
              const SizedBox(height: 10),
              TextField(
                key: ValueKey('qty-${line.id}'),
                controller: _qty,
                enabled: widget.enabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onChanged: (value) {
                  item.qtyText = value;
                  widget.onChanged();
                },
                decoration: InputDecoration(
                  labelText:
                      'How many ${item.condition.label.toLowerCase()}? (optional)',
                  helperText: 'Leave empty for all $delivered.',
                  suffixText: line.unit,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: ValueKey('remarks-${line.id}'),
                controller: _remarks,
                enabled: widget.enabled,
                maxLength: 255,
                onChanged: (value) => item.remarks = value,
                decoration: const InputDecoration(
                  labelText: 'What happened? (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The item's photo: a tap-to-take box, then the picture with "Retake".
class _PhotoBox extends StatelessWidget {
  const _PhotoBox({super.key, this.bytes, this.url = '', this.onTap});

  final List<int>? bytes;
  final String url;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final has = bytes != null || url.isNotEmpty;
    final Widget content;
    if (bytes case final local?) {
      content = Image.memory(
        Uint8List.fromList(local),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            const Center(child: Icon(Icons.broken_image_outlined)),
      );
    } else if (url.isNotEmpty) {
      content = Image.network(
        mediaUrl(url),
        headers: mediaHeaders(),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            const Center(child: Icon(Icons.broken_image_outlined)),
      );
    } else {
      content = const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_camera_outlined,
            size: 32,
            color: AppColors.brandGoldText,
          ),
          SizedBox(height: 6),
          Text(
            'Take a photo of this item',
            style: TextStyle(
              color: AppColors.brandGoldText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 150,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: has ? AppColors.border : AppColors.brandGold,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (has && onTap != null)
              const Positioned(
                right: 8,
                bottom: 8,
                child: Chip(
                  avatar: Icon(Icons.refresh, size: 16),
                  label: Text('Retake'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A checked line: the counts the checker gave and their photo.
class _CheckedLine extends StatelessWidget {
  const _CheckedLine({required this.line});
  final BodegaDeliveryLine line;

  @override
  Widget build(BuildContext context) {
    String q(double? value) => '${formatQuantity(value ?? 0)} ${line.unit}';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: MobileCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              line.label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Good ${q(line.goodQty)} · Damaged ${q(line.damagedQty)}'
              ' · Missing ${q(line.missingQty)}',
            ),
            if (line.remarks.isNotEmpty)
              Text(
                line.remarks,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            if (line.photoUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              _PhotoBox(url: line.photoUrl),
            ],
          ],
        ),
      ),
    );
  }
}
