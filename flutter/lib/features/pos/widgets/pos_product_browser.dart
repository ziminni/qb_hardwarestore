import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/pos_transaction.dart';
import 'package:flutter/material.dart';

/// The till's left panel: the scan field, the category chips and the
/// product grid.
class PosProductBrowser extends StatelessWidget {
  const PosProductBrowser({
    super.key,
    required this.products,
    required this.onSearch,
    required this.onSelect,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSubmitted,
    this.emptyMessage = 'No products match your search.',
    this.categories = const [],
    this.selectedCategory,
    this.onCategorySelected,
  });

  final List<PosCatalogItem> products;
  final ValueChanged<String> onSearch;
  final ValueChanged<PosCatalogItem> onSelect;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSubmitted;

  /// What the empty grid says. The till passes a different sentence when the
  /// catalogue itself failed to load — "no products match your search" would
  /// blame a search the cashier never made.
  final String emptyMessage;

  /// The category chips. Hidden when [onCategorySelected] is null or there is
  /// at most one category (a single chip filters nothing).
  final List<String> categories;
  final String? selectedCategory;
  final ValueChanged<String?>? onCategorySelected;

  @override
  Widget build(BuildContext context) {
    final showChips = onCategorySelected != null && categories.length > 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ScanField(
              controller: searchController,
              focusNode: searchFocusNode,
              onChanged: onSearch,
              onSubmitted: onSubmitted,
            ),
            if (showChips) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _CategoryChip(
                      label: 'All',
                      selected: selectedCategory == null,
                      onTap: () => onCategorySelected!(null),
                    ),
                    for (final category in categories)
                      _CategoryChip(
                        label: category,
                        selected: selectedCategory == category,
                        onTap: () => onCategorySelected!(category),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Expanded(
              child: products.isEmpty
                  ? Center(child: Text(emptyMessage))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        // The same column count the delegate below will pick,
                        // so the card height can follow the card width: a
                        // narrow card stacks its price over Add and needs
                        // more room than a wide one.
                        const maxExtent = 240.0;
                        const gap = 12.0;
                        final columns =
                            (constraints.maxWidth / (maxExtent + gap))
                                .ceil()
                                .clamp(1, 99);
                        final cardWidth =
                            (constraints.maxWidth - gap * (columns - 1)) /
                            columns;
                        final stacked =
                            cardWidth - 28 < _ProductCard.sideBySidePriceWidth;
                        final textScale = MediaQuery.textScalerOf(
                          context,
                        ).scale(1);
                        return GridView.builder(
                          gridDelegate:
                              SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: maxExtent,
                                mainAxisExtent:
                                    (stacked ? 252.0 : 212.0) *
                                    textScale.clamp(1.0, 1.6),
                                crossAxisSpacing: gap,
                                mainAxisSpacing: gap,
                              ),
                          itemCount: products.length,
                          itemBuilder: (context, index) => _ProductCard(
                            product: products[index],
                            onAdd: () => onSelect(products[index]),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The field the USB scanner types into. Gold-bordered so it reads as the
/// till's main input; the hint is the one the scan tests look for.
class _ScanField extends StatelessWidget {
  const _ScanField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.brandGold, width: 2),
    );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: true,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        hintText: 'Search or scan a Queen Builders barcode',
        filled: true,
        fillColor: const Color(0xFFFFFDF7),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: AppColors.brandBlack, width: 2),
        ),
        prefixIcon: const Icon(Icons.barcode_reader, color: _goldInk),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Tooltip(
            message: 'Scan a barcode and press Enter',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Scanner ready',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(minHeight: 24),
      ),
    );
  }
}

/// Gold that reads as text on white (the brand gold is too light for that).
const Color _goldInk = Color(0xFF6E5A22);

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? AppColors.brandBlack : AppColors.cardBackground,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? AppColors.brandBlack : AppColors.border,
            ),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? AppColors.brandWhite
                        : const Color(0xFF3A362F),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onAdd});

  /// Card content width below which the price and Add button stack.
  static const double sideBySidePriceWidth = 180;

  final PosCatalogItem product;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final caption = [
      product.categoryName,
      product.brandName,
    ].where((part) => part.isNotEmpty).join(' · ').toUpperCase();
    final outOfStock = product.availableSaleQuantity <= 0;
    return Material(
      color: outOfStock ? const Color(0xFFFAF9F6) : AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: outOfStock ? null : onAdd,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (caption.isNotEmpty) ...[
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                product.productName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                product.variantName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              _StockBadge(
                quantity: product.availableSaleQuantity,
                unit: product.unit,
              ),
              const Spacer(),
              // A narrow card cannot fit the price beside Add without cutting
              // the price off, so the two stack.
              LayoutBuilder(
                builder: (context, constraints) {
                  final price = Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: formatPeso(product.unitPrice),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        TextSpan(
                          text: ' / ${product.unit.toLowerCase()}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  );
                  final add = FilledButton(
                    onPressed: outOfStock ? null : onAdd,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandBlack,
                      foregroundColor: AppColors.brandWhite,
                      minimumSize: const Size(64, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'Add',
                      semanticsLabel:
                          'Add ${product.productName} ${product.variantName}',
                    ),
                  );
                  if (constraints.maxWidth >= sideBySidePriceWidth) {
                    return Row(
                      children: [
                        Expanded(child: price),
                        const SizedBox(width: 8),
                        add,
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [price, const SizedBox(height: 6), add],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stock on hand, in words AND color: the color alone would not reach a
/// color-blind cashier, and the tinted pill keeps small text readable.
class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.quantity, required this.unit});

  final double quantity;
  final String unit;

  /// At or below this, the badge warns that stock is running low.
  static const double lowThreshold = 10;

  @override
  Widget build(BuildContext context) {
    final amount = quantity == quantity.roundToDouble()
        ? quantity.toStringAsFixed(0)
        : quantity.toStringAsFixed(2);
    final unitLabel = unit.toLowerCase();
    final (Color text, Color tint, String label) = quantity <= 0
        ? (AppColors.errorText, AppColors.errorTint, 'Out of stock')
        : quantity <= lowThreshold
        ? (
            AppColors.warningText,
            AppColors.warningTint,
            'Low: $amount $unitLabel left',
          )
        : (
            AppColors.successText,
            AppColors.successTint,
            '$amount $unitLabel in stock',
          );
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
