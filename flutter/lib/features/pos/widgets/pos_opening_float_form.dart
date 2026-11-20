import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The opening-float field, and the only way a shift gets opened from the UI.
///
/// One widget for both places it appears — the till's gate and the Shifts tab's
/// dialog — so the two can never validate differently. Two things are shared
/// deliberately:
///
/// * **The float rule.** A negative float is refused here as well as on the
///   server: cash that cannot be in a drawer is a typo, and catching it keeps
///   the form up instead of posting a shift whose drawer arithmetic is already
///   wrong.
/// * **The failure handling.** A refused open shows the server's own message
///   (`SHIFT_ALREADY_OPEN` says what to do next, where a generic one would not)
///   and leaves the form usable.
///
/// It never navigates: the till keeps its full-page panel, the Shifts tab closes
/// its dialog. [onOpened] is how each caller says what happens next.
class PosOpeningFloatForm extends StatefulWidget {
  const PosOpeningFloatForm({super.key, this.onOpened});

  /// Called with the server's copy of the opened shift, after a 2xx open.
  final ValueChanged<Shift>? onOpened;

  @override
  State<PosOpeningFloatForm> createState() => _PosOpeningFloatFormState();
}

class _PosOpeningFloatFormState extends State<PosOpeningFloatForm> {
  final _floatController = TextEditingController();
  bool _opening = false;
  bool _askedForSuggestion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Owner ruling (drawer carry): ask ONCE what the last close left, then
    // prefill it as an EDITABLE starting point. The cashier still counts and
    // may overwrite it freely; nothing here opens a shift.
    if (_askedForSuggestion) return;
    _askedForSuggestion = true;
    final shift = context.read<ShiftViewmodel>();
    shift.loadOpeningSuggestion().then((_) {
      if (!mounted) return;
      final suggested = shift.openingSuggestion?.suggestedFloat;
      if (suggested == null || _floatController.text.isNotEmpty) {
        setState(() {});
        return;
      }
      _floatController.text = suggested.toStringAsFixed(2);
      setState(() {});
    });
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  double? get _openingFloat {
    final parsed = double.tryParse(_floatController.text.trim());
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }

  Future<void> _open() async {
    final openingFloat = _openingFloat;
    if (openingFloat == null || _opening) return;
    final shift = context.read<ShiftViewmodel>();
    setState(() => _opening = true);
    final opened = await shift.openShift(openingFloat);
    if (!mounted) return;
    setState(() => _opening = false);
    if (opened == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(shift.actionError ?? 'The shift could not be opened.'),
        ),
      );
      return;
    }
    widget.onOpened?.call(opened);
  }

  @override
  Widget build(BuildContext context) {
    final openingFloat = _openingFloat;
    final suggestion = context.watch<ShiftViewmodel>().openingSuggestion;
    final suggestionError = context
        .watch<ShiftViewmodel>()
        .openingSuggestionError;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (suggestionError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'Last drawer amount unavailable - count the cash. '
              '($suggestionError)',
              style: const TextStyle(fontSize: 12),
            ),
          )
        else if (suggestion != null && suggestion.cleared)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'The last shift cleared the drawer, so it starts empty. '
              'Count and confirm the cash you are starting with.',
              style: const TextStyle(fontSize: 12),
            ),
          )
        else if (suggestion?.source != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'The last shift left a drawer amount to carry over. It is '
              'prefilled - count and correct it if it differs.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        TextField(
          controller: _floatController,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Opening float',
            prefixText: '₱ ',
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _open(),
        ),
        const SizedBox(height: AppSpacing.lg),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: openingFloat == null || _opening ? null : _open,
            child: _opening
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Open shift'),
          ),
        ),
      ],
    );
  }
}
