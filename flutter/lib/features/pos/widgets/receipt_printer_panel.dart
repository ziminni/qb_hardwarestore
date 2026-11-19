import 'package:clock/clock.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/printing/raw_printer.dart';
import 'package:client/core/printing/roll_printer.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:flutter/material.dart';

/// The till's Settings tab: which printer on THIS computer receipts and
/// delivery slips go to. The choice is saved on the computer, not the server,
/// because the printer is plugged into it.
class ReceiptPrinterPanel extends StatefulWidget {
  const ReceiptPrinterPanel({super.key, this.raw});

  /// Injected by tests; the app talks to this computer's print system.
  final RawPrinter? raw;

  @override
  State<ReceiptPrinterPanel> createState() => _ReceiptPrinterPanelState();
}

class _ReceiptPrinterPanelState extends State<ReceiptPrinterPanel> {
  late final RollPrinter _printer = RollPrinter(raw: widget.raw);
  List<RawPrinterInfo>? _printers;
  RawPrinterInfo? _chosen;
  bool _autoPrint = true;
  String? _error;
  String? _notice;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _notice = null;
    });
    final chosen = await RollPrinter.saved();
    final autoPrint = await RollPrinter.autoPrint();
    if (mounted) setState(() => _autoPrint = autoPrint);
    try {
      final printers = await _printer.printers();
      if (!mounted) return;
      setState(() {
        _chosen = chosen;
        _printers = printers;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _chosen = chosen;
        _printers = const [];
        _error = 'Could not list this computer\'s printers: $error';
      });
    }
  }

  Future<void> _choose(RawPrinterInfo printer) async {
    await RollPrinter.choose(printer);
    if (!mounted) return;
    setState(() {
      _chosen = printer;
      _error = null;
      _notice = 'Receipts now print to ${printer.name}.';
    });
  }

  Future<void> _testPrint() async {
    final chosen = _chosen;
    if (chosen == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await _printer.print(
        buildTestPrintEscPos(chosen.name, clock.now()),
        job: 'Receipt printer test',
      );
      if (mounted) setState(() => _notice = 'Test sent to ${chosen.name}.');
    } catch (error) {
      if (mounted) setState(() => _error = 'Test print failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final printers = _printers;
    final chosen = _chosen;
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            chosen == null
                ? 'No receipt printer chosen. Receipts will not print on this '
                      'computer until one is.'
                : 'Receipts print to ${chosen.name}.',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Choose the 58 mm thermal receipt printer. Receipts go to it '
            'directly, with no print dialog. Any other printer would print '
            'the receipt as gibberish.',
          ),
          const SizedBox(height: AppSpacing.md),
          if (printers == null)
            const Center(child: CircularProgressIndicator())
          else if (printers.isEmpty && _error == null)
            const Text(
              'No printers found. Connect the receipt printer, then refresh.',
            )
          else
            // Its own Material: the panel's filled box would hide the tiles'
            // tap ink otherwise.
            Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  for (final printer in printers)
                    ListTile(
                      key: ValueKey('receipt-printer-${printer.id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        printer.id == chosen?.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      title: Text(printer.name),
                      onTap: _busy ? null : () => _choose(printer),
                    ),
                ],
              ),
            ),
          if (_error case final error?) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(error, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (_notice case final notice?) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(notice),
          ],
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const ValueKey('receipt-auto-print'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Print the receipt after each sale'),
              subtitle: const Text(
                'Off: nothing prints by itself. Print receipt on the '
                'finished sale still prints one.',
              ),
              value: _autoPrint,
              onChanged: (on) {
                setState(() => _autoPrint = on);
                RollPrinter.setAutoPrint(on);
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh list'),
              ),
              FilledButton.icon(
                onPressed: _busy || chosen == null ? null : _testPrint,
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Print test receipt'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
