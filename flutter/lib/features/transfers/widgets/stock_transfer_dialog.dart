import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/stock_transfer.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/features/transfers/viewmodels/transfers_viewmodel.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';

/// One selling unit a line may move: the unit the clerk counts in, its code and
/// whether the server insists on whole pieces.
///
/// The line is chosen at the SELLING-UNIT level, not the product's, because that
/// is what `POST /stock-transfers/` takes (`variant_uom` + `qty`) and what the
/// clerk actually counted: "2 BAG", not "24 PC".
typedef _SellingUnitOption = ({
  int variantUomId,
  String label,
  String unit,
  bool isWhole,
});

/// One line as the form holds it, before it becomes the wire body.
class _LineDraft {
  _LineDraft();

  final qty = TextEditingController();
  _SellingUnitOption? option;

  void dispose() => qty.dispose();
}

/// Record a move of stock from one shelf to another (Phase 9 F3, design 6).
///
/// Four things shape the form, and none of them is taste:
/// * the two ENDS are chosen first: stock leaves one shelf and lands on another,
///   so the same shelf twice is refused before a request is spent;
/// * only an ACTIVE shelf is offered as a destination (Design 11) — the server
///   answers `INVALID_STORAGE_LOCATION`, and a picker that offers it only teaches
///   the clerk to guess. A DEACTIVATED shelf stays selectable as a SOURCE,
///   because moving stock OUT of a closed shelf is exactly how it is emptied;
/// * every quantity is in the line's SELLING unit, which is the unit the clerk
///   counted and the unit the server converts from; a whole unit refuses a
///   fraction here so the identical refusal does not need a round trip;
/// * a refusal arrives as the server's own sentence (which shelf, how short)
///   and the form STAYS OPEN with every typed value, because retyping a slip is
///   how the same stock gets moved twice.
class StockTransferDialog extends StatefulWidget {
  const StockTransferDialog({
    super.key,
    required this.viewmodel,
    required this.locations,
    required this.products,
  });

  final TransfersViewmodel viewmodel;

  /// Every shelf the caller may see: the ACTIVE ones are offered as a
  /// destination, and all of them (a deactivated one included) as a source.
  final List<StorageLocation> locations;
  final List<Product> products;

  @override
  State<StockTransferDialog> createState() => _StockTransferDialogState();
}

class _StockTransferDialogState extends State<StockTransferDialog> {
  final _formKey = GlobalKey<FormState>();
  final _remarks = TextEditingController();
  final List<_LineDraft> _lines = [_LineDraft()];

  int? _fromId;
  int? _toId;
  bool _submitting = false;
  String? _refusal;

  /// The selling units of every ACTIVE product and variant: an archived one
  /// cannot be moved (`INACTIVE_SELLING_UNIT`), so it is not offered.
  late final List<_SellingUnitOption> _options = [
    for (final product in widget.products)
      if (product.isActive)
        for (final variant in product.variants)
          if (variant.isActive)
            for (final uom in variant.sellingUoms)
              (
                variantUomId: uom.id,
                label:
                    '${product.baseName} · ${variant.variantName} · '
                    '${uom.uomCode}',
                unit: uom.uomCode,
                isWhole: uom.uomIsWhole,
              ),
  ];

  List<StorageLocation> get _destinations => [
    for (final location in widget.locations)
      if (location.isActive) location,
  ];

