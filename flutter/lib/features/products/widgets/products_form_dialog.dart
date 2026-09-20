import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/product_tracking.dart';
import 'package:client/data/services/image_file_service.dart';
import 'package:client/features/products/widgets/products_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';

class ProductsFormDialog extends StatefulWidget {
  const ProductsFormDialog({
    super.key,
    required this.categories,
    required this.brands,
    this.product,
  });

  final List<Product> categories;
  final List<Product> brands;
  final Product? product;

  @override
  State<ProductsFormDialog> createState() => _ProductsFormDialogState();
}

class _ProductsFormDialogState extends State<ProductsFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _variantController;
  late final TextEditingController _skuController;
  late final TextEditingController _initialStockController;
  late final TextEditingController _reorderController;
  late final TextEditingController _locationController;
  late final TextEditingController _packageSizeController;
  late final TextEditingController _costController;
  late final TextEditingController _sellingController;
  ProductTrackingMethod _trackingMethod = ProductTrackingMethod.quantity;
  ProductStockForm _stockForm = ProductStockForm.direct;
  String _baseUnit = 'piece';
  String _packageType = 'Bag';
  bool _allowFractional = false;
  bool _allowPartial = false;
  late int _categoryId;
  late int _brandId;
  late String _imagePath;

  final _imageFileService = const ImageFileService();

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _nameController = TextEditingController(text: product?.baseName ?? '');
    _descriptionController = TextEditingController(
      text: product?.description ?? '',
    );
    final firstVariant = product?.variants.firstOrNull;
    _variantController = TextEditingController(
      text: firstVariant?.variantName ?? 'Standard',
    );
    _skuController = TextEditingController(text: firstVariant?.sku ?? '');
    _initialStockController = TextEditingController(
      text: firstVariant == null
          ? '0'
          : firstVariant.currentStock.toStringAsFixed(0),
    );
    _reorderController = TextEditingController(
      text: firstVariant == null
          ? '10'
          : firstVariant.reorderLevel.toStringAsFixed(0),
    );
    _locationController = TextEditingController(
      text: firstVariant?.storageLocation ?? '',
    );
    _packageSizeController = TextEditingController(text: '40');
    _costController = TextEditingController(
      text: firstVariant?.costPrice.toStringAsFixed(2) ?? '0',
    );
    _sellingController = TextEditingController(
      text: firstVariant?.sellingPrice.toStringAsFixed(2) ?? '0',
    );
    _categoryId = product?.categoryId ?? widget.categories.first.categoryId;
    _brandId = product?.brandId ?? widget.brands.first.brandId;
    _imagePath = product?.imageUrl ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _variantController.dispose();
    _skuController.dispose();
    _initialStockController.dispose();
    _reorderController.dispose();
    _locationController.dispose();
    _packageSizeController.dispose();
    _costController.dispose();
    _sellingController.dispose();
    super.dispose();
  }

  Future<void> _selectImage() async {
    final path = await _imageFileService.selectImage();
    if (!mounted || path == null) return;
    setState(() => _imagePath = path);
  }

  String _defaultUnit(ProductTrackingMethod method) => switch (method) {
    ProductTrackingMethod.quantity => 'piece',
    ProductTrackingMethod.weight => 'kg',
    ProductTrackingMethod.length => 'meter',
    ProductTrackingMethod.volume => 'L',
  };

  List<String> _unitsForMethod() => switch (_trackingMethod) {
    ProductTrackingMethod.quantity => ['piece', 'box', 'pack', 'set', 'bundle'],
    ProductTrackingMethod.weight => ['kg', 'g'],
    ProductTrackingMethod.length => ['meter', 'cm', 'mm', 'inch', 'foot'],
    ProductTrackingMethod.volume => ['L', 'mL'],
  };

  List<ProductStockForm> _stockOptions() => switch (_trackingMethod) {
    ProductTrackingMethod.length => [
      ProductStockForm.continuous,
      ProductStockForm.standardLengths,
    ],
    ProductTrackingMethod.weight || ProductTrackingMethod.volume => [
      ProductStockForm.direct,
      ProductStockForm.packaged,
    ],
    ProductTrackingMethod.quantity => [ProductStockForm.direct],
  };

  Widget _buildPreview(BuildContext context) {
    final initial = double.tryParse(_initialStockController.text) ?? 0;
    final size = double.tryParse(_packageSizeController.text) ?? 0;
    final packaged =
        _stockForm == ProductStockForm.packaged ||
        _stockForm == ProductStockForm.standardLengths;
    final total = packaged ? initial * size : initial;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.secondaryContainer.withValues(alpha: .35),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Stock Preview',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _nameController.text.trim().isEmpty
                ? 'Unnamed product'
                : _nameController.text.trim(),
          ),
          Text('Tracking: ${_trackingMethod.label}'),
          if (packaged)
            Text(
              'Physical inventory: ${initial.toStringAsFixed(0)} ${_packageType.toLowerCase()}s × ${size.toStringAsFixed(2)} $_baseUnit',
            ),
          Text('Total available: ${total.toStringAsFixed(2)} $_baseUnit'),
          Text(
            'Smaller amount sales: ${_allowPartial || _allowFractional ? 'Allowed' : 'Not allowed'}',
          ),
          Text(
            'Selling: ₱${_sellingController.text.isEmpty ? '0' : _sellingController.text} / $_baseUnit',
          ),
        ],
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final category = widget.categories.firstWhere(
      (product) => product.categoryId == _categoryId,
    );
    final brand = widget.brands.firstWhere(
      (product) => product.brandId == _brandId,
    );
    final existing = widget.product;
    final initial = double.tryParse(_initialStockController.text) ?? 0;
    final packageSize = double.tryParse(_packageSizeController.text) ?? 0;
    final packaged =
        _stockForm == ProductStockForm.packaged ||
        _stockForm == ProductStockForm.standardLengths;
    final total = packaged ? initial * packageSize : initial;
    final configuration = ProductTrackingConfiguration(
      productName: _nameController.text.trim(),
      method: _trackingMethod,
      baseUnit: _baseUnit,
      stockForm: _stockForm,
      allowFractional: _allowFractional,
      allowPartialPackage: _allowPartial,
      packageType: _packageType,
      packageSize: packageSize,
      initialPackages: packaged ? initial.toInt() : 0,
      totalBaseQuantity: total,
      reorderLevel: double.tryParse(_reorderController.text) ?? 0,
      storageLocation: _locationController.text.trim(),
      costPrice: double.tryParse(_costController.text) ?? 0,
      sellingPrice: double.tryParse(_sellingController.text) ?? 0,
      packageSellingPrice: 0,
      standardLength: _stockForm == ProductStockForm.standardLengths
          ? packageSize
          : 0,
      allowedSaleUnits: _unitsForMethod(),
      physicalPieces: _stockForm == ProductStockForm.standardLengths
          ? List.filled(initial.toInt(), packageSize)
          : const [],
    );
    context.read<ProductTrackingViewmodel>().save(configuration);

    Navigator.of(context).pop(
      Product(
        id: existing?.id ?? 0,
        categoryId: category.categoryId,
        categoryName: category.categoryName,
        brandId: brand.brandId,
        brandName: brand.brandName,
        baseName: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        imageUrl: _imagePath,
        isActive: existing?.isActive ?? true,
        variants:
            existing?.variants ??
            [
              ProductVariant(
                id: DateTime.now().microsecondsSinceEpoch,
                variantName: _variantController.text.trim(),
                baseUomCode: _baseUnit,
                isActive: true,
                sku: _skuController.text.trim(),
                qrIdentifier:
                    'MAT-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
                currentStock: total,
                reorderLevel: double.tryParse(_reorderController.text) ?? 0,
                storageLocation: _locationController.text.trim(),
                costPrice: double.tryParse(_costController.text) ?? 0,
                sellingPrice: double.tryParse(_sellingController.text) ?? 0,
              ),
            ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(widget.product == null ? 'Add product' : 'Edit product'),
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
                  '1. Basic Information',
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
                if (widget.product == null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'First variant',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _variantController,
                    decoration: const InputDecoration(
                      labelText: 'Variant name',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a variant name.'
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _skuController,
                    decoration: const InputDecoration(labelText: 'SKU'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter an SKU.'
                        : null,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<int>(
                  initialValue: _categoryId,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: widget.categories
                      .map(
                        (product) => DropdownMenuItem(
                          value: product.categoryId,
                          child: Text(product.categoryName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _categoryId = value);
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<int>(
                  initialValue: _brandId,
                  decoration: const InputDecoration(labelText: 'Brand'),
                  items: widget.brands
                      .map(
                        (product) => DropdownMenuItem(
                          value: product.brandId,
                          child: Text(product.brandName),
                        ),
                      )
                      .toList(),
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
                const SizedBox(height: AppSpacing.md),
                if (widget.product == null) ...[
                  const Divider(height: AppSpacing.xxl),
                  Text(
                    '2. Inventory Tracking',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text('How is this product tracked?'),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: ProductTrackingMethod.values
                        .map(
                          (method) => ChoiceChip(
                            label: Text(method.label),
                            selected: _trackingMethod == method,
                            onSelected: (_) => setState(() {
                              _trackingMethod = method;
                              _baseUnit = _defaultUnit(method);
                              _stockForm =
                                  method == ProductTrackingMethod.length
                                  ? ProductStockForm.standardLengths
                                  : ProductStockForm.direct;
                              _allowFractional =
                                  method != ProductTrackingMethod.quantity;
                            }),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _trackingMethod.description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  DropdownButtonFormField<String>(
                    initialValue: _baseUnit,
                    decoration: const InputDecoration(
                      labelText: 'Base measurement / unit',
                    ),
                    items: _unitsForMethod()
                        .map(
                          (unit) =>
                              DropdownMenuItem(value: unit, child: Text(unit)),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _baseUnit = value ?? _baseUnit),
                  ),
                  if (_trackingMethod != ProductTrackingMethod.quantity) ...[
                    const SizedBox(height: AppSpacing.md),
                    SegmentedButton<ProductStockForm>(
                      segments: _stockOptions()
                          .map(
                            (form) => ButtonSegment(
                              value: form,
                              label: Text(form.label),
                            ),
                          )
                          .toList(),
                      selected: {_stockForm},
                      onSelectionChanged: (values) =>
                          setState(() => _stockForm = values.first),
                    ),
                  ],
                  if (_stockForm == ProductStockForm.packaged ||
                      _stockForm == ProductStockForm.standardLengths) ...[
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _packageType,
                            decoration: InputDecoration(
                              labelText:
                                  _stockForm == ProductStockForm.standardLengths
                                  ? 'Physical unit'
                                  : 'Package type',
                            ),
                            items:
                                const [
                                      'Bag',
                                      'Sack',
                                      'Box',
                                      'Pack',
                                      'Container',
                                      'Piece',
                                      'Roll',
                                    ]
                                    .map(
                                      (item) => DropdownMenuItem(
                                        value: item,
                                        child: Text(item),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (value) => setState(
                              () => _packageType = value ?? _packageType,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: TextFormField(
                            controller: _packageSizeController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText:
                                  _stockForm == ProductStockForm.standardLengths
                                  ? 'Standard length per piece'
                                  : 'Quantity per package',
                              suffixText: _baseUnit,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _stockForm == ProductStockForm.standardLengths
                            ? 'Allow partial / cut sales'
                            : 'Allow partial package sales',
                      ),
                      value: _allowPartial,
                      onChanged: (value) =>
                          setState(() => _allowPartial = value),
                    ),
                  ],
                  if (_trackingMethod == ProductTrackingMethod.quantity)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Allow fractional quantity?'),
                      subtitle: const Text(
                        'Keep this off for indivisible items such as hammers.',
                      ),
                      value: _allowFractional,
                      onChanged: (value) =>
                          setState(() => _allowFractional = value),
                    ),
                  const Divider(height: AppSpacing.xxl),
                  Text(
                    '3. Pricing & Initial Stock',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _costController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Cost per $_baseUnit',
                            prefixText: '₱ ',
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: TextFormField(
                          controller: _sellingController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Selling price per $_baseUnit',
                            prefixText: '₱ ',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _initialStockController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText:
                                (_stockForm == ProductStockForm.packaged ||
                                    _stockForm ==
                                        ProductStockForm.standardLengths)
                                ? 'Initial packages / pieces'
                                : 'Initial quantity',
                            suffixText:
                                (_stockForm == ProductStockForm.packaged ||
                                    _stockForm ==
                                        ProductStockForm.standardLengths)
                                ? _packageType.toLowerCase()
                                : _baseUnit,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: TextFormField(
                          controller: _reorderController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Reorder level',
                            suffixText: _baseUnit,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _locationController,
                    decoration: const InputDecoration(
                      labelText: 'Storage location',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _buildPreview(context),
                ],
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
          child: Text(widget.product == null ? 'Add product' : 'Save changes'),
        ),
      ],
    );
  }
}
