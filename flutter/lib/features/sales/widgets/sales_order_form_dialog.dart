import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/format/money_input.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:client/data/models/catalogue_item.dart';
import 'package:client/data/models/customer.dart';
import 'package:client/data/models/delivery.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';

/// Raise ONE sales order (Phase 5 F3 follow-up, owner-authorised).
///
/// Create-only, and that is the whole of it: there is no status control, no edit
/// and no fulfil-to-sale action here, because no such route exists in this build.
/// The server writes the order as CONFIRMED and the client never sends a status.
///
/// Everything it shows comes from what the page passes in: the customers the
/// sales module loaded and the live catalogue (so a line is counted and priced in
/// a SELLING unit, `variant_uom`, exactly as the till does). Two rules are checked
/// here rather than left to the server, because both refusals are cheap to make
/// and expensive to discover after a round trip:
///   * a whole unit takes a whole number of units (`WHOLE_UNIT_QUANTITY`);
///   * a fee is money at two decimals — `10.005` is REFUSED by the server, not
///     rounded, and a zero fee is allowed.
///
/// [onSubmit] returns null when the order was created, or the sentence to show.
/// It is awaited, so the button is disabled for exactly as long as the request
/// runs and a second tap cannot post twice. A refusal keeps this dialog OPEN with
/// every input intact: what the clerk typed is the thing being corrected.
class SalesOrderFormDialog extends StatefulWidget {
  const SalesOrderFormDialog({
    super.key,
    required this.customers,
    required this.catalogue,
    required this.onSubmit,
  });

  /// The accounts an order can be raised for. The Walk-in placeholder is not one
  /// of them: an order is a promise to a named customer.
  final List<Customer> customers;

  /// One row per (variant, selling unit) — the same catalogue the till sells from.
  final List<CatalogueItem> catalogue;

  final Future<String?> Function(SalesOrderDraft draft) onSubmit;

  @override
  State<SalesOrderFormDialog> createState() => _SalesOrderFormDialogState();
}

/// One line being typed. [unit] is chosen from the catalogue, so its price is the
/// price the shop charges for that unit unless the clerk overrides it.
class _OrderLineForm {
  _OrderLineForm(this.item)
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

class _SalesOrderFormDialogState extends State<SalesOrderFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _notes = TextEditingController();

  final _deliveryAddress = TextEditingController();
  final _deliveryContact = TextEditingController();
  final _deliveryPhone = TextEditingController();
  final _deliveryFee = TextEditingController(text: '0.00');

  final List<_OrderLineForm> _lines = [];

  int? _customerId;
  bool _deliver = false;

  /// The day the goods go out. Defaults to tomorrow, like the till's Deliver
  /// section: a delivery is arranged for a later day, never for right now.
  DateTime? _deliveryDate;

  String? _refusal;
  bool _submitting = false;

  /// What an order may promise: the till's rule, so an archived product or
  /// variant is never offered (or preselected as the first line).
  late final List<CatalogueItem> _offered = [
    for (final item in widget.catalogue)
      if (item.product.isActive && item.variant.isActive) item,
  ];

  @override
  void initState() {
    super.initState();
    if (_offered.isNotEmpty) _lines.add(_OrderLineForm(_offered.first));
  }

  @override
  void dispose() {
    _notes.dispose();
    _deliveryAddress.dispose();
    _deliveryContact.dispose();
    _deliveryPhone.dispose();
    _deliveryFee.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  /// The catalogue row behind a line's chosen unit.
  CatalogueItem? _itemFor(int unitId) {
    for (final item in _offered) {
      if (item.uom.id == unitId) return item;
    }
    return null;
  }

  /// The customers an order can be raised for: named accounts only.
  List<Customer> get _namedCustomers => [
    for (final c in widget.customers)
      if (!c.isWalkIn) c,
  ];

  double get _goodsTotal {
    var total = 0.0;
    for (final line in _lines) {
      total +=
          (double.tryParse(line.qty.text.trim()) ?? 0) *
          (double.tryParse(line.price.text.trim()) ?? 0);
    }
    return total;
  }

  double get _fee =>
      _deliver ? (double.tryParse(_deliveryFee.text.trim()) ?? 0) : 0;

  void _addLine() {
    if (_offered.isEmpty) return;
    setState(() => _lines.add(_OrderLineForm(_offered.first)));
  }

  void _removeLine(int index) {
    final line = _lines.removeAt(index);
    line.dispose();
    setState(() {});
  }

  /// Switching a line's unit moves its price to that unit's catalogue price: a
  /// per-kilo price must not survive as a per-bag one.
  void _changeUnit(_OrderLineForm line, int unitId) {
    final item = _itemFor(unitId);
    if (item == null) return;
    setState(() {
      line.unitId = unitId;
      line.price.text = item.uom.defaultSellingPrice.toStringAsFixed(2);
    });
  }

  void _setDeliver(bool value) {
    setState(() {
      _deliver = value;
      if (value && _deliveryDate == null) {
        final now = appClock.now();
        _deliveryDate = DateTime(now.year, now.month, now.day + 1);
      }
    });
  }

  Future<void> _pickDeliveryDate() async {
    final now = appClock.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deliveryDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
      currentDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() => _deliveryDate = picked);
  }