  @override
  void dispose() {
    _remarks.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _addLine() => setState(() => _lines.add(_LineDraft()));

  void _removeLine(_LineDraft line) {
    setState(() {
      _lines.remove(line);
      if (_lines.isEmpty) _lines.add(_LineDraft());
    });
    line.dispose();
  }

  Future<void> _submit() async {
    // One slip at a time: a double click would move the stock twice, and the
    // viewmodel refuses the second attempt too.
    if (_submitting || widget.viewmodel.isRecording) return;

    final from = _fromId;
    final to = _toId;
    if (from == null || to == null) {
      setState(
        () => _refusal =
            'Choose the shelf the stock leaves and the shelf it '
            'lands on.',
      );
      return;
    }
    if (from == to) {
      setState(
        () => _refusal =
            'Stock must leave one shelf and land on another: '
            'choose two different shelves.',
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final lines = <({int variantUomId, double qty})>[
      for (final line in _lines)
        if (line.option != null)
          (
            variantUomId: line.option!.variantUomId,
            qty: double.parse(line.qty.text.trim()),
          ),
    ];
    if (lines.isEmpty) {
      setState(
        () => _refusal = 'Add at least one line: the lines are the slip.',
      );
      return;
    }

    setState(() {
      _submitting = true;
      _refusal = null;
    });
    final outcome = await widget.viewmodel.record(
      StockTransferRequest(
        fromLocationId: from,
        toLocationId: to,
        remarks: _remarks.text,
        lines: lines,
      ),
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    final recorded = outcome.recorded;
    if (recorded != null) {
      Navigator.pop(context, recorded);
      return;
    }
    setState(() => _refusal = outcome.refusal);
  }

  @override
  Widget build(BuildContext context) {
    final busy = _submitting || widget.viewmodel.isRecording;
    return AppDialog(
      icon: Icons.swap_horiz_rounded,
      title: 'Record a transfer',
      subtitle: 'The stock moves at once, with a numbered slip.',
      width: 720,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _shelfField(isFrom: true)),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: _shelfField(isFrom: false)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const ValueKey('transfer-remarks'),
              controller: _remarks,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Remarks',
                hintText: 'Why is the stock moving?',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Lines — counted in the unit you enter',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('transfer-add-line'),
                  onPressed: _addLine,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add line'),
                ),
              ],
            ),
            for (var index = 0; index < _lines.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _lineRow(index, _lines[index]),
              ),
            if (_refusal case final refusal?) ...[
              const SizedBox(height: AppSpacing.md),
              ErrorBanner(
                key: const ValueKey('transfer-refusal'),
                message: refusal,
                onRetry: () => setState(() => _refusal = null),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const ValueKey('transfer-submit'),
          onPressed: busy ? null : _submit,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Move stock'),
        ),
      ],
    );
  }

  Widget _shelfField({required bool isFrom}) {
    final rows = isFrom ? widget.locations : _destinations;
    return DropdownButtonFormField<int>(
      key: ValueKey(isFrom ? 'transfer-from' : 'transfer-to'),
      isExpanded: true,
      initialValue: isFrom ? _fromId : _toId,
      decoration: InputDecoration(
        labelText: isFrom ? 'From shelf' : 'To shelf',
        helperText: isFrom
            ? 'Stock leaves here'
            : 'Only active shelves take stock',
      ),
      items: [
        for (final location in rows)
          DropdownMenuItem(
            value: location.id,
            child: Text(location.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) => setState(() {
        if (isFrom) {
          _fromId = value;
        } else {
          _toId = value;
        }
      }),
      validator: (value) => value == null
          ? (isFrom
                ? 'Choose the source shelf.'
                : 'Choose the destination shelf.')
          : null,
    );
  }

  Widget _lineRow(int index, _LineDraft line) {
    final option = line.option;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: DropdownButtonFormField<_SellingUnitOption>(
            key: ValueKey('transfer-line-uom-$index'),
            isExpanded: true,
            initialValue: option,
            decoration: const InputDecoration(labelText: 'What moves'),
            items: [
              for (final entry in _options)
                DropdownMenuItem(
                  value: entry,
                  child: Text(entry.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) => setState(() => line.option = value),
            validator: (value) =>
                value == null ? 'Pick the product and its unit.' : null,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 150,
          child: TextFormField(
            key: ValueKey('transfer-line-qty-$index'),
            controller: line.qty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Quantity',
              suffixText: option?.unit,
            ),
            validator: (_) {
              final picked = line.option;
              if (picked == null) return 'Pick the unit first.';
              final parsed = double.tryParse(line.qty.text.trim());
              if (parsed == null || parsed <= 0) {
                return 'Enter a quantity above zero.';
              }
              if (picked.isWhole && parsed != parsed.roundToDouble()) {
                return 'Counted in whole ${picked.unit}.';
              }
              return null;
            },
          ),
        ),
        IconButton(
          key: ValueKey('transfer-line-remove-$index'),
          tooltip: 'Remove line',
          onPressed: _lines.length == 1 ? null : () => _removeLine(line),
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
      ],
    );
  }
}
