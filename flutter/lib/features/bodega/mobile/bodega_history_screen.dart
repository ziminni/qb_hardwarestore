import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/bodega.dart';
import 'package:client/features/bodega/mobile/bodega_arrivals_tab.dart';
import 'package:client/features/bodega/mobile/bodega_mobile_shell.dart';
import 'package:client/features/bodega/mobile/bodega_mobile_widgets.dart';
import 'package:client/features/bodega/viewmodels/bodega_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// The phone's Release history (owner 2026-11-19): the brand header with a
/// back arrow, then Releases (goods handed over) and Deliveries checked,
/// newest first. Read only.
class BodegaHistoryScreen extends StatelessWidget {
  const BodegaHistoryScreen({super.key, this.viewmodel});

  final BodegaViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => (viewmodel ?? BodegaViewmodel())..loadHistory(),
    child: const _HistoryBody(),
  );
}

class _HistoryBody extends StatefulWidget {
  const _HistoryBody();

  @override
  State<_HistoryBody> createState() => _HistoryBodyState();
}

class _HistoryBodyState extends State<_HistoryBody> {
  bool _deliveries = false;

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<BodegaViewmodel>();
    int newestFirst(DateTime? a, DateTime? b) =>
        (b ?? DateTime(0)).compareTo(a ?? DateTime(0));
    final releases = [...viewmodel.releases]
      ..sort((a, b) => newestFirst(a.createdAt, b.createdAt));
    final checked = [...viewmodel.checkedDeliveries]
      ..sort((a, b) => newestFirst(a.checkedAt, b.checkedAt));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            BodegaHeader(
              title: 'Release history',
              name: '',
              subtitle: '',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text('Releases (${releases.length})'),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Deliveries (${checked.length})'),
                    ),
                  ],
                  selected: {_deliveries},
                  onSelectionChanged: (picked) =>
                      setState(() => _deliveries = picked.single),
                ),
              ),
            ),
            if (viewmodel.loadError case final error?)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  error,
                  style: const TextStyle(color: AppColors.errorText),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: viewmodel.loadHistory,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  children: [
                    if (viewmodel.isLoading &&
                        releases.isEmpty &&
                        checked.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (!_deliveries && releases.isEmpty)
                      const MobileCard(
                        child: EmptyNote('No goods handed over yet.'),
                      )
                    else if (_deliveries && checked.isEmpty)
                      const MobileCard(
                        child: EmptyNote('No delivery checked yet.'),
                      )
                    else if (_deliveries)
                      for (final delivery in checked)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _CheckedCard(delivery: delivery),
                        )
                    else
                      for (final release in releases)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ReleaseCard(release: release),
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One hand-over: the slip, the receipt and customer, who took it, and what.
class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({required this.release});
  final BodegaRelease release;

  @override
  Widget build(BuildContext context) {
    return MobileCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.local_shipping_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  release.number,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (release.createdAt case final at?)
                Text(
                  formatDateTime(at),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              release.transactionNo,
              release.customerName.isEmpty ? 'Walk-in' : release.customerName,
            ].join(' · '),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const Divider(height: 18),
          for (final line in release.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Expanded(child: Text(line.label)),
                  Text(
                    '${formatQuantity(line.qty)} ${line.unit}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text(
            [
              'Received by ${release.receivedBy}',
              if (release.plateNo.isNotEmpty) 'Plate ${release.plateNo}',
            ].join(' · '),
            style: const TextStyle(fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// One checked delivery: its number, supplier, totals; taps open the report.
class _CheckedCard extends StatelessWidget {
  const _CheckedCard({required this.delivery});
  final BodegaDelivery delivery;

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.read<BodegaViewmodel>();
    final damaged = delivery.damagedTotal;
    final items = delivery.lines.length;
    return MobileCard(
      child: ListTile(
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider<BodegaViewmodel>.value(
              value: viewmodel,
              child: ArrivalReportScreen(
                deliveryId: delivery.id,
                takePhoto: takePhotoWithCamera,
              ),
            ),
          ),
        ),
        leading: const CircleAvatar(
          backgroundColor: AppColors.successTint,
          child: Icon(Icons.task_alt, color: AppColors.successText),
        ),
        title: Text(
          delivery.number,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            if (delivery.supplierName.isNotEmpty) delivery.supplierName,
            '$items item${items == 1 ? '' : 's'}',
            if (damaged > 0) '${formatQuantity(damaged)} damaged',
            if (delivery.checkedAt != null)
              formatShortDate(delivery.checkedAt!),
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
