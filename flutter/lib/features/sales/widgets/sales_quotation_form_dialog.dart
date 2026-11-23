import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/format/money_input.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:client/data/models/catalogue_item.dart';
import 'package:client/data/models/customer.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';

/// Raise ONE quotation (`POST /api/v1/quotations/`).
///
/// Deliberately smaller than [SalesOrderFormDialog]: a quotation has no delivery,
/// no fulfilment and no cap guard on the server, so it collects a customer, the
/// lines and the day the price stops holding. The lines name a SELLING unit
/// (`variant_uom`) and default to that unit's catalogue price — the same unit and
/// price the till would charge, so a quotation cannot quote something the shop
/// does not sell.
///
/// [onSubmit] returns the number the server generated, or the refusal; it is
/// awaited, so the button is disabled for exactly as long as the request runs and
/// a second tap cannot post twice. A refusal keeps this dialog OPEN with every
/// input intact: what the clerk typed is the thing being corrected.
class SalesQuotationFormDialog extends StatefulWidget {
  const SalesQuotationFormDialog({
    super.key,
    required this.customers,
    required this.catalogue,
    required this.onSubmit,
  });

  /// The accounts a quotation can be raised for. The Walk-in placeholder is not
  /// one of them: a quotation is a price promised to a named customer.
  final List<Customer> customers;

  /// One row per (variant, selling unit) — the same catalogue the till sells from.
  final List<CatalogueItem> catalogue;

  /// Returns the created quotation's number, or the server's refusal.
  final Future<(String?, SalesServiceException?)> Function(QuotationDraft draft)
  onSubmit;

  @override
  State<SalesQuotationFormDialog> createState() =>
      _SalesQuotationFormDialogState();
}

class _QuotationLineForm {
  _QuotationLineForm(this.item)
    : unitId = item.uom.id,
      qty = TextEditingController(text: '1'),
      price = TextEditingController(
        text: item.uom.defaultSellingPrice.toStringAsFixed(2),
      );

  final CatalogueItem item;
  int unitId;
  final TextEditingController qty;
  final TextEditingController price;

  void dispose() {
    qty.dispose();
    price.dispose();
  }
}

