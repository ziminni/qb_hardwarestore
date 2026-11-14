import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/product_writes.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/services/image_file_service.dart';
import 'package:client/features/products/widgets/products_image.dart';
import 'package:client/features/products/widgets/selling_unit_fields.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';

/// What the product form produced: a creation draft, or an edit draft.
///
/// One dialog, two payloads, because the two writes are genuinely different: a
/// create is a chain of POSTs that cannot exist without a category, a brand and a
/// base unit, while an edit is a set of PATCHes over rows that already have ids.
class ProductFormResult {
  const ProductFormResult.create(NewProductDraft this.draft) : edit = null;
  const ProductFormResult.edit(ProductEditDraft this.edit) : draft = null;

  final NewProductDraft? draft;
  final ProductEditDraft? edit;
}

/// The product dialog: how a product is catalogued, how it is sold, and how much
/// stock to warn about.
///
/// Three steps, in the order a stock manager answers them (decision 15):
///
///  1. **Basic information**: name, variant, code, category, brand, description.
///  2. **How is this product sold?**: the base unit and its price, plus the extra
///     selling units ("Bag = 40 kg at ₱270"). Each extra unit becomes a real
///     `VariantUOM` row with its own price and code; the base unit is frozen once
///     the product exists because the server refuses to change it.
///  3. **Stock levels**: the reorder and maximum levels, and the storage
///     location, which lives on THIS device: the server has no location field.
///
/// There is still **no opening stock and no cost**: user decision 2026-10-25, a
/// product's first stock arrives through a purchase order that is then received.
class ProductsFormDialog extends StatefulWidget {
  const ProductsFormDialog({
    super.key,
    required this.categories,
    required this.brands,
    required this.units,
    required this.products,
    this.product,
    this.locationHint = '',
    this.storageLocations = const [],
    this.storageLocationError,
  });

  final List<Category> categories;
  final List<Brand> brands;
  final List<UnitOfMeasure> units;
  final List<Product> products;
  final Product? product;

  /// Where this device says the stock sits. Blank on a product nobody recorded.
  final String locationHint;

  /// The shop's pick-up points as the SERVER answered (Phase 5 B4). Active rows
  /// are offered; the product's own (possibly inactive) one stays visible.
  final List<StorageLocation> storageLocations;

  /// Why the list is not trustworthy, or null.
  ///
  /// A failed read must not become a blank picker that quietly submits the
  /// server's default: the form refuses to create a product until the clerk has
  /// seen a real list (see [_submit]).
  final String? storageLocationError;

  @override
  State<ProductsFormDialog> createState() => _ProductsFormDialogState();
}

