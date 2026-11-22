import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/bodega_skeleton_layout.dart';
import 'package:client/data/models/bodega.dart';
import 'package:client/features/bodega/mobile/bodega_mobile_shell.dart';
import 'package:client/features/bodega/viewmodels/bodega_viewmodel.dart';
import 'package:client/features/bodega/widgets/bodega_navigation.dart';
import 'package:client/features/bodega/widgets/receipt_scanner.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// The Bodega Checker's four screens (decision 25). Phone-first: one column of
// cards, big tap targets, nothing that needs a mouse. The checker READS and
// CONFIRMS; stock moves in through the stocker's Receiving and out at the till.

String _q(double value) => formatQuantity(value);

double? _parseQty(String raw) {
  final text = raw.trim().replaceAll(',', '');
  if (text.isEmpty) return null;
  return double.tryParse(text);
}

final _qtyInput = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    required this.subtitle,
    required this.index,
    required this.onRefresh,
    required this.children,
  });

  final String title;
  final String subtitle;
  final int index;
  final Future<void> Function() onRefresh;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => BodegaSkeletonLayout(
    title: title,
    subtitle: subtitle,
    selectedNavigationIndex: index,
    scrollable: false,
    onNavigationSelected: (i) => navigateBodega(context, i),
    child: RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        physics: const AlwaysScrollableScrollPhysics(),
        children: children,
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppColors.textSecondary),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

Widget _muted(String text) => Text(
  text,
  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
);

// ---------------------------------------------------------------------------
// 1. Pick-ups: scan the receipt, hand the goods over.
// ---------------------------------------------------------------------------

class BodegaPickupsPage extends StatelessWidget {
  const BodegaPickupsPage({
    super.key,
    this.viewmodel,
    this.scanner,
    this.phoneLayout,
  });

  final BodegaViewmodel? viewmodel;

  /// Injected by tests; the phone uses the camera.
  final ReceiptScanner? scanner;

  /// The phone app's layout (header + bottom bar) instead of this page. Null
  /// asks the device: the Android / iPhone app gets it (owner 2026-11-18).
  final bool? phoneLayout;

  @override
  Widget build(BuildContext context) {
    if (phoneLayout ?? runsAsPhoneApp) {
      return BodegaMobileShell(viewmodel: viewmodel, scanner: scanner);
    }
    return ChangeNotifierProvider(
      create: (_) => (viewmodel ?? BodegaViewmodel())..loadPickups(),
      child: _PickupsBody(scanner: scanner),
    );
  }
}

class _PickupsBody extends StatefulWidget {
  const _PickupsBody({this.scanner});
  final ReceiptScanner? scanner;

  @override
  State<_PickupsBody> createState() => _PickupsBodyState();
}

class _PickupsBodyState extends State<_PickupsBody> {
  final _receipt = TextEditingController();

  @override
  void dispose() {
    _receipt.dispose();
    super.dispose();
  }

  bool get _canScan => widget.scanner != null || cameraScanAvailable;

  Future<void> _scan() async {
    final scan = widget.scanner ?? scanReceiptWithCamera;
    final value = await scan(context);
    if (!mounted || value == null) return;
    await _find(value);
  }

