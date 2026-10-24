import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
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

  final count = await showDialog<double>(
    context: context,
    builder: (dialogContext) => _CloseShiftDialog(shift: shift),
  );
  if (count == null) return null;

  final closed = await viewmodel.closeShift(count);
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
          child: PosZReadingSummary(reading: reading),
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

  @override
  void dispose() {
    _controller.dispose();
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

  @override
  Widget build(BuildContext context) {
    final count = _count;
    return AlertDialog(
      title: const Text('Close shift'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Opening float ₱${widget.shift.openingFloat.toStringAsFixed(2)}. '
            'Count the drawer and enter the total cash.',
          ),
          // Decision 06 / Phase 3 Task 3: record-and-WARN, never block. The
          // carts are not deleted by the close and can still be resumed, so the
          // cashier is told the count and may close anyway. A warning on every
          // close would be a warning nobody reads, hence the > 0 guard.
          if (widget.shift.heldCartCount > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${widget.shift.heldCartCount} held cart(s) remain — they stay '
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: count == null
              ? null
              : () => Navigator.of(context).pop(count),
          child: const Text('Close shift'),
        ),
      ],
    );
  }
}
