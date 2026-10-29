import 'package:flutter/material.dart';

/// Swaps one selling unit's code for its factory barcode, or back.
///
/// The PATCH itself is the caller's `onSubmit` (the details dialog hands it the
/// store's `setSellingUnitBarcode`, which writes and reloads) so this form stays a
/// form: it can be tested with an answer instead of a server.
///
/// A refused code keeps the dialog OPEN with the server's sentence on the field —
/// closing would leave the user with a message and no way to fix the typing.
class EditUnitCodeDialog extends StatefulWidget {
  const EditUnitCodeDialog({
    super.key,
    required this.unitName,
    required this.currentCode,
    required this.onSubmit,
  });

  /// The selling unit being edited, e.g. `BOX`.
  final String unitName;

  /// What the unit's code is right now, shown so the clerk knows what changes.
  final String currentCode;

  /// Returns null when the server accepted the code, or the message to show.
  final Future<String?> Function(String code) onSubmit;

  @override
  State<EditUnitCodeDialog> createState() => _EditUnitCodeDialogState();
}

class _EditUnitCodeDialogState extends State<EditUnitCodeDialog> {
  final _code = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    // Trimmed only: the server normalises (trim + upper), and sending exactly what
    // was typed keeps its refusal messages about the text the user sees.
    final message = await widget.onSubmit(_code.text.trim());
    if (!mounted) return;
    if (message != null) {
      setState(() {
        _error = message;
        _saving = false;
      });
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.unitName} code'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current code: ${widget.currentCode}'),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: 'Barcode',
                hintText: 'Factory barcode — leave blank to restore the QB code',
                errorText: _error,
                prefixIcon: const Icon(Icons.barcode_reader),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