  Future<void> _find([String? number]) async {
    if (number != null) _receipt.text = number;
    FocusScope.of(context).unfocus();
    await context.read<BodegaViewmodel>().lookup(_receipt.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<BodegaViewmodel>();
    final claim = state.claim;
    final waiting = state.pendingDeliveries.length;
    return _Page(
      title: 'Pick-ups',
      subtitle: 'Scan the customer\'s receipt and release what was paid for.',
      index: BodegaSkeletonLayout.pickupsIndex,
      onRefresh: state.loadPickups,
      children: [
        if (waiting > 0)
          Card(
            color: AppColors.selected,
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            child: ListTile(
              key: const ValueKey('bodega-deliveries-banner'),
              leading: const Icon(Icons.move_to_inbox_outlined),
              title: Text(
                '$waiting ${waiting == 1 ? 'delivery' : 'deliveries'} to check',
              ),
              subtitle: const Text('Confirm the quantity and any damage'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(AppRoutes.bodegaDeliveries),
            ),
          ),
        if (_canScan)
          SizedBox(
            height: 64,
            child: FilledButton.icon(
              key: const ValueKey('bodega-scan'),
              onPressed: state.isSaving ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 28),
              label: const Text(
                'Scan receipt QR',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('bodega-receipt'),
                controller: _receipt,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _find(),
                decoration: const InputDecoration(
                  labelText: 'Order Slip (OS) or transaction number',
                  hintText: 'OS-…',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filledTonal(
              key: const ValueKey('bodega-find'),
              tooltip: 'Find receipt',
              onPressed: state.isSaving ? null : _find,
              icon: const Icon(Icons.search),
            ),
          ],
        ),
        if (state.actionError != null && claim == null) ...[
          const SizedBox(height: AppSpacing.md),
          ErrorBanner(message: state.actionError!),
        ],
        if (claim != null) ...[
          const SizedBox(height: AppSpacing.md),
          BodegaClaimCard(
            key: ValueKey('claim-${claim.saleId}-${claim.releases.length}'),
            claim: claim,
          ),
        ],
        const _SectionTitle('Waiting for pick-up'),
        if (state.loadError != null)
          ErrorBanner(message: state.loadError!, onRetry: state.loadPickups)
        else if (state.isLoading && state.openClaims.isEmpty)
          const Center(child: CircularProgressIndicator())
        else if (state.openClaims.isEmpty)
          const _Empty('Every paid Bodega item has been collected.'),
        for (final row in state.openClaims)
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ListTile(
              key: ValueKey('open-claim-${row.saleId}'),
              title: Text(
                row.customerName.isEmpty ? 'Walk-in' : row.customerName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${row.orNumber.isEmpty ? row.transactionNo : row.orNumber}\n'
                '${[for (final line in row.lines)
                  if (line.remaining > 0) '${_q(line.remaining)} ${line.unit} ${line.label}'].join(', ')}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _find(row.transactionNo),
            ),
          ),
      ],
    );
  }
}

/// One receipt's claim with the hand-over form, stacked for a phone.
/// One receipt's claim and its release form; reads the nearest
/// [BodegaViewmodel]. Public so the phone's Scan and Pick-ups tabs reuse it.
class BodegaClaimCard extends StatefulWidget {
  const BodegaClaimCard({super.key, required this.claim});
  final BodegaClaim claim;

  @override
  State<BodegaClaimCard> createState() => _ClaimCardState();
}

class _ClaimCardState extends State<BodegaClaimCard> {
  late final Map<String, TextEditingController> _qty = {
    for (final line in widget.claim.lines)
      _key(line): TextEditingController(
        text: line.remaining > 0 ? _q(line.remaining) : '',
      ),
  };
  final _receivedBy = TextEditingController();
  final _plate = TextEditingController();
  String? _formError;

  static String _key(BodegaClaimLine line) =>
      '${line.variantId}.${line.locationId}';

  @override
  void dispose() {
    for (final controller in _qty.values) {
      controller.dispose();
    }
    _receivedBy.dispose();
    _plate.dispose();
    super.dispose();
  }

