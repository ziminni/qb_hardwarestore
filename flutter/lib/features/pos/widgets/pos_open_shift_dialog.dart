import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_opening_float_form.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The open-shift flow as a dialog, for the screens that are not the till.
///
/// The till replaces itself with a full-page gate (it cannot ring a sale
/// without a shift, so it takes the whole surface); every other entry point —
/// the Shifts tab, and the "Go to Shifts" route out of the Release gate and the
/// Returns gate — asks for the same number in a dialog. Both render the SAME
/// [PosOpeningFloatForm], so the float rule and the server's failure messages
/// cannot drift apart.
///
/// The viewmodel is passed IN and re-provided inside the dialog, exactly like
/// [showShiftCloseDialog]. A dialog is a route pushed above the page, so it has
/// no access to the provider the page installs around itself: reading one there
/// threw ProviderNotFoundException inside the async tap callback, where it was
/// swallowed and the cashier saw a button that did nothing (live QA).
///
/// Returns the server's copy of the opened shift, or null when the cashier
/// cancelled or the open failed.
Future<Shift?> showOpenShiftDialog(
  BuildContext context,
  ShiftViewmodel viewmodel,
) {
  return showDialog<Shift>(
    context: context,
    // Above the AlertDialog, not around the call site: everything the form
    // reads has to be an ancestor of the dialog's own subtree.
    builder: (dialogContext) => ChangeNotifierProvider<ShiftViewmodel>.value(
      value: viewmodel,
      child: AlertDialog(
        title: const Text('Open shift'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Every sale is counted in a shift. Count the cash in the drawer '
                'and enter it as the opening float.',
              ),
              const SizedBox(height: AppSpacing.lg),
              PosOpeningFloatForm(
                onOpened: (shift) => Navigator.of(dialogContext).pop(shift),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}
