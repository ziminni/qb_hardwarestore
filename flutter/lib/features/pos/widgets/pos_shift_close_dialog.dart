import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_z_reading_summary.dart';
import 'package:flutter/material.dart';

/// The end-of-shift form: counted cash in, Z-reading out.
///
/// One function for both places a shift is closed (the till and the Shifts tab)
/// so the two can never ask for different things or show different numbers.
///
/// Returns the closed shift, or null when the cashier cancelled, entered an
/// unreadable count, or the server refused. A variance is NEVER a refusal
/// (decision 06, ruling 3): it is shown afterwards, and management reviews it.
Future<Shift?> showShiftCloseDialog(
  BuildContext context,
  ShiftViewmodel viewmodel,
) async {
  final shift = viewmodel.currentShift;
  if (shift == null) return null;

  final result = await showDialog<_CloseResult>(
    context: context,
    builder: (dialogContext) => _CloseShiftDialog(shift: shift),
  );
  if (result == null) return null;

  final closed = await viewmodel.closeShift(
    result.count,
    cashLeft: result.cashLeft,
    denominations: result.denominations,
  );
  if (!context.mounted) return closed;
  if (closed == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          viewmodel.actionError ?? 'The shift could not be closed.',
        ),
      ),
    );
    return null;
  }

  final reading = closed.zReading;
  if (reading != null) {
    await showDialog<void>(
      context: context,
      builder: (resultContext) => AlertDialog(
        title: const Text('Shift closed'),
        content: SingleChildScrollView(
          child: PosZReadingSummary(
            reading: reading,
            // Both sides of the difference the cashier is about to read.
            closingCount: closed.closingCount,
            cashMovements: closed.cashMovements,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(resultContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
  return closed;
}

class _CloseShiftDialog extends StatefulWidget {
  const _CloseShiftDialog({required this.shift});

  final Shift shift;

  @override
  State<_CloseShiftDialog> createState() => _CloseShiftDialogState();
}

class _CloseShiftDialogState extends State<_CloseShiftDialog> {
  final _controller = TextEditingController();
  final _leftController = TextEditingController();
  final Map<String, TextEditingController> _denomControllers = {
    for (final d in ShiftCashMovement.phpDenominations)
      d.key: TextEditingController(),
  };
  bool _showDenominations = false;

  /// "The drawer was cleared": sends `cash_left: 0.00`, which the server records
  /// as a REAL number (different from omitting the field).
  bool _cleared = false;

  @override
  void dispose() {
    _controller.dispose();
    _leftController.dispose();
    for (final c in _denomControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, int> get _denominations {
    final out = <String, int>{};
    for (final d in ShiftCashMovement.phpDenominations) {
      final cnt = int.tryParse(_denomControllers[d.key]!.text.trim()) ?? 0;
      if (cnt > 0) out[d.key] = cnt;
    }
    return out;
  }

  void _syncFromDenominations() {
    var sum = 0.0;
    for (final d in ShiftCashMovement.phpDenominations) {
      final cnt = int.tryParse(_denomControllers[d.key]!.text.trim()) ?? 0;
      if (cnt > 0) sum += d.value * cnt;
    }
    _controller.text = sum.toStringAsFixed(2);
    setState(() {});
  }

  /// A negative count is refused here as well as on the server: money that
  /// cannot be in a drawer is a typo, and catching it before the POST keeps a
  /// valid shift open instead of half-closed.
  double? get _count {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }

  /// What STAYS in the drawer (owner ruling). Null = the cashier leaves the
  /// question unanswered, which the server records as "not recorded". Never
  /// assumed to be the whole count: the deposit is the rest.
  double? get _cashLeft {
    if (_cleared) return 0;
    final text = _leftController.text.trim();
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    if (parsed == null || parsed < 0) return null;
    final count = _count;
    if (count != null && parsed > count) return null;
    return parsed;
  }

  bool get _cashLeftValid {
    if (_cleared) return true;
    final text = _leftController.text.trim();
    if (text.isEmpty) return true;
    return _cashLeft != null;
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    final cashLeft = _cashLeft;
    final expected = widget.shift.zReading?.expectedDrawer;
    return AlertDialog(
      title: const Text('Close shift'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
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
                          const Text(
                            'Opening float',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            formatPeso(widget.shift.openingFloat),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (expected != null)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Expected in drawer',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              formatPeso(expected),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          // Decision 06 / Phase 3 Task 3: record-and-WARN, never block. The
          // carts are not deleted by the close and can still be resumed, so the
          // cashier is told the count and may close anyway. A warning on every
          // close would be a warning nobody reads, hence the > 0 guard.
          if (widget.shift.heldCartCount > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${widget.shift.heldCartCount} held cart(s) remain. They stay '
              'held and can be resumed later.',
              style: TextStyle(
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            key: const ValueKey('shift-close-denoms-toggle'),
            onPressed: () =>
                setState(() => _showDenominations = !_showDenominations),
            icon: Icon(
              _showDenominations ? Icons.expand_less : Icons.payments_outlined,
              size: 18,
            ),
            label: Text(
              _showDenominations
                  ? 'Hide bill & coin counter'
                  : 'Count by bills & coins',
            ),
          ),
          if (_showDenominations)
            Container(
              width: 420,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(AppRadii.medium),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Bills & Coins',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (_denominations.isNotEmpty)
                        TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () {
                            for (final c in _denomControllers.values) {
                              c.clear();
                            }
                            _syncFromDenominations();
                          },
                          child: const Text('Clear'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      for (final d in ShiftCashMovement.phpDenominations)
                        SizedBox(
                          width: 186,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 58,
                                child: Text(
                                  d.label,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 58,
                                child: TextField(
                                  key: ValueKey('denom-${d.key}'),
                                  controller: _denomControllers[d.key],
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    filled: true,
                                    fillColor: AppColors.cardBackground,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 7,
                                    ),
                                    hintText: '0',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (_) => _syncFromDenominations(),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  formatPeso(
                                    (int.tryParse(
                                              _denomControllers[d.key]!.text
                                                  .trim(),
                                            ) ??
                                            0) *
                                        d.value,
                                  ),
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textSecondary,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Actual cash counted in drawer',
              helperText:
                  'Total physical cash inside the register right now (or use the bill & coin counter above).',
              prefixText: '₱ ',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          // Owner ruling (drawer carry): what stays behind for the next shift.
          // Optional on purpose - an unanswered question is stored as "not
          // recorded", which is a different fact from a cleared drawer.
          TextField(
            controller: _leftController,
            enabled: !_cleared,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Keep in drawer (Next shift float)',
              prefixText: '₱ ',
              border: const OutlineInputBorder(),
              helperText: count == null
                  ? 'Enter actual cash counted first.'
                  : 'Stays in the register for the next cashier; the rest goes to Safe Deposit.',
              errorText: _cashLeftValid
                  ? null
                  : 'Enter 0 or more, up to the counted cash.',
            ),
            onChanged: (_) => setState(() {}),
          ),
          CheckboxListTile(
            value: _cleared,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Drawer cleared (take all cash out)'),
            subtitle: const Text('Leaves ₱0.00 in the drawer for the next shift.'),
            onChanged: (value) => setState(() => _cleared = value ?? false),
          ),
          if (cashLeft != null && count != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.brandGold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadii.small),
                border: Border.all(color: AppColors.brandGold),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Safe deposit (cash to hand over)',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    formatPeso(count - cashLeft),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
        ],
        ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: count == null || !_cashLeftValid
              ? null
              : () => Navigator.of(context).pop(
                  _CloseResult(
                    count: count,
                    cashLeft: cashLeft,
                    denominations: _denominations,
                  ),
                ),
          child: const Text('Close shift'),
        ),
      ],
    );
  }
}

/// What the close form collected: the counted cash, and what stays in the
/// drawer (`null` = the question was not answered).
class _CloseResult {
  const _CloseResult({
    required this.count,
    this.cashLeft,
    this.denominations = const {},
  });

  final double count;
  final double? cashLeft;
  final Map<String, int> denominations;
}
