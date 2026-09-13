import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/services/image_file_service.dart';
import 'package:client/features/products/widgets/products_image.dart';
import 'package:flutter/material.dart';

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
  late int _categoryId;
  late int _brandId;
  late bool _isActive;
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
    _categoryId = product?.categoryId ?? widget.categories.first.categoryId;
    _brandId = product?.brandId ?? widget.brands.first.brandId;
    _isActive = product?.isActive ?? true;
    _imagePath = product?.imageUrl ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectImage() async {
    final path = await _imageFileService.selectImage();
    if (!mounted || path == null) return;
    setState(() => _imagePath = path);
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
        isActive: _isActive,
        variants: existing?.variants ?? const [],
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
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Product name'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a product name.'
                      : null,
                ),
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active product'),
                  subtitle: const Text(
                    'Inactive products remain in the catalog.',
                  ),
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
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
          child: Text(widget.product == null ? 'Add product' : 'Save changes'),
        ),
      ],
    );
  }
}
