import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/viewmodels/material_release_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/features/pos/widgets/pos_release_step_panel.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The material release counter — Phase 5's only **irreversible** screen (decision 09).
///
/// A store clerk takes a printed token from a foreman, checks it, and releases the materials. The
/// release FIFO-deducts real stock, writes a real `SalesTransaction`, and **always** leaves a
/// receivable because a construction firm pays later — so the receipt is shown, not just the success.
///
/// Three steps, in the order the clerk does them: verify the token, review the requisition it
/// stands for, then the receipt the release leaves behind. [viewmodel] is injectable so a test can
/// observe what the screen sends; production passes nothing.
class MaterialReleasePage extends StatefulWidget {
  const MaterialReleasePage({super.key, this.viewmodel});

  final MaterialReleaseViewmodel? viewmodel;

  @override
  State<MaterialReleasePage> createState() => _MaterialReleasePageState();
}

class _MaterialReleasePageState extends State<MaterialReleasePage> {
  late final MaterialReleaseViewmodel _viewmodel =
      widget.viewmodel ?? MaterialReleaseViewmodel();
  late final bool _ownsViewmodel = widget.viewmodel == null;
  final _token = TextEditingController();

  @override
  void dispose() {
    _token.dispose();
    if (_ownsViewmodel) _viewmodel.dispose();
    super.dispose();
  }

  /// Both the button and Enter land here, so the two can never disagree.
  void _verify() {
    final token = _token.text.trim();
    if (token.isEmpty || _viewmodel.isBusy) return;
    _viewmodel.verify(token);
  }

  /// The next customer: clear the field and everything the last token proved.
  void _startOver() {
    _token.clear();
    _viewmodel.reset();
  }

