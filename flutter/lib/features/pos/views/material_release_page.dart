import 'dart:async';

import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/viewmodels/material_release_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/features/pos/widgets/release_line_row.dart';
import 'package:client/features/pos/widgets/release_summary_bar.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/features/pos/widgets/pos_receipt_dialog.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The material release counter — Phase 5's only **irreversible** screen (decision 09).
///
/// A store clerk takes a printed token from a project (CPMS raises the request and mints
/// the token; the POS only fulfils it), checks it, and releases the materials. The
/// release FIFO-deducts real stock, writes a real `SalesTransaction`, and **always** leaves a
/// receivable because a construction firm pays later — so the receipt is shown, not just the success.
///
/// Decision 05: the shelf can be short, and a short shelf no longer refuses the whole
/// release. Each line says what can leave the store now, and anything that cannot stays
/// open on the same token, which is why the confirm press can be absent entirely.
///
/// One screen (2026-11-27 design, layout B): the waiting requests and the token field on the
/// left, the chosen request on the right with a Give now amount per line, then the receipt in
/// the same place. [viewmodel] is injectable so a test can observe what the screen sends;
/// production passes nothing.
class MaterialReleasePage extends StatefulWidget {
  const MaterialReleasePage({super.key, this.viewmodel, this.printer});

  final MaterialReleaseViewmodel? viewmodel;
  final ReceiptPrinter? printer;

  @override
  State<MaterialReleasePage> createState() => _MaterialReleasePageState();
}

