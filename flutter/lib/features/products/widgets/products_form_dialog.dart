import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/product_writes.dart';
import 'package:client/data/services/image_file_service.dart';
import 'package:client/features/products/widgets/products_image.dart';
import 'package:flutter/material.dart';

/// What the product form produced: a creation draft, or an edit draft.
///
/// One dialog, two payloads, because the two writes are genuinely different: a
/// create is a chain of three POSTs that cannot exist without a category, a brand
/// and a base unit, while an edit is a set of PATCHes over rows that already have
/// ids. Phase 4 Task 4.
class ProductFormResult {
  const ProductFormResult.create(NewProductDraft this.draft) : edit = null;
  const ProductFormResult.edit(ProductEditDraft this.edit) : draft = null;

  final NewProductDraft? draft;
  final ProductEditDraft? edit;
}

/// The product dialog, live (Phase 4 Task 4).
///
/// Two things changed at once here, and both were forced by the server contract:
///
///  * **No opening stock.** User decision 2026-10-25: a product's first stock
///    arrives through a purchase order that is then received. Quantity, cost and
///    package fields used to build an in-memory batch that vanished on reload.
///  * **Server lists, not derivations.** Categories and brands come from their
///    own endpoints and the base unit from `/uoms/`, because `base_uom` is a
///    foreign key that is frozen after creation. The old form offered a hardcoded
///    word list ('piece', 'kg', …) that could not be sent at all.
class ProductsFormDialog extends StatefulWidget {
  const ProductsFormDialog({
    super.key,
    required this.categories,
    required this.brands,
    required this.units,
    required this.products,
    this.product,
  });

  final List<Category> categories;
  final List<Brand> brands;
  final List<UnitOfMeasure> units;
  final List<Product> products;
  final Product? product;

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
  int? _categoryId;
  int? _brandId;
  int? _baseUomId;
  late String _imagePath;

  final _imageFileService = const ImageFileService();

  ProductVariant? get _variant => widget.product?.variants.firstOrNull;

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
      text: (variant?.minStockThreshold ?? 0).toStringAsFixed(0),
    );
    _maxController = TextEditingController(
      text: (variant?.maxStockLevel ?? 0).toStringAsFixed(0),
    );
    _sellingController = TextEditingController(
      // The charged price is the selling unit's, never the batch's (decision 08).
      text:
          variant?.sellingUoms.firstOrNull?.defaultSellingPrice.toStringAsFixed(
            2,
          ) ??
          '0.00',
    );
    _categoryId = product?.categoryId ?? widget.categories.firstOrNull?.id;
    _brandId = product?.brandId ?? widget.brands.firstOrNull?.id;
    _baseUomId = variant?.baseUomId ?? widget.units.firstOrNull?.id;
    _imagePath = product?.imageUrl ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _variantController.dispose();
    _barcodeController.dispose();
    _reorderController.dispose();
    _maxController.dispose();
    _sellingController.dispose();
    super.dispose();
  }

  Future<void> _selectImage() async {
    final path = await _imageFileService.selectImage();
    if (!mounted || path == null) return;
    setState(() => _imagePath = path);
  }

  /// The factor-1 selling unit's code — the unit this form writes.
  ///
  /// `variant.barcode` answers with the variant's FIRST non-blank code, which may
  /// be the box's; the form PATCHes the base unit, so it must show that one.
  String _baseUnitCode(ProductVariant? variant) {
    if (variant == null) return '';
    for (final unit in variant.sellingUoms) {
      if (unit.conversionFactor == 1) return unit.barcodeQr;
    }
    return variant.barcode;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final price = double.tryParse(_sellingController.text.trim()) ?? 0;
    final threshold = double.tryParse(_reorderController.text.trim()) ?? 0;
    final maxLevel = double.tryParse(_maxController.text.trim()) ?? 0;
    final barcode = _barcodeController.text.trim();

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
          sellingUnitId: variant?.sellingUoms.firstOrNull?.id ?? 0,
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final editing = widget.product != null;
    return AlertDialog(
      title: Text(editing ? 'Edit product' : 'Add product'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '1. Basic information',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Product name'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a product name.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _variantController,
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
                                variant.barcode.toLowerCase() ==
                                barcode.toLowerCase(),
                          ),
                    );
                    return duplicate
                        ? 'This barcode is already assigned to another product.'
                        : null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _categoryId,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: widget.categories
                      // An archived category is hidden from the picker; its
                      // products stay sellable.
                      .where(
                        (category) =>
                            category.isActive ||
                            category.id == widget.product?.categoryId,
                      )
                      .map(
                        (category) => DropdownMenuItem(
                          value: category.id,
                          child: Text(
                            category.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  validator: (value) =>
                      value == null ? 'Choose a category.' : null,
                  onChanged: (value) {
                    if (value != null) setState(() => _categoryId = value);
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _brandId,
                  decoration: const InputDecoration(labelText: 'Brand'),
                  items: widget.brands
                      .map(
                        (brand) => DropdownMenuItem(
                          value: brand.id,
                          child: Text(
                            brand.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  validator: (value) =>
                      value == null ? 'Choose a brand.' : null,
                  onChanged: (value) {
                    if (value != null) setState(() => _brandId = value);
                  },
                ),
                if (!editing) ...[
                  const SizedBox(height: AppSpacing.lg),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: _baseUomId,
                    decoration: const InputDecoration(
                      labelText: 'Base unit',
                      helperText:
                          'Set once: a variant keeps this unit for its whole '
                          'history.',
                    ),
                    items: widget.units
                        .map(
                          (unit) => DropdownMenuItem(
                            value: unit.id,
                            child: Text(unit.label),
                          ),
                        )
                        .toList(),
                    validator: (value) =>
                        value == null ? 'Choose a base unit.' : null,
                    onChanged: (value) {
                      if (value != null) setState(() => _baseUomId = value);
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Product image',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLowest,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadii.small),
                        child: ProductsImage(
                          imageUrl: _imagePath,
                          width: 88,
                          height: 88,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _imagePath.isEmpty
                                  ? 'No image selected'
                                  : _imagePath.split(RegExp(r'[/\\]')).last,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _selectImage,
                                  icon: const Icon(Icons.attach_file),
                                  label: Text(
                                    _imagePath.isEmpty
                                        ? 'Choose image'
                                        : 'Replace image',
                                  ),
                                ),
                                if (_imagePath.isNotEmpty)
                                  TextButton(
                                    onPressed: () =>
                                        setState(() => _imagePath = ''),
                                    child: const Text('Remove'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: AppSpacing.xxl),
                Text(
                  '2. Stock levels',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer.withValues(alpha: .35),
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.local_shipping_outlined, size: 18),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Stock arrives through a purchase order → Receiving. '
                          'This form creates the catalogue item only.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
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
                        controller: _maxController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Maximum stock level',
                          helperText: 'Used to suggest reorder quantity',
                        ),
                        validator: _nonNegative,
                      ),
                    ),
                  ],
                ),
                const Divider(height: AppSpacing.xxl),
                Text(
                  '3. Selling price',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _sellingController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Selling price',
                    prefixText: '₱ ',
                  ),
                  validator: (value) {
                    final price = double.tryParse(value?.trim() ?? '');
                    if (price == null) return 'Enter a price.';
                    if (price < 0) return 'The price cannot be negative.';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(editing ? 'Save changes' : 'Add product'),
        ),
      ],
    );
  }

  static String? _nonNegative(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null) return 'Enter a number.';
    if (parsed < 0) return 'This cannot be negative.';
    return null;
  }
}