  Future<void> _submit() async {
    // A second tap while a request is in flight would post the same order twice.
    if (_submitting) return;
    setState(() => _refusal = null);
    if (!_formKey.currentState!.validate()) return;
    if (_lines.isEmpty) {
      setState(() => _refusal = _noLines);
      return;
    }

    final draft = SalesOrderDraft(
      customerId: _customerId!,
      notes: _notes.text.trim(),
      lines: [
        for (final line in _lines)
          SalesOrderLineDraft(
            variantUomId: line.unitId,
            qty: double.parse(line.qty.text.trim()),
            unitPrice: double.parse(line.price.text.trim()),
          ),
      ],
      delivery: _deliver
          ? DeliveryDraft(
              address: _deliveryAddress.text.trim(),
              contactName: _deliveryContact.text.trim(),
              contactPhone: _deliveryPhone.text.trim(),
              scheduledDate: _deliveryDate ?? _tomorrow(),
              fee: _fee,
            )
          : null,
    );

    setState(() => _submitting = true);
    final error = await widget.onSubmit(draft);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _submitting = false;
      _refusal = error;
    });
  }

  static DateTime _tomorrow() {
    final now = appClock.now();
    return DateTime(now.year, now.month, now.day + 1);
  }

  static const String _noLines =
      'An order needs at least one line. Add one from the catalogue.';

  @override
  Widget build(BuildContext context) {
    final noCatalogue = _offered.isEmpty;
    final noCustomers = _namedCustomers.isEmpty;

    return AppDialog(
      icon: Icons.assignment_outlined,
      title: 'New sales order',
      subtitle: 'Raise the order now; the store confirms it as it is prepared.',
      width: 640,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const FormStepHeader(step: 1, title: 'Who is the order for?'),
            DropdownButtonFormField<int>(
              key: const ValueKey('so-customer'),
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
              validator: (value) => value == null ? 'Choose a customer.' : null,
              onChanged: (value) => setState(() => _customerId = value),
            ),
            if (noCustomers)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  'No customer accounts have loaded, so there is nobody to '
                  'raise an order for. Close this and try again.',
                ),
              ),
            const SizedBox(height: AppSpacing.xl),
            FormStepHeader(step: 2, title: 'What are they ordering?'),
            if (noCatalogue)
              const Text(
                'The catalogue has not loaded, so there is nothing to order. '
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
                  onPressed: _addLine,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add line'),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              key: const ValueKey('so-notes'),
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'Optional instructions for this order',
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FormStepHeader(step: 3, title: 'Deliver it?'),
            _deliverySection(),
            const SizedBox(height: AppSpacing.lg),
            TotalBar(label: 'Goods total', amount: _goodsTotal),
            // The fee is NOT in that total: it lives on the delivery row and is
            // never discounted, so adding it here would invent a second total.
            if (_deliver)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  'Delivery charge ${formatPeso(_fee)}, charged on the slip.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
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
          key: const ValueKey('so-submit'),
          onPressed: _submitting || noCatalogue || noCustomers ? null : _submit,
          child: Text(_submitting ? 'Creating…' : 'Create order'),
        ),
      ],
    );
  }

  /// The unit picker, the count and the price for one line.
  Widget _lineCard(int index, _OrderLineForm line) {
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
                  key: ValueKey('so-remove-$index'),
                  tooltip: 'Remove line',
                  onPressed: () => _removeLine(index),
                  icon: const Icon(Icons.close, size: 18),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<int>(
            key: ValueKey('so-unit-$index'),
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
                  key: ValueKey('so-qty-$index'),
                  controller: line.qty,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    suffixText: code,
                    isDense: true,
                    // Keep the whole-unit refusal readable in narrow, scaled layouts.
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
                  key: ValueKey('so-price-$index'),
                  controller: line.price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Price per $code',
                    prefixText: '₱ ',
                    isDense: true,
                    // A half-width column at 760 px would ellipsize the refusal.
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

  /// The Deliver section: off by default, and every field required once it is on
  /// (the server refuses a partial delivery with `INVALID_DELIVERY`).
  Widget _deliverySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('so-deliver-toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Deliver to the customer'),
          subtitle: const Text(
            'The charge is stored on the delivery, after any discount.',
          ),
          value: _deliver,
          onChanged: _setDeliver,
        ),
        if (_deliver) ...[
          TextFormField(
            key: const ValueKey('so-delivery-address'),
            controller: _deliveryAddress,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Delivery address'),
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'A delivery needs an address.'
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('so-delivery-contact'),
                  controller: _deliveryContact,
                  decoration: const InputDecoration(labelText: 'Contact name'),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'A delivery needs a contact name.'
                      : null,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('so-delivery-phone'),
                  controller: _deliveryPhone,
                  decoration: const InputDecoration(labelText: 'Contact phone'),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'A delivery needs a contact phone number.'
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('so-delivery-date'),
                  onPressed: _pickDeliveryDate,
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(
                    _deliveryDate == null
                        ? 'Delivery date'
                        : formatDate(_deliveryDate!),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('so-delivery-fee'),
                  controller: _deliveryFee,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Delivery fee',
                    // Same half-width column as the price: the refusal must fit.
                    errorMaxLines: 4,
                  ),
                  validator: _moneyError,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ],
      ],
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

  /// A price or a fee: money at two decimals, never negative. `10.005` is refused
  /// by the server rather than rounded, so it is refused here with the same
  /// sentence the cashier has to correct. The rule itself is shared with the till
  /// (item 10); only this screen's wording lives here.
  static String? _moneyError(String? value) =>
      switch (moneyInputProblem(value)) {
        MoneyInputProblem.notAnAmount => 'Enter an amount, 0 or more.',
        MoneyInputProblem.moreThanTwoDecimals => 'At most two decimals.',
        null => null,
      };

  static final RegExp _twoDecimals = RegExp(r'^\d+(\.\d{1,2})?$');
}