  Future<void> _release() async {
    final state = context.read<BodegaViewmodel>();
    final lines = <({int variantId, int locationId, double qty})>[];
    for (final line in widget.claim.lines) {
      final raw = _qty[_key(line)]!.text;
      if (raw.trim().isEmpty) continue;
      final qty = _parseQty(raw);
      if (qty == null || qty < 0) {
        setState(() => _formError = '"${raw.trim()}" is not a quantity.');
        return;
      }
      if (qty == 0) continue;
      if (qty > line.remaining + 1e-9) {
        setState(
          () => _formError =
              '${line.label}: only ${_q(line.remaining)} ${line.unit} '
              'is left to collect.',
        );
        return;
      }
      lines.add((
        variantId: line.variantId,
        locationId: line.locationId,
        qty: qty,
      ));
    }
    if (lines.isEmpty) {
      setState(() => _formError = 'Enter how much is being loaded now.');
      return;
    }
    if (_receivedBy.text.trim().isEmpty) {
      setState(() => _formError = 'Write who received the goods.');
      return;
    }
    setState(() => _formError = null);
    final recorded = await state.release(
      BodegaReleaseRequest(
        receipt: widget.claim.transactionNo,
        receivedBy: _receivedBy.text.trim(),
        plateNo: _plate.text.trim(),
        lines: lines,
      ),
    );
    if (!mounted || recorded == null) return;
    final notice = state.outboxNotice;
    final message = (recorded.number == 'QUEUED-OFFLINE' && notice != null)
        ? notice
        : '${recorded.number} recorded: ${recorded.summary}.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<BodegaViewmodel>();
    final claim = widget.claim;
    final error = _formError ?? state.actionError;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    claim.customerName.isEmpty ? 'Walk-in' : claim.customerName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: state.closeClaim,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            _muted(
              [
                if (claim.orNumber.isNotEmpty) claim.orNumber,
                claim.transactionNo,
                if (claim.soldAt != null) formatDateTime(claim.soldAt!),
              ].join(' · '),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: claim.isOpen
                  ? const StatusBadge(
                      label: 'Waiting for pick-up',
                      tone: StatusTone.warning,
                    )
                  : const StatusBadge(
                      label: 'Fully released',
                      tone: StatusTone.success,
                    ),
            ),
            const Divider(height: AppSpacing.lg),
            for (final line in claim.lines) ...[
              Text(
                line.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              _muted(
                'Paid ${_q(line.sold)} · released ${_q(line.released)} · '
                'left ${_q(line.remaining)} ${line.unit}',
              ),
              if (line.remaining > 0) ...[
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  key: ValueKey('release-qty-${_key(line)}'),
                  controller: _qty[_key(line)],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: _qtyInput,
                  decoration: InputDecoration(
                    labelText: 'Loading now',
                    suffixText: line.unit,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
            ],
            if (claim.isOpen) ...[
              TextField(
                key: const ValueKey('release-received-by'),
                controller: _receivedBy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Received by'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey('release-plate'),
                controller: _plate,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Truck plate (optional)',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: AppSpacing.md),
                ErrorBanner(message: error),
              ],
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  key: const ValueKey('bodega-release'),
                  onPressed: state.isSaving ? null : _release,
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Release goods'),
                ),
              ),
            ],
            if (claim.releases.isNotEmpty) ...[
              const Divider(height: AppSpacing.lg),
              Text(
                'Already released',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final release in claim.releases)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: _muted(
                    '${release.number} · ${release.summary} · to '
                    '${release.receivedBy}'
                    '${release.plateNo.isEmpty ? '' : ' (${release.plateNo})'}',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Deliveries to check: the stocker received it; the checker confirms it.
// ---------------------------------------------------------------------------

class BodegaDeliveriesPage extends StatelessWidget {
  const BodegaDeliveriesPage({super.key, this.viewmodel});
  final BodegaViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => (viewmodel ?? BodegaViewmodel())..loadDeliveries(),
    child: const _DeliveriesBody(),
  );
}

class _DeliveriesBody extends StatelessWidget {
  const _DeliveriesBody();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<BodegaViewmodel>();
    final pending = state.pendingDeliveries;
    final checked = state.checkedDeliveries.take(10).toList();
    return _Page(
      title: 'Deliveries to check',
      subtitle:
          'Count what arrived and mark damaged pieces. Stock is added '
          'only after you confirm.',
      index: BodegaSkeletonLayout.deliveriesIndex,
      onRefresh: state.loadDeliveries,
      children: [
        if (state.loadError != null)
          ErrorBanner(message: state.loadError!, onRetry: state.loadDeliveries)
        else if (state.isLoading && state.deliveries.isEmpty)
          const Center(child: CircularProgressIndicator())
        else if (pending.isEmpty)
          const _Empty('No delivery is waiting for you.'),
        for (final delivery in pending)
          _DeliveryCheckCard(
            key: ValueKey('delivery-${delivery.id}'),
            delivery: delivery,
          ),
        if (checked.isNotEmpty) const _SectionTitle('Recently checked'),
        for (final delivery in checked) _CheckedDeliveryTile(delivery),
      ],
    );
  }
}

class _DeliveryCheckCard extends StatefulWidget {
  const _DeliveryCheckCard({super.key, required this.delivery});
  final BodegaDelivery delivery;

  @override
  State<_DeliveryCheckCard> createState() => _DeliveryCheckCardState();
}

class _DeliveryCheckCardState extends State<_DeliveryCheckCard> {
  late final Map<int, TextEditingController> _good = {
    for (final line in widget.delivery.lines)
      line.id: TextEditingController(text: _q(line.deliveredQty)),
  };
  late final Map<int, TextEditingController> _damaged = {
    for (final line in widget.delivery.lines)
      line.id: TextEditingController(text: '0'),
  };
  late final Map<int, TextEditingController> _remarks = {
    for (final line in widget.delivery.lines) line.id: TextEditingController(),
  };
  String? _formError;

  @override
  void dispose() {
    for (final map in [_good, _damaged, _remarks]) {
      for (final controller in map.values) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  double? _missing(BodegaDeliveryLine line) {
    final good = _parseQty(_good[line.id]!.text);
    final damaged = _parseQty(_damaged[line.id]!.text);
    if (good == null || damaged == null) return null;
    return line.deliveredQty - good - damaged;
  }

  Future<void> _confirm() async {
    final lines =
        <({int lineId, double good, double damaged, String remarks})>[];
    for (final line in widget.delivery.lines) {
      final good = _parseQty(_good[line.id]!.text);
      final damaged = _parseQty(_damaged[line.id]!.text);
      if (good == null || damaged == null || good < 0 || damaged < 0) {
        setState(
          () =>
              _formError = '${line.label}: enter the good and damaged counts.',
        );
        return;
      }
      if (line.isWhole &&
          (good != good.roundToDouble() ||
              damaged != damaged.roundToDouble())) {
        setState(
          () => _formError = '${line.label} is counted in whole ${line.unit}.',
        );
        return;
      }
      if (good + damaged > line.deliveredQty + 1e-9) {
        setState(
          () => _formError =
              '${line.label}: ${_q(good)} good + ${_q(damaged)} damaged is more '
              'than the ${_q(line.deliveredQty)} ${line.unit} delivered.',
        );
        return;
      }
      lines.add((
        lineId: line.id,
        good: good,
        damaged: damaged,
        remarks: _remarks[line.id]!.text.trim(),
      ));
    }
    setState(() => _formError = null);
    final state = context.read<BodegaViewmodel>();
    final checked = await state.confirmDelivery(
      widget.delivery.id,
      BodegaDeliveryConfirmation(lines: lines),
    );
    if (!mounted || checked == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${checked.number} confirmed. '
          '${checked.damagedTotal > 0 ? '${_q(checked.damagedTotal)} damaged written off.' : 'No damage.'}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<BodegaViewmodel>();
    final delivery = widget.delivery;
    final error = _formError ?? state.actionError;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              delivery.supplierName.isEmpty
                  ? delivery.number
                  : delivery.supplierName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            _muted(
              '${delivery.number} · received by ${delivery.receivedByName}'
              '${delivery.createdAt == null ? '' : ' · ${formatDateTime(delivery.createdAt!)}'}',
            ),
            const Divider(height: AppSpacing.lg),
            for (final line in delivery.lines) ...[
              Text(
                line.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              _muted('Delivered: ${_q(line.deliveredQty)} ${line.unit}'),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: ValueKey('delivery-good-${line.id}'),
                      controller: _good[line.id],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: _qtyInput,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Good',
                        suffixText: line.unit,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      key: ValueKey('delivery-damaged-${line.id}'),
                      controller: _damaged[line.id],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: _qtyInput,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Damaged',
                        suffixText: line.unit,
                      ),
                    ),
                  ),
                ],
              ),
              if ((_missing(line) ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    '${_q(_missing(line)!)} ${line.unit} missing — will be '
                    'written off',
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _remarks[line.id],
                decoration: const InputDecoration(
                  labelText: 'Remarks (optional)',
                  hintText: 'e.g. cracked at the bottom row',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (error != null) ...[
              ErrorBanner(message: error),
              const SizedBox(height: AppSpacing.md),
            ],
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: ValueKey('delivery-confirm-${delivery.id}'),
                onPressed: state.isSaving ? null : _confirm,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Confirm delivery'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckedDeliveryTile extends StatelessWidget {
  const _CheckedDeliveryTile(this.delivery);
  final BodegaDelivery delivery;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: ListTile(
      title: Text(
        '${delivery.number} · '
        '${delivery.supplierName.isEmpty ? delivery.locationName : delivery.supplierName}',
      ),
      subtitle: Text(
        [
          for (final line in delivery.lines)
            '${line.label}: ${_q(line.goodQty ?? 0)} good'
                '${(line.damagedQty ?? 0) > 0 ? ', ${_q(line.damagedQty!)} damaged' : ''}'
                '${(line.missingQty ?? 0) > 0 ? ', ${_q(line.missingQty!)} missing' : ''}',
          'Checked by ${delivery.checkedByName}'
              '${delivery.checkedAt == null ? '' : ' · ${formatDateTime(delivery.checkedAt!)}'}',
        ].join('\n'),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// 3. Bodega stock: read only.
// ---------------------------------------------------------------------------

class BodegaStockPage extends StatelessWidget {
  const BodegaStockPage({super.key, this.viewmodel});
  final BodegaViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => (viewmodel ?? BodegaViewmodel())..loadStock(),
    child: const _StockBody(),
  );
}

class _StockBody extends StatefulWidget {
  const _StockBody();

  @override
  State<_StockBody> createState() => _StockBodyState();
}

class _StockBodyState extends State<_StockBody> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<BodegaViewmodel>();
    final needle = _query.trim().toLowerCase();
    final rows = [
      for (final row in state.stock)
        if (needle.isEmpty ||
            row.label.toLowerCase().contains(needle) ||
            row.category.toLowerCase().contains(needle))
          row,
    ];
    return _Page(
      title: 'Bodega stock',
      subtitle: 'What should be on site. Read only: the stocker moves stock.',
      index: BodegaSkeletonLayout.stockIndex,
      onRefresh: state.loadStock,
      children: [
        TextField(
          onChanged: (value) => setState(() => _query = value),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Find a product',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (state.loadError != null)
          ErrorBanner(message: state.loadError!, onRetry: state.loadStock)
        else if (state.isLoading && state.stock.isEmpty)
          const Center(child: CircularProgressIndicator())
        else if (rows.isEmpty)
          _Empty(
            needle.isEmpty
                ? 'Nothing is kept in the Bodega yet.'
                : 'No Bodega product matches that search.',
          ),
        for (final row in rows)
          Card(
            key: ValueKey('bodega-stock.${row.variantId}.${row.locationId}'),
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (row.isLow)
                        const StatusBadge(
                          label: 'Low',
                          tone: StatusTone.warning,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Should be on site: ${_q(row.physical)} ${row.unit}',
                    style: const TextStyle(fontSize: 16),
                  ),
                  _muted(
                    'Can still sell ${_q(row.onHand)} · waiting pick-up '
                    '${_q(row.unreleased)}'
                    '${row.awaitingDispatch > 0 ? ' · awaiting dispatch ${_q(row.awaitingDispatch)}' : ''}'
                    '${row.forChecking > 0 ? ' · for checking ${_q(row.forChecking)}' : ''}'
                    ' ${row.unit}',
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 4. History: what left and what came in.
// ---------------------------------------------------------------------------

class BodegaHistoryPage extends StatelessWidget {
  const BodegaHistoryPage({super.key, this.viewmodel});
  final BodegaViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => (viewmodel ?? BodegaViewmodel())..loadHistory(),
    child: const _HistoryBody(),
  );
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<BodegaViewmodel>();
    return _Page(
      title: 'History',
      subtitle: 'Every release and every checked delivery.',
      index: BodegaSkeletonLayout.historyIndex,
      onRefresh: state.loadHistory,
      children: [
        if (state.loadError != null)
          ErrorBanner(message: state.loadError!, onRetry: state.loadHistory),
        const _SectionTitle('Released'),
        if (!state.isLoading && state.releases.isEmpty)
          const _Empty('Nothing has been released yet.'),
        for (final release in state.releases)
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ListTile(
              key: ValueKey('bodega-release.${release.id}'),
              title: Text('${release.number} · ${release.summary}'),
              subtitle: Text(
                'Receipt ${release.transactionNo} · to ${release.receivedBy}'
                '${release.plateNo.isEmpty ? '' : ' (${release.plateNo})'}\n'
                'Checked by ${release.checkerName}'
                '${release.createdAt == null ? '' : ' · ${formatDateTime(release.createdAt!)}'}',
              ),
              isThreeLine: true,
            ),
          ),
        const _SectionTitle('Deliveries checked'),
        if (!state.isLoading && state.checkedDeliveries.isEmpty)
          const _Empty('No delivery has been checked yet.'),
        for (final delivery in state.checkedDeliveries)
          _CheckedDeliveryTile(delivery),
      ],
    );
  }
}
