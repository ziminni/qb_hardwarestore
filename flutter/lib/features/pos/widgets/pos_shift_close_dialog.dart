import 'package:client/core/constants/app_colors.dart';
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

  /// "The drawer was cleared": sends `cash_left: 0.00`, which the server records
  /// as a REAL number (different from omitting the field).
  bool _cleared = false;

  @override
  void dispose() {
    _controller.dispose();
    _leftController.dispose();
    super.dispose();
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
    return AlertDialog(
      title: const Text('Close shift'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Opening float ${formatPeso(widget.shift.openingFloat)}. '
            'Count the drawer and enter the total cash.',
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
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Cash counted',
              prefixText: '₱ ',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Owner ruling (drawer carry): what stays behind for the next shift.
          // Optional on purpose - an unanswered question is stored as "not
          // recorded", which is a different fact from a cleared drawer.
          TextField(
            controller: _leftController,
            enabled: !_cleared,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Cash left in drawer',
              prefixText: '₱ ',
              helperText: count == null
                  ? 'Count the drawer first.'
                  : 'Stays for the next shift; the rest is the deposit.',
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
            title: const Text('Drawer cleared'),
            subtitle: const Text('Leaves ₱0.00 in the drawer.'),
            onChanged: (value) => setState(() => _cleared = value ?? false),
          ),
          if (cashLeft != null && count != null)
            Text(
              'Deposit: ${formatPeso(count - cashLeft)}',
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: count == null || !_cashLeftValid
              ? null
              : () => Navigator.of(
                  context,
                ).pop(_CloseResult(count: count, cashLeft: cashLeft)),
          child: const Text('Close shift'),
        ),
      ],
    );
  }
}

/// What the close form collected: the counted cash, and what stays in the
/// drawer (`null` = the question was not answered).
class _CloseResult {
  const _CloseResult({required this.count, this.cashLeft});

  final double count;
  final double? cashLeft;
}