class _ProductsFormDialogState extends State<ProductsFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _variantController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _reorderController;
  late final TextEditingController _maxController;
  late final TextEditingController _sellingController;
  late final TextEditingController _locationController;
  int? _categoryId;
  int? _brandId;
  int? _baseUomId;
  late String _imagePath;

  /// The SERVER pick-up point this product is stored at (Phase 5 B4).
  int? _storedAtId;

  /// True once the clerk picked a location themselves (item 12).
  ///
  /// A legacy product has no stored id, so the form pre-fills the Store default
  /// for it; comparing ids alone cannot tell that prefill from a real choice.
  bool _storedAtTouched = false;

  final List<SellingUnitDraft> _extraUnits = [];
  final _imageFileService = const ImageFileService();

  bool get _editing => widget.product != null;

  ProductVariant? get _variant => widget.product?.variants.firstOrNull;

  /// The base unit's code, which the price label and every helper print.
  ///
  /// On an edit it comes from the variant (the server's truth, frozen); on a
  /// create from the picker's current choice.
  String get _baseCode {
    if (_editing) return _variant?.baseUomCode ?? '';
    return _unitWithId(_baseUomId)?.code ?? '';
  }

  UnitOfMeasure? _unitWithId(int? id) {
    for (final unit in widget.units) {
      if (unit.id == id) return unit;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    final variant = _variant;
    _nameController = TextEditingController(text: product?.baseName ?? '');
    _descriptionController = TextEditingController(
      text: product?.description ?? '',
    );
    _variantController = TextEditingController(
      text: variant?.variantName ?? 'Standard',
    );
    // The BASE unit's code, not the variant's first non-blank one: this field
    // writes the factor-1 selling unit, and `variant.barcode` may belong to the
    // box (Phase 6 decisions 11 F3 and 18).
    _barcodeController = TextEditingController(text: _baseUnitCode(variant));
    _reorderController = TextEditingController(
      text: formatQuantity(variant?.minStockThreshold ?? 0),
    );
    _maxController = TextEditingController(
      text: formatQuantity(variant?.maxStockLevel ?? 0),
    );
    _sellingController = TextEditingController(
      // The charged price is the base SELLING UNIT's, never the batch's and never
      // a package's (decision 08).
      text: formatQuantity(_baseSellingUnit(variant)?.defaultSellingPrice ?? 0),
    );
    _locationController = TextEditingController(text: widget.locationHint);
    _categoryId = product?.categoryId ?? widget.categories.firstOrNull?.id;
    _brandId = product?.brandId ?? widget.brands.firstOrNull?.id;
    _baseUomId = variant?.baseUomId ?? widget.units.firstOrNull?.id;
    _imagePath = product?.imageUrl ?? '';
    _storedAtId = product?.storedAtId ?? _defaultStoredAtId();
  }

  /// What a NEW product is stored at: the row NAMED **Store**, which is the
  /// server's own default.
  ///
  /// Resolved by the name the API returned, not by a hardcoded primary key and
  /// not by list order — a second location created first would otherwise become
  /// the default. Null when the list holds no Store (or could not be read), and
  /// the field then makes the clerk choose instead of guessing.
  int? _defaultStoredAtId() {
    for (final location in widget.storageLocations) {
      if (location.isActive && location.name.toLowerCase() == 'store') {
        return location.id;
      }
    }
    return null;
  }

  /// The locations the picker offers.
  ///
  /// Every ACTIVE one, plus this product's own place when it is inactive or no
  /// longer listed: the goods did not move just because the shop stopped using
  /// the name, so an edit must show that location — and keep it selected —
  /// rather than silently re-point the product at Store.
  List<StorageLocation> get _storedAtOptions {
    final options = [
      for (final location in widget.storageLocations)
        if (location.isActive) location,
    ];
    final currentId = widget.product?.storedAtId;
    if (currentId != null && !options.any((l) => l.id == currentId)) {
      options.add(
        StorageLocation(
          id: currentId,
          name: widget.product!.storedAtName,
          isActive: false,
        ),
      );
    }
    return options;
  }

  /// `Bodega`, marked when the server no longer offers it. A location with no
  /// name on the wire (a legacy row) says what it is instead of showing a blank.
  String _storedAtLabel(StorageLocation location) {
    final name = location.name.trim();
    final label = name.isEmpty ? 'Unnamed location' : name;
    return location.isActive ? label : '$label (inactive)';
  }

  /// True when the clerk changed the product's location.
  ///
  /// A null original id (a legacy product) is changeable too — it just needs an
  /// explicit pick, so the pre-filled Store default is never silently written.
  bool get _storedAtChanged =>
      _storedAtTouched && _storedAtId != widget.product?.storedAtId;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _variantController.dispose();
    _barcodeController.dispose();
    _reorderController.dispose();
    _maxController.dispose();
    _sellingController.dispose();
    _locationController.dispose();
    for (final row in _extraUnits) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _selectImage() async {
    final path = await _imageFileService.selectImage();
    if (!mounted || path == null) return;
    setState(() => _imagePath = path);
  }

  /// The selling unit that IS the base unit: the variant's own `base_uom` at
  /// factor 1.
  ///
  /// List order is not identity. Once a product is sold by the bag the server
  /// may answer `[BAG (factor 40), KG (factor 1)]`, so `firstOrNull` would price
  /// a field labelled "per KG" with the bag's money and PATCH the bag's row.
  VariantUom? _baseSellingUnit(ProductVariant? variant) {
    if (variant == null) return null;
    for (final unit in variant.sellingUoms) {
      if (unit.uomId == variant.baseUomId && unit.conversionFactor == 1) {
        return unit;
      }
    }
    return null;
  }

  /// The factor-1 selling unit's code: the unit this form writes.
  ///
  /// `variant.barcode` answers with the variant's FIRST non-blank code, which may
  /// be the box's; the form PATCHes the base unit, so it must show that one.
  String _baseUnitCode(ProductVariant? variant) {
    final base = _baseSellingUnit(variant);
    if (base != null) return base.barcodeQr;
    return variant?.barcode ?? '';
  }

  void _addExtraUnit() {
    setState(() => _extraUnits.add(SellingUnitDraft()));
  }

  void _removeExtraUnit(int index) {
    setState(() => _extraUnits.removeAt(index).dispose());
  }

  // --- The server's rules, checked before the POST chain starts -------------
  //
  // `VariantUOM.conversion_factor` is 2 decimal places with a 0.01 minimum, a
  // unit can appear once per variant, and a second factor-1 unit is refused
  // (`INVALID_SELLING_UNIT` / `DUPLICATE_BASE_UNIT`). Catching all three here
  // means the clerk does not find out after the product row already exists.

  /// How many decimals a typed number has: `40` is 0, `40.25` is 2.
  String? _validateFactor(String? raw) =>
      sellingUnitFactorError(raw, baseCode: _baseCode);

  String? _validateUnit(int index, int? value) => sellingUnitUnitError(
    value,
    baseUomId: _baseUomId,
    usedUomIds: [
      for (var i = 0; i < _extraUnits.length; i++)
        if (i != index) _extraUnits[i].uomId,
    ],
  );

  static String? _validatePrice(String? raw) {
    final value = double.tryParse(raw?.trim() ?? '');
    if (value == null) return 'Enter a price.';
    if (value < 0) return 'The price cannot be negative.';
    return null;
  }

  /// The base price field also refuses when there is no base row to price, so a
  /// missing row never turns into a PATCH against some package instead.
  String? _validateBasePrice(String? raw) {
    if (_editing && _baseSellingUnit(_variant) == null) {
      return 'This product has no base selling unit to price.';
    }
    return _validatePrice(raw);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final price = double.tryParse(_sellingController.text.trim()) ?? 0;
    final threshold = double.tryParse(_reorderController.text.trim()) ?? 0;
    final maxLevel = double.tryParse(_maxController.text.trim()) ?? 0;
    final barcode = _barcodeController.text.trim();
    final location = _locationController.text.trim();

    final existing = widget.product;
    if (existing == null) {
      Navigator.of(context).pop(
        ProductFormResult.create(
          NewProductDraft(
            categoryId: _categoryId!,
            brandId: _brandId!,
            baseName: _nameController.text.trim(),
            description: _descriptionController.text.trim(),
            imageUrl: _imagePath,
            variantName: _variantController.text.trim(),
            baseUomId: _baseUomId!,
            minStockThreshold: threshold,
            maxStockLevel: maxLevel,
            sellingPrice: price,
            barcodeQr: barcode,
            locationHint: location,
            storedAtId: _storedAtId,
            // Posted after the base unit, in form order (the repository owns that
            // chain). The code travels with the row so a partial failure can name
            // the unit that was not saved.
            extraSellingUnits: [
              for (final row in _extraUnits)
                NewSellingUnit(
                  uomId: row.uomId!,
                  uomCode: _unitWithId(row.uomId)?.code ?? '',
                  conversionFactor: double.parse(row.factor.text.trim()),
                  sellingPrice: double.parse(row.price.text.trim()),
                  barcodeQr: row.code.text.trim(),
                ),
            ],
          ),
        ),
      );
      return;
    }

    final variant = _variant;
    Navigator.of(context).pop(
      ProductFormResult.edit(
        ProductEditDraft(
          productId: existing.id,
          variantId: variant?.id ?? 0,
          sellingUnitId: _baseSellingUnit(variant)?.id ?? 0,
          baseName: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          categoryId: _categoryId,
          brandId: _brandId,
          // `product` and `base_uom` are frozen after creation, so the variant
          // PATCH never carries them (400 INVALID_VARIANT if it did).
          variantName: _variantController.text.trim(),
          minStockThreshold: threshold,
          maxStockLevel: maxLevel,
          sellingPrice: price,
          barcodeQr: barcode,
          locationHint: location,
          // Only when the clerk MOVED it. Resending the unchanged id would be
          // refused for a product sitting at a location the shop has since
          // deactivated (INVALID_STORAGE_LOCATION), failing an edit that never
          // touched the place.
          storedAtId: _storedAtChanged ? _storedAtId : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.inventory_2_outlined,
      title: _editing ? 'Edit product' : 'Add product',
      subtitle: _editing
          ? '${widget.product!.baseName} · ${widget.product!.brandName}'
          : 'A catalogue item, how it is sold, and its stock levels.',
      width: 600,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FormStepHeader(step: 1, title: 'Basic information'),
            ..._stepOne(context),
            const Divider(height: AppSpacing.xxl),
            const FormStepHeader(step: 2, title: 'How is this product sold?'),
            ..._stepTwo(context),
            const Divider(height: AppSpacing.xxl),
            const FormStepHeader(step: 3, title: 'Stock levels'),
            ..._stepThree(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_editing ? 'Save changes' : 'Add product'),
        ),
      ],
    );
  }

  List<Widget> _stepOne(BuildContext context) {
    return [
      TextFormField(
        controller: _nameController,
        autofocus: true,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'Product name'),
        validator: (value) => value == null || value.trim().isEmpty
            ? 'Enter a product name.'
            : null,
      ),
      const SizedBox(height: AppSpacing.md),
      TextFormField(
        controller: _variantController,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'Variant name'),
        validator: (value) => value == null || value.trim().isEmpty
            ? 'Enter a variant name.'
            : null,
      ),
      const SizedBox(height: AppSpacing.md),
      TextFormField(
        controller: _barcodeController,
        decoration: const InputDecoration(
          labelText: 'Factory barcode (leave blank to auto-generate)',
          hintText: 'Scan or type the code printed on the package',
          prefixIcon: Icon(Icons.barcode_reader),
        ),
        validator: (value) {
          final barcode = value?.trim() ?? '';
          if (barcode.isEmpty) return null;
          final duplicate = widget.products.any(
            (product) =>
                product.id != widget.product?.id &&
                product.variants.any(
                  (variant) =>
                      variant.barcode.toLowerCase() == barcode.toLowerCase(),
                ),
          );
          return duplicate
              ? 'This barcode is already assigned to another product.'
              : null;
        },
      ),
      const SizedBox(height: AppSpacing.lg),
      DropdownButtonFormField<int>(
        key: const ValueKey('category-picker'),
        isExpanded: true,
        initialValue: _categoryId,
        decoration: const InputDecoration(labelText: 'Category'),
        items: widget.categories
            // An archived category is hidden from the picker; its products stay
            // sellable.
            .where(
              (category) =>
                  category.isActive ||
                  category.id == widget.product?.categoryId,
            )
            .map(
              (category) => DropdownMenuItem(
                value: category.id,
                child: Text(category.name, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        validator: (value) => value == null ? 'Choose a category.' : null,
        onChanged: (value) {
          if (value != null) setState(() => _categoryId = value);
        },
      ),
      const SizedBox(height: AppSpacing.lg),
      DropdownButtonFormField<int>(
        key: const ValueKey('brand-picker'),
        isExpanded: true,
        initialValue: _brandId,
        decoration: const InputDecoration(labelText: 'Brand'),
        items: widget.brands
            .map(
              (brand) => DropdownMenuItem(
                value: brand.id,
                child: Text(brand.name, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        validator: (value) => value == null ? 'Choose a brand.' : null,
        onChanged: (value) {
          if (value != null) setState(() => _brandId = value);
        },
      ),
      const SizedBox(height: AppSpacing.lg),
      TextFormField(
        controller: _descriptionController,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Description'),
      ),
      const SizedBox(height: AppSpacing.lg),
      Text('Product image', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: AppSpacing.sm),
      _ImagePicker(
        imagePath: _imagePath,
        onPick: _selectImage,
        onRemove: () => setState(() => _imagePath = ''),
      ),
    ];
  }

  List<Widget> _stepTwo(BuildContext context) {
    return [
      if (_editing) ...[
        const DialogSectionLabel('Base unit'),
        Text(
          _frozenBaseUnitLabel(),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          // The server answers 400 INVALID_VARIANT to a base-unit change, so the
          // form does not pretend to offer one.
          'A variant keeps this unit for its whole history, so it cannot be '
          'changed here.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ] else
        DropdownButtonFormField<int>(
          key: const ValueKey('base-unit-picker'),
          isExpanded: true,
          initialValue: _baseUomId,
          decoration: const InputDecoration(
            labelText: 'Base unit',
            helperText:
                'Set once: a variant keeps this unit for its whole history.',
          ),
          items: widget.units
              .map(
                (unit) =>
                    DropdownMenuItem(value: unit.id, child: Text(unit.label)),
              )
              .toList(),
          validator: (value) => value == null ? 'Choose a base unit.' : null,
          onChanged: (value) {
            if (value != null) setState(() => _baseUomId = value);
          },
        ),
      const SizedBox(height: AppSpacing.lg),
      TextFormField(
        key: const ValueKey('base-price'),
        controller: _sellingController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Price per $_baseCode',
          prefixText: '₱ ',
          helperText: 'Charged for one $_baseCode',
        ),
        validator: _validateBasePrice,
      ),
      if (!_editing) ...[
        const SizedBox(height: AppSpacing.xl),
        const DialogSectionLabel('Other selling units'),
        Text(
          'Sell this product by the bag, box or pack as well. Each unit carries '
          'its own price and code.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        for (var index = 0; index < _extraUnits.length; index++) ...[
          _extraUnitRow(context, index),
          const SizedBox(height: AppSpacing.md),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('add-unit-row'),
            onPressed: _addExtraUnit,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add another unit'),
          ),
        ),
      ],
    ];
  }

  /// The frozen base unit as the units list spells it, falling back to the code
  /// the server sent when the list has no matching row.
  String _frozenBaseUnitLabel() {
    final code = _variant?.baseUomCode ?? '';
    for (final unit in widget.units) {
      if (unit.code == code) return unit.label;
    }
    return code;
  }

  Widget _extraUnitRow(BuildContext context, int index) {
    final row = _extraUnits[index];
    return SellingUnitFields(
      draft: row,
      index: index,
      keyPrefix: 'row',
      baseCode: _baseCode,
      units: widget.units,
      validateUnit: (value) => _validateUnit(index, value),
      validateFactor: _validateFactor,
      validatePrice: _validatePrice,
      onRemove: () => _removeExtraUnit(index),
    );
  }

  List<Widget> _stepThree() {
    return [
      const InfoBanner(
        message: 'Stock arrives through a purchase order, then Receiving.',
      ),
      const SizedBox(height: AppSpacing.lg),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              key: const ValueKey('reorder-field'),
              controller: _reorderController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Reorder level',
                helperText: 'Low-stock alert below this',
              ),
              validator: _nonNegative,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: TextFormField(
              key: const ValueKey('max-field'),
              controller: _maxController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Maximum stock level',
                helperText: 'Reorder suggestion',
              ),
              validator: _nonNegative,
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      if (widget.storageLocationError != null) ...[
        ErrorBanner(message: widget.storageLocationError!),
        const SizedBox(height: AppSpacing.lg),
      ],
      DropdownButtonFormField<int>(
        key: const ValueKey('stored-at-picker'),
        isExpanded: true,
        initialValue: _storedAtId,
        decoration: const InputDecoration(
          labelText: 'Stored at',
          helperText: 'Where the shop keeps it: printed on the receipt',
        ),
        items: [
          for (final location in _storedAtOptions)
            DropdownMenuItem(
              value: location.id,
              child: Text(
                _storedAtLabel(location),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        validator: (value) =>
            value == null ? 'Choose where this product is stored.' : null,
        onChanged: (value) {
          if (value != null) {
            setState(() {
              _storedAtId = value;
              _storedAtTouched = true;
            });
          }
        },
      ),
      const SizedBox(height: AppSpacing.lg),
      TextFormField(
        key: const ValueKey('location-field'),
        controller: _locationController,
        decoration: const InputDecoration(
          labelText: 'Shelf note (this device only)',
          // The shelf hint is DEVICE-LOCAL knowledge: "Stored at" above is the
          // server's answer, and the two must never be presented as one fact.
          helperText: 'Not shared with other tills',
          hintText: 'Rack A-01',
        ),
      ),
    ];
  }

  static String? _nonNegative(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null) return 'Enter a number.';
    if (parsed < 0) return 'This cannot be negative.';
    return null;
  }
}

/// The product image, its two buttons and the file name.
class _ImagePicker extends StatelessWidget {
  const _ImagePicker({
    required this.imagePath,
    required this.onPick,
    required this.onRemove,
  });

  final String imagePath;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.small),
            child: ProductsImage(imageUrl: imagePath, width: 88, height: 88),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  imagePath.isEmpty
                      ? 'No image selected'
                      : imagePath.split(RegExp(r'[/\\]')).last,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onPick,
                      icon: const Icon(Icons.attach_file),
                      label: Text(
                        imagePath.isEmpty ? 'Choose image' : 'Replace image',
                      ),
                    ),
                    if (imagePath.isNotEmpty)
                      TextButton(
                        onPressed: onRemove,
                        child: const Text('Remove'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
