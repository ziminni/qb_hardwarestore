import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/bodega.dart';
import 'package:client/features/bodega/mobile/bodega_mobile_shell.dart';
import 'package:client/features/bodega/mobile/bodega_mobile_widgets.dart';
import 'package:client/features/bodega/viewmodels/bodega_viewmodel.dart';
import 'package:client/features/bodega/widgets/receipt_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Pick-ups (owner 2026-11-19): no list of pending receipts. A pending pick-up
/// opens only by scanning its QR (or typing its OR number in the scanner when
/// the code is damaged); this tab types an OR number to find COMPLETED ones.
class BodegaPickupsTab extends StatefulWidget {
  const BodegaPickupsTab({super.key, required this.onRefresh, this.scanner});

  final Future<void> Function() onRefresh;
  final ReceiptScanner? scanner;

  @override
  State<BodegaPickupsTab> createState() => _BodegaPickupsTabState();
}

class _BodegaPickupsTabState extends State<BodegaPickupsTab> {
  final _number = TextEditingController();
  bool _showAccomplished = false;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _search(BodegaViewmodel viewmodel) async {
    FocusScope.of(context).unfocus();
    await viewmodel.searchClaims(_number.text);
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<BodegaViewmodel>();
    final searched = viewmodel.searchedFor;
    final found = sortedClaims(viewmodel.foundClaims);
    final waitingList = searched.isNotEmpty
        ? [
            for (final claim in found)
              if (claim.isOpen) claim,
          ]
        : sortedClaims(viewmodel.openClaims);
    final completedList = searched.isNotEmpty
        ? [
            for (final claim in found)
              if (!claim.isOpen) claim,
          ]
        : sortedClaims(viewmodel.completedClaims);

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        key: const ValueKey('bodega-pickups'),
        padding: const EdgeInsets.only(top: 16, bottom: 24),
        children: [
          MobileCard(
            child: InkWell(
              key: const ValueKey('pickups-scan'),
              onTap: () => scanAndOpenClaim(context, viewmodel, widget.scanner),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: AppColors.brandGold,
                      child: Icon(
                        Icons.qr_code_scanner,
                        color: AppColors.brandBlack,
                      ),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Scan & release goods',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Scan the customer receipt QR (or enter OR number) '
                            'to hand over Bodega items.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<bool>(
              key: const ValueKey('pickups-status-toggle'),
              segments: [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Waiting (${viewmodel.openClaims.length})'),
                  icon: const Icon(Icons.hourglass_top, size: 16),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text(
                    'Accomplished (${viewmodel.completedClaims.length})',
                  ),
                  icon: const Icon(Icons.task_alt, size: 16),
                ),
              ],
              selected: {_showAccomplished},
              onSelectionChanged: (values) =>
                  setState(() => _showAccomplished = values.first),
            ),
          ),
          const SizedBox(height: 10),
          MobileCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('or-number'),
                    controller: _number,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(viewmodel),
                    decoration: const InputDecoration(
                      hintText: 'Search by OR number or customer',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const ValueKey('or-search'),
                  tooltip: 'Search',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.brandBlack,
                    foregroundColor: AppColors.brandWhite,
                  ),
                  onPressed: viewmodel.isSearching
                      ? null
                      : () => _search(viewmodel),
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (viewmodel.isSearching)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (viewmodel.searchError case final error?)
            MobileCard(child: EmptyNote(error))
          else if (!_showAccomplished) ...[
            if (waitingList.isEmpty)
              MobileCard(
                child: EmptyNote(
                  searched.isEmpty
                      ? 'No customer pick-ups waiting at the Bodega right now.'
                      : 'No waiting pick-up matches "$searched".',
                ),
              )
            else
              for (final claim in waitingList)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _WaitingPickupTile(
                    claim: claim,
                    onTap: () =>
                        scanAndOpenClaim(context, viewmodel, widget.scanner),
                  ),
                ),
          ] else ...[
            if (completedList.isEmpty)
              MobileCard(
                child: EmptyNote(
                  searched.isEmpty
                      ? 'No accomplished pick-ups recorded yet.'
                      : 'No accomplished pick-up matches "$searched".',
                ),
              )
            else
              for (final claim in completedList)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CompletedTile(claim: claim),
                ),
          ],
        ],
      ),
    );
  }
}

