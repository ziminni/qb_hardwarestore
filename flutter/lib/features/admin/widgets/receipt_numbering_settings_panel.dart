import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

class _SeriesDraft {
  _SeriesDraft({
    required this.name,
    required this.prefix,
    required this.nextNumber,
    required this.digits,
  });

  final String name;
  String prefix;
  int nextNumber;
  int digits;

  String get preview =>
      '$prefix${nextNumber.toString().padLeft(digits, '0')}';
}

/// Admin Settings -> Receipts & numbering (frontend-only configuration draft
/// with live thermal receipt preview, ready to bind to a store document-series
/// endpoint once added server-side).
class ReceiptNumberingSettingsPanel extends StatefulWidget {
  const ReceiptNumberingSettingsPanel({super.key, required this.canEdit});

  final bool canEdit;

  @override
  State<ReceiptNumberingSettingsPanel> createState() =>
      _ReceiptNumberingSettingsPanelState();
}

class _ReceiptNumberingSettingsPanelState
    extends State<ReceiptNumberingSettingsPanel> {
  final List<_SeriesDraft> _series = [
    _SeriesDraft(
      name: 'Order Slip',
      prefix: 'OS-',
      nextNumber: 1001,
      digits: 6,
    ),
    _SeriesDraft(
      name: 'POS Transaction',
      prefix: 'TRX-',
      nextNumber: 2401,
      digits: 6,
    ),
    _SeriesDraft(
      name: 'Delivery Slip',
      prefix: 'DS-',
      nextNumber: 301,
      digits: 5,
    ),
    _SeriesDraft(
      name: 'Purchase Order',
      prefix: 'PO-',
      nextNumber: 501,
      digits: 5,
    ),
    _SeriesDraft(
      name: 'Quotation',
      prefix: 'QT-',
      nextNumber: 120,
      digits: 5,
    ),
  ];

  bool _resetYearly = false;
  String _paperWidth = '80mm';
  final TextEditingController _headerLine = TextEditingController(
    text: 'QUEEN BUILDERS HARDWARE & CONSTRUCTION SUPPLIES',
  );
  final TextEditingController _tinLine = TextEditingController(
    text: 'VAT REG TIN: 000-123-456-000',
  );
  final TextEditingController _footerLine = TextEditingController(
    text: 'Returns accepted within 7 days with original receipt.',
  );

  @override
  void dispose() {
    _headerLine.dispose();
    _tinLine.dispose();
    _footerLine.dispose();
    super.dispose();
  }

  Future<void> _editSeries(_SeriesDraft item) {
    return showDialog<void>(
      context: context,
      builder: (_) => _SeriesEditDialog(
        item: item,
        onSaved: (prefix, next) {
          setState(() {
            if (prefix.isNotEmpty) item.prefix = prefix;
            if (next != null && next > 0) item.nextNumber = next;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  Text(
                    'Document numbering series',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: p.textPrimary,
                    ),
                  ),
                  const StatusBadge(
                    label: 'Pending server sync',
                    tone: StatusTone.neutral,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Prefixes and sequence padding for official receipts, sales, '
                'deliveries, purchase orders, and quotations.',
                style: TextStyle(fontSize: 12.5, color: p.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              for (var i = 0; i < _series.length; i++) ...[
                if (i > 0) Divider(height: 1, color: p.border),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _series[i].name,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: p.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Prefix: ${_series[i].prefix} · '
                              '${_series[i].digits} digits',
                              style: TextStyle(
                                fontSize: 12,
                                color: p.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: p.selected,
                          borderRadius: BorderRadius.circular(AppRadii.small),
                          border: Border.all(
                            color: p.accent.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Text(
                          _series[i].preview,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: p.accentInk,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      if (widget.canEdit) ...[
                        const SizedBox(width: AppSpacing.sm),
                        TextButton(
                          onPressed: () => _editSeries(_series[i]),
                          child: const Text('Edit'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Divider(height: 1, color: p.border),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reset sequence on fiscal year start',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: p.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Keep off for continuous Order Slip (OS) numbering.',
                          style: TextStyle(
                            fontSize: 12,
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _resetYearly,
                    onChanged: widget.canEdit
                        ? (v) => setState(() => _resetYearly = v)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Receipt & print template',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Header, tax line, and return policy printed on POS receipts.',
                style: TextStyle(fontSize: 12.5, color: p.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final size in const ['58mm', '80mm', 'A4 Invoice'])
                    ChoiceChip(
                      label: Text(size),
                      selected: _paperWidth == size,
                      backgroundColor: p.surfaceSunken,
                      selectedColor: p.selected,
                      checkmarkColor: p.accentInk,
                      side: BorderSide(
                        color: _paperWidth == size ? p.accent : p.border,
                      ),
                      labelStyle: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _paperWidth == size
                            ? p.accentInk
                            : p.textPrimary,
                      ),
                      onSelected: widget.canEdit
                          ? (_) => setState(() => _paperWidth = size)
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _headerLine,
                readOnly: !widget.canEdit,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Receipt header title',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _tinLine,
                readOnly: !widget.canEdit,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'TIN / Accreditation line',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _footerLine,
                readOnly: !widget.canEdit,
                maxLines: 2,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Receipt footer & return policy',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const DialogSectionLabel('Live receipt preview'),
              Container(
                key: const ValueKey('receipt-template-preview'),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: p.surfaceSunken,
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                  border: Border.all(color: p.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      _headerLine.text.trim().isEmpty
                          ? 'QUEEN BUILDERS'
                          : _headerLine.text.trim(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _tinLine.text.trim(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: p.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Paper: $_paperWidth  ·  ${_series.first.preview}',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: p.accentInk,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1, color: p.border),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '1x Portland Cement 40kg',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: p.textPrimary,
                          ),
                        ),
                        Text(
                          'PHP 260.00',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1, color: p.border),
                    ),
                    Text(
                      _footerLine.text.trim(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SeriesEditDialog extends StatefulWidget {
  const _SeriesEditDialog({required this.item, required this.onSaved});

  final _SeriesDraft item;
  final void Function(String prefix, int? nextNumber) onSaved;

  @override
  State<_SeriesEditDialog> createState() => _SeriesEditDialogState();
}

class _SeriesEditDialogState extends State<_SeriesEditDialog> {
  late final TextEditingController _prefixCtrl = TextEditingController(
    text: widget.item.prefix,
  );
  late final TextEditingController _nextCtrl = TextEditingController(
    text: '${widget.item.nextNumber}',
  );

  @override
  void dispose() {
    _prefixCtrl.dispose();
    _nextCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.tag_rounded,
      title: 'Edit ${widget.item.name} series',
      subtitle: 'Preview updates live; server sync applies once API is wired.',
      width: 440,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _prefixCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Prefix',
              hintText: 'e.g. OS-, TRX-',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _nextCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Next sequence number',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            widget.onSaved(
              _prefixCtrl.text.trim().toUpperCase(),
              int.tryParse(_nextCtrl.text.trim()),
            );
            Navigator.of(context).pop();
          },
          child: const Text('Apply preview'),
        ),
      ],
    );
  }
}