class _MaterialReleasePageState extends State<MaterialReleasePage>
    with WidgetsBindingObserver {
  late final MaterialReleaseViewmodel _viewmodel =
      widget.viewmodel ?? MaterialReleaseViewmodel();
  late final bool _ownsViewmodel = widget.viewmodel == null;
  final _token = TextEditingController();
  bool _printing = false;
  String? _printError;
  Timer? _queueTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewmodel.loadQueue();
    // New accepted requests appear without leaving the page.
    _queueTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _viewmodel.loadQueue(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _viewmodel.loadQueue();
  }

  @override
  void dispose() {
    _queueTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _token.dispose();
    if (_ownsViewmodel) _viewmodel.dispose();
    super.dispose();
  }

  /// Both the button and Enter land here, so the two can never disagree.
  void _verify() {
    final token = _token.text.trim();
    if (token.isEmpty || _viewmodel.isBusy || _printing) return;
    setState(() => _printError = null);
    _viewmodel.verify(token);
  }

  /// The next customer: clear the field and everything the last token proved.
  void _startOver() {
    if (_printing || _viewmodel.isBusy) return;
    _token.clear();
    setState(() => _printError = null);
    _viewmodel.reset();
  }

  Future<void> _pickRequest(int id) async {
    if (_viewmodel.isBusy || _printing) return;
    _token.clear();
    setState(() => _printError = null);
    await _viewmodel.verifyRequest(id);
  }

  Future<void> _printReceipt() async {
    if (_printing || _viewmodel.result == null) return;
    setState(() {
      _printing = true;
      _printError = null;
    });
    try {
      final receipt = await _viewmodel.fetchReceipt();
      await (widget.printer ?? const RollReceiptPrinter()).print(receipt);
    } catch (error) {
      if (mounted) {
        setState(
          () => _printError =
              'Release already recorded. Could not print receipt: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DashboardShell(
      title: 'Release materials',
      subtitle:
          'Pick a waiting request, choose how much goes out today, then release',
      selectedNavigationIndex: 2,
      navigationItems: posNavigationItems,
      onNavigationSelected: (i) => navigatePos(context, i),
      child: AnimatedBuilder(
        animation: _viewmodel,
        builder: (context, _) => _body(context),
      ),
    );
  }

  /// Wide windows: the queue beside the request, so the cashier moves from one
  /// request to the next without switching steps (2026-11-27 design, layout B).
  /// Narrow windows stack the two.
  static const double _twoPaneWidth = 1100;
  static const double _queuePaneWidth = 380;

  Widget _body(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _twoPaneWidth) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: _queuePaneWidth, child: _queuePane()),
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: _requestPane()),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _queuePane(),
            const SizedBox(height: AppSpacing.lg),
            _requestPane(),
          ],
        );
      },
    );
  }

  /// The one failure of the screen, in the app's one error style.
  ///
  /// A `NO_OPEN_SHIFT` refusal is a RULE with a next step the clerk can take, so
  /// it carries the Shifts control instead of a Retry that would fail again.
  Widget? _errorBanner() {
    final failure = _viewmodel.error;
    if (failure == null) return null;
    if (_viewmodel.needsOpenShift) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ErrorBanner(message: failure),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => context.go(AppRoutes.posShifts),
              icon: const Icon(Icons.access_time),
              label: const Text('Go to Shifts'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            ),
          ),
        ],
      );
    }
    // Retrying means repeating the last request: the release when the token is
    // already verified, the verify itself before that.
    return ErrorBanner(
      message: failure,
      onRetry: _viewmodel.hasVerified ? _viewmodel.release : _verify,
    );
  }

  // --------------------------------------------------------------- left pane

  Widget _queuePane() {
    final selected = _viewmodel.verification?.reqNumber;
    return KeyedSubtree(
      key: const ValueKey('release-queue-pane'),
      child: AppPanel(
        title: 'Waiting for release',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Requests the store manager accepted. Pick the one the project '
              'is collecting. The list updates by itself.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            _ReleaseQueue(
              viewmodel: _viewmodel,
              selectedReqNumber: selected,
              enabled: !_viewmodel.isBusy && !_printing,
              onPick: _pickRequest,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Have a token slip instead? Scan its QR or type the token.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            _TokenField(controller: _token, onSubmitted: (_) => _verify()),
            const SizedBox(height: AppSpacing.sm),
            // Disabled with an empty field: a press that cannot work should
            // look like it cannot work, not explain itself afterwards.
            ListenableBuilder(
              listenable: _token,
              builder: (context, _) => FilledButton(
                onPressed:
                    _viewmodel.isBusy ||
                        _printing ||
                        _token.text.trim().isEmpty
                    ? null
                    : _verify,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  // Family spelled out: a partial textStyle REPLACES the
                  // theme's label style and drops the label to the platform
                  // font (app_button_theme.dart says the same).
                  textStyle: const TextStyle(
                    fontFamily: AppTextStyles.outfitFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Verify'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- right pane

  Widget _requestPane() {
    final verification = _viewmodel.verification;
    final result = _viewmodel.result;
    return KeyedSubtree(
      key: const ValueKey('release-request-pane'),
      child: AppPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorBanner() case final banner?) ...[
              banner,
              const SizedBox(height: AppSpacing.md),
            ],
            if (_viewmodel.isBusy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: AppSpacing.md),
            ],
            if (verification == null)
              const _StepHint(
                'Choose a request on the left, or scan a slip. Its items and '
                'what can go out now appear here.',
              )
            else ...[
              _RequestHeader(verification: verification),
              const SizedBox(height: AppSpacing.md),
              if (result == null)
                ..._linesAndRelease(verification)
              else
                _receipt(result),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _linesAndRelease(TokenVerification verification) {
    final items = verification.items;
    final blocked = _viewmodel.confirmBlockedReason;
    final giving = _viewmodel.givingLines.length;
    return [
      if (items.isEmpty)
        const _StepHint('No lines on this requisition.')
      else
        for (var i = 0; i < items.length; i++)
          ReleaseLineRow(
            key: ValueKey('release-line-${items[i].id}'),
            item: items[i],
            giveNow: _viewmodel.giveNow(items[i].id),
            changed: _viewmodel.giveNowChanged(items[i].id),
            onChanged: items[i].isReleasable && !_viewmodel.isBusy
                ? (value) => _viewmodel.setGiveNow(items[i].id, value)
                : null,
            last: i == items.length - 1,
          ),
      const SizedBox(height: AppSpacing.md),
      // Nothing can go out at all: no press, just the reason (decision 05).
      if (!_viewmodel.hasReleasable)
        Text(
          blocked ?? '',
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        )
      else ...[
        ReleaseSummaryBar(
          giving: _viewmodel.givingToday,
          total: _viewmodel.todayTotal,
          stillOpen: _viewmodel.stillOpenAfter,
        ),
        const SizedBox(height: AppSpacing.md),
        if (blocked != null) ...[
          Text(
            blocked,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.warningText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        // One large button, like the till's Pay: this is the irreversible press
        // and it should not look like a form.
        FilledButton.icon(
          key: const ValueKey('release-confirm'),
          onPressed: _viewmodel.isBusy || blocked != null
              ? null
              : _viewmodel.release,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 56),
            textStyle: const TextStyle(
              fontFamily: AppTextStyles.outfitFont,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          icon: const Icon(Icons.check_circle_outline),
          label: Text(
            giving == 1 ? 'Release 1 item' : 'Release $giving items',
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Releasing deducts the stock and posts the receivable. It cannot be '
          'undone. Whatever is not given stays open on this token.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    ];
  }

  Widget _receipt(ReleaseResult result) {
    return Column(
      key: const ValueKey('release-receipt'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Decision 05: a short release leaves the request open, and the
            // clerk has to say so, so the receipt cannot read "Released".
            StatusBadge(
              label: result.isPartial ? 'Partially released' : 'Released',
              tone: result.isPartial ? StatusTone.warning : StatusTone.success,
            ),
            const Spacer(),
            Text(
              'Sale ${result.transactionNo}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        // A count of zero is not a sentence: the server can answer PARTIAL
        // while every line is finished, and "0 lines still open" would send
        // the project away and back for nothing.
        if (result.isPartial && result.openLineCount > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Partially released: ${_openLines(result)} still open on '
            'this token.',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        _MoneyLine(label: 'Total', amount: result.grandTotal),
        const SizedBox(height: AppSpacing.xs),
        // A construction firm pays later, so this is the number the clerk
        // must say out loud.
        _MoneyLine(
          label: 'Balance due',
          amount: result.balanceDue,
          emphasis: true,
        ),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(
          onPressed: _printing ? null : _printReceipt,
          icon: const Icon(Icons.print_outlined),
          label: Text(_printing ? 'Printing…' : 'Print receipt'),
        ),
        if (_printError case final message?) ...[
          const SizedBox(height: AppSpacing.sm),
          ErrorBanner(message: message),
        ],
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          onPressed: _viewmodel.isBusy || _printing ? null : _startOver,
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          child: const Text('Next request'),
        ),
      ],
    );
  }
}

/// One line, in words a clerk can repeat: how many lines the request still owes.
String _openLines(ReleaseResult result) =>
    result.openLineCount == 1 ? '1 line' : '${result.openLineCount} lines';

/// The open request: number, project, who it is for, and where it stands.
class _RequestHeader extends StatelessWidget {
  const _RequestHeader({required this.verification});

  final TokenVerification verification;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (verification.status) {
      'PARTIAL' => ('Partly released', StatusTone.warning),
      'ACCEPTED' => ('Accepted', StatusTone.success),
      _ => (null, StatusTone.neutral),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  verification.reqNumber,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(verification.project),
                // Who the materials are being released for — the same
                // provenance rule as the approve queue.
                Text(
                  'For ${verification.customer}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (label != null) StatusBadge(label: label, tone: tone),
        ],
      ),
    );
  }
}

/// The token field
class _TokenField extends StatelessWidget {
  const _TokenField({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.medium),
      borderSide: const BorderSide(color: AppColors.brandGold, width: 2),
    );
    return TextField(
      key: const ValueKey('release.tokenField'),
      controller: controller,
      autofocus: true,
      onSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        // A 2D scanner types the slip's QR into this field and presses Enter,
        // which submits it like a typed token.
        hintText: 'Scan the slip QR or type the token',
        filled: true,
        fillColor: const Color(0xFFFFFDF7),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: AppColors.brandBlack, width: 2),
        ),
        prefixIcon: const Icon(
          Icons.key_outlined,
          color: AppColors.brandGoldText,
        ),
      ),
    );
  }
}

/// A muted sentence where a step's content will be.
class _StepHint extends StatelessWidget {
  const _StepHint(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
    );
  }
}

/// A label and its amount, the amount right aligned in tabular digits so two
/// receipts can be compared down the decimal point.
class _MoneyLine extends StatelessWidget {
  const _MoneyLine({
    required this.label,
    required this.amount,
    this.emphasis = false,
  });

  final String label;
  final double amount;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: emphasis ? 18 : 14,
      fontWeight: emphasis ? FontWeight.w700 : FontWeight.w400,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: emphasis ? 15 : 14,
              fontWeight: emphasis ? FontWeight.w600 : FontWeight.w400,
              color: emphasis ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
        Text(formatPeso(amount), style: style),
      ],
    );
  }
}

/// The accepted requests waiting at the counter, picked with one click.
class _ReleaseQueue extends StatefulWidget {
  const _ReleaseQueue({
    required this.viewmodel,
    required this.selectedReqNumber,
    required this.enabled,
    required this.onPick,
  });

  final MaterialReleaseViewmodel viewmodel;
  final String? selectedReqNumber;
  final bool enabled;
  final ValueChanged<int> onPick;

  @override
  State<_ReleaseQueue> createState() => _ReleaseQueueState();
}

class _ReleaseQueueState extends State<_ReleaseQueue> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final viewmodel = widget.viewmodel;
    final all = viewmodel.queue;
    final queue = [
      for (final request in all)
        if ('${request.reqNumber} ${request.projectName} '
                '${request.projectCustomerName}'
            .toLowerCase()
            .contains(_search))
          request,
    ];
    if (viewmodel.queueLoading && all.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (viewmodel.queueError case final message?) ...[
          ErrorBanner(message: message, onRetry: viewmodel.loadQueue),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (all.isNotEmpty) ...[
          TextField(
            key: const ValueKey('release.requestSearch'),
            decoration: const InputDecoration(
              labelText: 'Search request number, project or customer',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (value) =>
                setState(() => _search = value.trim().toLowerCase()),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (all.isEmpty && viewmodel.queueError == null)
          const _StepHint(
            'No accepted requests are waiting. New ones appear here as soon as '
            'the store manager accepts them.',
          )
        else if (queue.isEmpty && all.isNotEmpty)
          const _StepHint('No requests match your search.'),
        for (final request in queue)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _QueueTile(
              request: request,
              selected: request.reqNumber == widget.selectedReqNumber,
              onTap: widget.enabled ? () => widget.onPick(request.id) : null,
            ),
          ),
      ],
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.request, required this.selected, this.onTap});

  final Requisition request;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final partial = request.rawStatus == 'PARTIAL';
    final lines = request.items.length;
    return Material(
      color: selected ? AppColors.selected : AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        side: BorderSide(
          color: selected ? AppColors.brandGold : AppColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.reqNumber,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${request.projectName} · ${request.projectCustomerName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$lines item${lines == 1 ? '' : 's'}'
                      '${partial ? ' · remaining items only' : ''}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              StatusBadge(
                label: selected
                    ? 'Selected'
                    : partial
                    ? 'Partly released'
                    : 'Ready',
                tone: selected
                    ? StatusTone.info
                    : partial
                    ? StatusTone.warning
                    : StatusTone.success,
              ),
              const SizedBox(width: AppSpacing.sm),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