class _WaitingPickupTile extends StatelessWidget {
  const _WaitingPickupTile({required this.claim, required this.onTap});

  final BodegaClaim claim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final releasedAny = claim.lines.any((l) => l.released > 0);
    final statusLabel = releasedAny
        ? 'Partially picked up · ${formatQuantity(claim.remainingTotal)} left'
        : 'Waiting for pickup · ${formatQuantity(claim.remainingTotal)} item(s)';
    return MobileCard(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: releasedAny
              ? AppColors.info.withValues(alpha: 0.14)
              : AppColors.warningTint,
          child: Icon(
            releasedAny ? Icons.timelapse : Icons.hourglass_top,
            color: releasedAny ? AppColors.info : AppColors.warningText,
          ),
        ),
        title: Text(
          _receiptNumber(claim),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            claim.customerName.isEmpty ? 'Walk-in' : claim.customerName,
            statusLabel,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.qr_code_scanner),
      ),
    );
  }
}

String _receiptNumber(BodegaClaim claim) =>
    claim.orNumber.isNotEmpty ? claim.orNumber : claim.transactionNo;

int _newestFirst(BodegaRelease a, BodegaRelease b) =>
    (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));

class _CompletedTile extends StatelessWidget {
  const _CompletedTile({required this.claim});
  final BodegaClaim claim;

  @override
  Widget build(BuildContext context) {
    final last = [...claim.releases]..sort(_newestFirst);
    return MobileCard(
      child: ListTile(
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => CompletedPickupScreen(claim: claim),
          ),
        ),
        leading: const CircleAvatar(
          backgroundColor: AppColors.successTint,
          child: Icon(Icons.task_alt, color: AppColors.successText),
        ),
        title: Text(
          _receiptNumber(claim),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            claim.customerName.isEmpty ? 'Walk-in' : claim.customerName,
            if (last.isNotEmpty && last.first.createdAt != null)
              'Picked up ${formatShortDate(last.first.createdAt!)}',
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

/// One completed pick-up: what was bought, and every hand-over of it.
class CompletedPickupScreen extends StatelessWidget {
  const CompletedPickupScreen({super.key, required this.claim});
  final BodegaClaim claim;

  @override
  Widget build(BuildContext context) {
    final releases = [...claim.releases]..sort(_newestFirst);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            BodegaHeader(
              title: _receiptNumber(claim),
              name: '',
              subtitle: '',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 16, bottom: 24),
                children: [
                  MobileCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          claim.customerName.isEmpty
                              ? 'Walk-in'
                              : claim.customerName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          [
                            claim.transactionNo,
                            if (claim.soldAt != null)
                              'Sold ${formatDate(claim.soldAt!)}',
                          ].join(' · '),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const Divider(height: 20),
                        for (final line in claim.lines)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Expanded(child: Text(line.label)),
                                Text(
                                  '${formatQuantity(line.released)} '
                                  '${line.unit}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SectionHeader(title: 'Handed over'),
                  if (releases.isEmpty)
                    const MobileCard(child: EmptyNote('No hand-over recorded.'))
                  else
                    for (final release in releases)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: MobileCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      release.number,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
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
                              for (final line in release.lines)
                                Row(
                                  children: [
                                    Expanded(child: Text(line.label)),
                                    Text(
                                      '${formatQuantity(line.qty)} '
                                      '${line.unit}',
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 6),
                              Text(
                                [
                                  'Received by ${release.receivedBy}',
                                  if (release.plateNo.isNotEmpty)
                                    'Plate ${release.plateNo}',
                                  if (release.checkerName.isNotEmpty)
                                    'by ${release.checkerName}',
                                ].join(' · '),
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