class _SalesQuotationFormDialogState extends State<SalesQuotationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final List<_QuotationLineForm> _lines = [];

  int? _customerId;

  /// The day the quoted price stops holding. A month out by default: a
  /// quotation with no expiry reads as "Expired" from the day after it was
  /// written, and the list has no way to tell the two apart.
  DateTime? _validUntil;

  String? _refusal;
  bool _submitting = false;

  /// What a quotation may promise: the till's rule, so an archived product or
  /// variant is never offered (or preselected as the first line).
  late final List<CatalogueItem> _offered = [
    for (final item in widget.catalogue)
      if (item.product.isActive && item.variant.isActive) item,
  ];

  @override
  void initState() {
    super.initState();
    final now = appClock.now();
    _validUntil = DateTime(now.year, now.month, now.day + 30);
    if (_offered.isNotEmpty) _lines.add(_QuotationLineForm(_offered.first));
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  /// The customers a quotation can be raised for: named accounts only.
  List<Customer> get _namedCustomers => [
    for (final c in widget.customers)
      if (!c.isWalkIn) c,
  ];

  CatalogueItem? _itemFor(int unitId) {
    for (final item in _offered) {
      if (item.uom.id == unitId) return item;
    }
    return null;
  }

  double get _total {
    var total = 0.0;
    for (final line in _lines) {
      total +=
          (double.tryParse(line.qty.text.trim()) ?? 0) *
          (double.tryParse(line.price.text.trim()) ?? 0);
    }
    return total;
  }

  void _addLine() {
    if (_offered.isEmpty) return;
    setState(() => _lines.add(_QuotationLineForm(_offered.first)));
  }

  void _removeLine(int index) {
    final line = _lines.removeAt(index);
    line.dispose();
    setState(() {});
  }

  /// Switching a line's unit moves its price to that unit's catalogue price: a
  /// per-kilo price must not survive as a per-bag one.
  void _changeUnit(_QuotationLineForm line, int unitId) {
    final item = _itemFor(unitId);
    if (item == null) return;
    setState(() {
      line.unitId = unitId;
      line.price.text = item.uom.defaultSellingPrice.toStringAsFixed(2);
    });
  }

  Future<void> _pickValidUntil() async {
    final now = appClock.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _validUntil ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
      currentDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() => _validUntil = picked);
  }

  Future<void> _submit() async {
    // A second tap while a request is in flight would post the same quotation
    // twice.
    if (_submitting) return;
    setState(() => _refusal = null);
    if (!_formKey.currentState!.validate()) return;
    if (_lines.isEmpty) {
      setState(() => _refusal = _noLines);
      return;
    }

    setState(() => _submitting = true);
    final (number, refusal) = await widget.onSubmit(
      QuotationDraft(
        customerId: _customerId!,
        validUntil: _validUntil,
        lines: [
          for (final line in _lines)
            SalesOrderLineDraft(
              variantUomId: line.unitId,
              qty: double.parse(line.qty.text.trim()),
              unitPrice: double.parse(line.price.text.trim()),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (number != null) {
      Navigator.pop(context, number);
      return;
    }
    setState(() {
      _submitting = false;
      _refusal = refusal?.message;
    });
  }

  static const String _noLines =
      'A quotation needs at least one line. Add one from the catalogue.';

  @override
  Widget build(BuildContext context) {
    final noCatalogue = _offered.isEmpty;
    final noCustomers = _namedCustomers.isEmpty;

    return AppDialog(
      icon: Icons.request_quote_outlined,
      title: 'New quotation',
      subtitle: 'Quote the price now; it becomes an order when they accept.',
      width: 640,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const FormStepHeader(step: 1, title: 'Who is it for?'),
            DropdownButtonFormField<int>(
              key: const ValueKey('sq-customer'),
              isExpanded: true,
              initialValue: _customerId,
              decoration: const InputDecoration(labelText: 'Customer'),
              items: [
                for (final customer in _namedCustomers)
                  DropdownMenuItem(
                    value: customer.id,
                    child: Text(customer.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              validator: (value) =>
                  value == null ? 'Choose a customer.' : null,
              onChanged: (value) => setState(() => _customerId = value),
            ),
            if (noCustomers)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  'No customer accounts have loaded, so there is nobody to '
                  'quote. Close this and try again.',
                ),
              ),
            const SizedBox(height: AppSpacing.xl),
            const FormStepHeader(step: 2, title: 'What is being quoted?'),
            if (noCatalogue)
              const Text(
                'The catalogue has not loaded, so there is nothing to quote. '
                'Close this and try again.',
              )
            else ...[
              for (var index = 0; index < _lines.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _lineCard(index, _lines[index]),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('sq-add-line'),
                  onPressed: _addLine,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add line'),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('sq-valid-until'),
                onPressed: _submitting ? null : _pickValidUntil,
                icon: const Icon(Icons.event, size: 18),
                label: Text(
                  'Valid until ${_validUntil == null ? 'not set' : formatDate(_validUntil!)}',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TotalBar(label: 'Quotation total', amount: _total),
            if (_refusal case final refusal?) ...[
              const SizedBox(height: AppSpacing.lg),
              ErrorBanner(message: refusal),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('sq-submit'),
          onPressed: _submitting || noCatalogue || noCustomers ? null : _submit,
          child: Text(_submitting ? 'Creating…' : 'Create quotation'),
        ),
      ],
    );
  }

  /// The unit picker, the count and the price for one line.
  Widget _lineCard(int index, _QuotationLineForm line) {
    // The chosen unit decides the product, so the heading follows it.
    final chosen = _itemFor(line.unitId) ?? line.item;
    final unit = chosen.uom;
    final code = unit.uomCode;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  chosen.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (index > 0)
                IconButton(
                  key: ValueKey('sq-remove-$index'),
                  tooltip: 'Remove line',
                  onPressed: () => _removeLine(index),
                  icon: const Icon(Icons.close, size: 18),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<int>(
            key: ValueKey('sq-unit-$index'),
            isExpanded: true,
            initialValue: line.unitId,
            decoration: const InputDecoration(labelText: 'Unit', isDense: true),
            items: [
              for (final item in _offered)
                DropdownMenuItem(
                  value: item.uom.id,
                  // Each row is one product's unit: the code alone hides which.
                  child: Text(
                    '${item.displayName} · ${item.uom.uomCode} (${item.uom.uomName})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) _changeUnit(line, value);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('sq-qty-$index'),
                  controller: line.qty,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    suffixText: code,
                    isDense: true,
                    // Keep the whole-unit refusal readable in narrow layouts.
                    errorMaxLines: 4,
                  ),
                  validator: (value) =>
                      _quantityError(unit.uomIsWhole, code, value),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextFormField(
                  key: ValueKey('sq-price-$index'),
                  controller: line.price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Price per $code',
                    prefixText: '₱ ',
                    isDense: true,
                    errorMaxLines: 4,
                  ),
                  validator: _moneyError,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The count a line may take, checked against its OWN unit: a whole unit takes
  /// whole numbers (the server's `WHOLE_UNIT_QUANTITY`), a measured one takes the
  /// two decimals the quantity field stores.
  static String? _quantityError(bool isWhole, String code, String? value) {
    final text = (value ?? '').trim();
    final parsed = double.tryParse(text);
    if (parsed == null || parsed <= 0) return 'Enter a quantity above 0.';
    if (isWhole && parsed != parsed.roundToDouble()) {
      return '$code is sold in whole numbers. Enter a whole number.';
    }
    if (!isWhole && !_twoDecimals.hasMatch(text)) {
      return 'At most two decimals.';
    }
    return null;
  }

  /// A price: money at two decimals, never negative. The rule is shared with the
  /// till and the order form (`moneyInputProblem`); only the wording lives here.
  static String? _moneyError(String? value) =>
      switch (moneyInputProblem(value)) {
        MoneyInputProblem.notAnAmount => 'Enter an amount, 0 or more.',
        MoneyInputProblem.moreThanTwoDecimals => 'At most two decimals.',
        null => null,
      };

  static final RegExp _twoDecimals = RegExp(r'^\d+(\.\d{1,2})?$');
}
