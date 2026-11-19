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
    final completed = [
      for (final claim in found)
        if (!claim.isOpen) claim,
    ];
    final stillWaiting = [
      for (final claim in found)
        if (claim.isOpen) claim,
    ];
    return ListView(
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
                          'Release goods',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Scan the receipt QR. Damaged? Tap the arrow in the '
                          'scanner and type the OR number.',
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
        const SectionHeader(title: 'Completed pick-ups'),
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
                    hintText: 'Type the OR number',
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
        else if (searched.isEmpty)
          const MobileCard(
            child: EmptyNote(
              'Type an OR number to find a pick-up that was already handed '
              'over.',
            ),
          )
        else ...[
          for (final claim in completed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CompletedTile(claim: claim),
            ),
          for (final claim in stillWaiting)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: MobileCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(
                      Icons.hourglass_top,
                      color: AppColors.warningText,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${_receiptNumber(claim)} still has goods waiting. '
                        'Scan its QR to release them.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (found.isEmpty)
            MobileCard(
              child: EmptyNote('No pick-up has the OR number "$searched".'),
            ),
        ],
      ],
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
