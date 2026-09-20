import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/product_tracking.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ProductsInventorySimulatorDialog extends StatefulWidget {
  const ProductsInventorySimulatorDialog({super.key});
  @override
  State<ProductsInventorySimulatorDialog> createState() =>
      _ProductsInventorySimulatorDialogState();
}

class _ProductsInventorySimulatorDialogState
    extends State<ProductsInventorySimulatorDialog> {
  final _quantity = TextEditingController(text: '1');
  String? _productName;
  String? _unit;
  InventorySimulationResult? _result;
  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  String _summary(ProductTrackingConfiguration config) {
    if (config.method == ProductTrackingMethod.length &&
        config.stockForm == ProductStockForm.standardLengths) {
      return '${config.fullPieces} full pieces · ${config.cutPieces} cut pieces · ${config.totalBaseQuantity.toStringAsFixed(3)} ${config.baseUnit} total';
    }
    if (config.stockForm == ProductStockForm.packaged) {
      return '${config.sealedPackages} sealed ${config.packageType.toLowerCase()}s · ${config.openPackageRemainder.toStringAsFixed(2)} ${config.baseUnit} opened · ${config.totalBaseQuantity.toStringAsFixed(2)} ${config.baseUnit} total';
    }
    return '${config.totalBaseQuantity.toStringAsFixed(2)} ${config.baseUnit} available';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProductTrackingViewmodel>();
    _productName ??= state.configurations.first.productName;
    final config = state.configurationFor(_productName!)!;
    _unit ??= config.allowedSaleUnits.first;
    if (!config.allowedSaleUnits.contains(_unit)) {
      _unit = config.allowedSaleUnits.first;
    }
    return AlertDialog(
      title: const Text('Inventory Simulator'),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Frontend-only simulation',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: AppColors.brandGold),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Test how quantity, packages, cuts, and unit conversions affect physical inventory.',
              ),
              const SizedBox(height: AppSpacing.xl),
              DropdownButtonFormField<String>(
                initialValue: _productName,
                decoration: const InputDecoration(labelText: 'Sample product'),
                items: state.configurations
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.productName,
                        child: Text(item.productName),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() {
                  _productName = value;
                  _unit = null;
                  _result = null;
                }),
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
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
                      config.method.label,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(_summary(config)),
                    const SizedBox(height: AppSpacing.xs),
                    Text('Location: ${config.storageLocation}'),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _quantity,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Customer quantity',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 170,
                    child: DropdownButtonFormField<String>(
                      initialValue: _unit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: config.allowedSaleUnits
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _unit = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: () {
                  final value = double.tryParse(_quantity.text);
                  if (value == null) {
                    setState(
                      () => _result = const InventorySimulationResult(
                        success: false,
                        message: 'Enter a valid quantity.',
                      ),
                    );
                    return;
                  }
                  setState(
                    () => _result = context
                        .read<ProductTrackingViewmodel>()
                        .simulateSale(config.productName, value, _unit!),
                  );
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Simulate sale'),
              ),
              if (_result != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color:
                        (_result!.success ? AppColors.success : AppColors.error)
                            .withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _result!.success
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: _result!.success
                            ? AppColors.success
                            : AppColors.error,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: Text(_result!.message)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