  @override
  Widget build(BuildContext context) {
    return DashboardShell(
      title: 'Release materials',
      subtitle: 'Verify a material token and release the stock it covers',
      selectedNavigationIndex: 2,
      navigationItems: posNavigationItems,
      onNavigationSelected: (i) => navigatePos(context, i),
      child: AnimatedBuilder(
        animation: _viewmodel,
        builder: (context, _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_errorBanner() case final banner?) ...[
          banner,
          const SizedBox(height: AppSpacing.lg),
        ],
        // One column at every width: the steps are a sequence, and a side by
        // side layout squeezed the requisition into cards and pushed the
        // release below the fold even on a 1440 px window.
        _tokenStep(),
        const SizedBox(height: AppSpacing.lg),
        _reviewStep(),
        const SizedBox(height: AppSpacing.lg),
        _receiptStep(),
      ],
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

  // ------------------------------------------------------------------ step 1

  Widget _tokenStep() {
    return PosReleaseStepPanel(
      step: 1,
      title: 'Verify the token',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Type or paste the token printed on the approved requisition, then '
            'press Enter.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _TokenField(
                  controller: _token,
                  onSubmitted: (_) => _verify(),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Disabled with an empty field: a press that cannot work should
              // look like it cannot work, not explain itself afterwards.
              ListenableBuilder(
                listenable: _token,
                builder: (context, _) => SizedBox(
                  height: _TokenField.height,
                  child: FilledButton(
                    onPressed: _viewmodel.isBusy || _token.text.trim().isEmpty
                        ? null
                        : _verify,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(148, _TokenField.height),
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
              ),
            ],
          ),
          if (_viewmodel.isBusy)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.md),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ step 2

  Widget _reviewStep() {
    final verification = _viewmodel.verification;
    return PosReleaseStepPanel(
      step: 2,
      title: 'Review the requisition',
      pending: verification == null,
      child: verification == null
          ? const _StepHint(
              'The requisition behind the token appears here once the token is '
              'verified.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  verification.reqNumber,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
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
                const SizedBox(height: AppSpacing.md),
                _RequisitionLines(items: verification.items),
                if (!_viewmodel.isReleased) ...[
                  const SizedBox(height: AppSpacing.md),
                  // One large button, like the till's Pay: this is the
                  // irreversible press and it should not look like a form.
                  FilledButton(
                    onPressed: _viewmodel.isBusy ? null : _viewmodel.release,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 56),
                      textStyle: const TextStyle(
                        fontFamily: AppTextStyles.outfitFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('Release materials'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'Releasing deducts the stock and posts the receivable. It '
                    'cannot be undone.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  // ------------------------------------------------------------------ step 3

  Widget _receiptStep() {
    final result = _viewmodel.result;
    final verification = _viewmodel.verification;
    return PosReleaseStepPanel(
      step: 3,
      title: 'Release receipt',
      pending: result == null,
      child: result == null
          ? const _StepHint(
              'The receipt for this release appears here once the materials '
              'leave the store.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const StatusBadge(
                      label: 'Released',
                      tone: StatusTone.success,
                    ),
                    const Spacer(),
                    if (verification != null)
                      Text(
                        verification.reqNumber,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Sale ${result.transactionNo}'),
                // What left stock is NOT repeated here: step 2 shows the same
                // lines one panel above, and printing them twice pushed the
                // balance due off a 900 px window. The money is the part the
                // clerk has to say out loud.
                const SizedBox(height: AppSpacing.md),
                _MoneyLine(label: 'Total', amount: result.grandTotal),
                const SizedBox(height: AppSpacing.xs),
                // A construction firm pays later, so this is the number the
                // clerk must say out loud.
                _MoneyLine(
                  label: 'Balance due',
                  amount: result.balanceDue,
                  emphasis: true,
                ),
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton(
                  onPressed: _viewmodel.isBusy ? null : _startOver,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  child: const Text('Verify another token'),
                ),
              ],
            ),
    );
  }
}

/// The verified requisition's lines: item, how many were asked for and how many
/// are still to hand over, in one compact table.
///
/// Not `DataPanel`: inside a step panel its own frame doubled the borders, and
/// under 720 px of content it falls back to one tall card per line, which put
/// the release action below the fold at both 760 px and 1440 px. A requisition
/// has a handful of lines and two numbers each, so three narrow columns read
/// straight down.
class _RequisitionLines extends StatelessWidget {
  const _RequisitionLines({required this.items});

  final List<VerifiedRequisitionItem> items;

  static const double _numberWidth = 76;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _StepHint('No lines on this requisition.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(
          const Text('Item', style: _headerStyle),
          const Text(
            'Requested',
            style: _headerStyle,
            textAlign: TextAlign.right,
          ),
          const Text(
            'Remaining',
            style: _headerStyle,
            textAlign: TextAlign.right,
          ),
          last: false,
        ),
        for (var index = 0; index < items.length; index++)
          _row(
            Text(
              items[index].variantName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _quantity(items[index].quantity),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              _quantity(items[index].remaining),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            last: index == items.length - 1,
          ),
      ],
    );
  }

  Widget _row(
    Widget item,
    Widget requested,
    Widget remaining, {
    required bool last,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: last
          ? null
          : const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
      child: Row(
        children: [
          Expanded(flex: 3, child: item),
          SizedBox(width: _numberWidth, child: requested),
          SizedBox(width: _numberWidth, child: remaining),
        ],
      ),
    );
  }
}

const TextStyle _headerStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: AppColors.textSecondary,
);

/// The token field
class _TokenField extends StatelessWidget {
  const _TokenField({required this.controller, required this.onSubmitted});

  /// The field and the button beside it are one row, so the button matches the
  /// field instead of relying on both growing to the same height by accident.
  static const double height = 58;

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.medium),
      borderSide: const BorderSide(color: AppColors.brandGold, width: 2),
    );
    return TextField(
      controller: controller,
      autofocus: true,
      onSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        hintText: 'Paste or type the token',
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

/// A requisition quantity as a person writes it: whole bags are not "10.0".
String _quantity(double value) => value == value.roundToDouble()
    ? formatCount(value.round())
    : value.toStringAsFixed(2);
