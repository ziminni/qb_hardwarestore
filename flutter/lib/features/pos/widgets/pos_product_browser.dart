import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/data/models/pos_transaction.dart';
import 'package:client/features/products/widgets/products_image.dart';
import 'package:client/shared/widgets/blueprint.dart';
import 'package:flutter/material.dart';

/// The till's left panel: the scan field, the category + location chips and the
/// product grid.
class PosProductBrowser extends StatefulWidget {
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
    this.stockLabelFor,
  });

  final List<PosCatalogItem> products;

  /// Overrides a card's stock amount (`2 BAG + 32.5 KG` for a bag also sold
  /// by the kilo); null keeps the plain amount.
  final String? Function(PosCatalogItem)? stockLabelFor;
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
  State<PosProductBrowser> createState() => _PosProductBrowserState();
}

class _PosProductBrowserState extends State<PosProductBrowser> {
  /// Location filter: null = All, 'store' = Store, 'bodega' = Bodega.
  String? _locationFilter;

  List<PosCatalogItem> get _filteredProducts {
    final loc = _locationFilter;
    if (loc == null) return widget.products;
    return [
      for (final item in widget.products)
        if (loc == 'bodega'
            ? item.storedAtName.toLowerCase().contains('bodega')
            : !item.storedAtName.toLowerCase().contains('bodega'))
          item,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final showChips =
        widget.onCategorySelected != null && widget.categories.length > 1;
    final visibleProducts = _filteredProducts;
    final hasAnyLocation = widget.products.any(
      (item) => item.storedAtName.isNotEmpty,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.cardBackground,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ScanField(
              controller: widget.searchController,
              focusNode: widget.searchFocusNode,
              onChanged: widget.onSearch,
              onSubmitted: widget.onSubmitted,
            ),
            if (showChips || hasAnyLocation) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    if (hasAnyLocation) ...[
                      _CategoryChip(
                        label: 'All locations',
                        selected: _locationFilter == null,
                        onTap: () {
                          setState(() => _locationFilter = null);
                          widget.searchFocusNode.requestFocus();
                        },
                      ),
                      _CategoryChip(
                        label: 'Store',
                        selected: _locationFilter == 'store',
                        onTap: () {
                          setState(() => _locationFilter = 'store');
                          widget.searchFocusNode.requestFocus();
                        },
                      ),
                      _CategoryChip(
                        label: 'Bodega',
                        selected: _locationFilter == 'bodega',
                        onTap: () {
                          setState(() => _locationFilter = 'bodega');
                          widget.searchFocusNode.requestFocus();
                        },
                      ),
                      if (showChips)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: VerticalDivider(width: 1, color: p.border),
                        ),
                    ],
                    if (showChips) ...[
                      _CategoryChip(
                        label: 'All',
                        selected: widget.selectedCategory == null,
                        onTap: () {
                          widget.onCategorySelected!(null);
                          widget.searchFocusNode.requestFocus();
                        },
                      ),
                      for (final category in widget.categories)
                        _CategoryChip(
                          label: category,
                          selected: widget.selectedCategory == category,
                          onTap: () {
                            widget.onCategorySelected!(category);
                            widget.searchFocusNode.requestFocus();
                          },
                        ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Expanded(
              child: visibleProducts.isEmpty
                  ? Center(child: Text(widget.emptyMessage))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        const maxExtent = 240.0;
                        const gap = 12.0;
                        final columns =
                            ((constraints.maxWidth + gap) / (maxExtent + gap))
                                .ceil()
                                .clamp(1, 99);
                        final cardWidth =
                            (constraints.maxWidth - gap * (columns - 1)) /
                            columns;
                        final textScale = MediaQuery.textScalerOf(
                          context,
                        ).scale(1).clamp(1.0, 1.6);
                        // Top photo is a 1:1 square inside the 1px card border.
                        // Scale only the text block by textScale so the square
                        // photo, padding, and Add button stay crisp without
                        // opening dead vertical space.
                        final imageSize = (cardWidth - 2).clamp(
                          0.0,
                          double.infinity,
                        );
                        final fixedHeight = imageSize + 100.0;
                        final textHeight = 116.0 * textScale;
                        return GridView.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisExtent: fixedHeight + textHeight,
                                crossAxisSpacing: gap,
                                mainAxisSpacing: gap,
                              ),
                          itemCount: visibleProducts.length,
                          itemBuilder: (context, index) => _ProductCard(
                            product: visibleProducts[index],
                            stockLabel: widget.stockLabelFor?.call(
                              visibleProducts[index],
                            ),
                            onAdd: () =>
                                widget.onSelect(visibleProducts[index]),
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

/// The field the USB scanner types into. Accent-bordered so it reads as the
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
    final p = AppPalette.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: p.accent, width: 2),
    );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: true,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: TextStyle(fontSize: 15, color: p.textPrimary),
      decoration: InputDecoration(
        hintText: 'Search or scan a Queen Builders barcode',
        filled: true,
        fillColor: p.isDark ? p.surfaceSunken : const Color(0xFFFFFDF7),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(
            color: p.isDark ? p.accentLight : AppColors.brandBlack,
            width: 2,
          ),
        ),
        prefixIcon: Icon(Icons.barcode_reader, color: p.accentInk),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Tooltip(
            message: 'Scan a barcode and press Enter',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: p.cardBackground,
                border: Border.all(color: p.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Scanner ready',
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
            ),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(minHeight: 24),
      ),
    );
  }
}

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
    final p = AppPalette.of(context);
    final selectedBg = p.isDark ? p.accent : AppColors.brandBlack;
    final selectedFg = p.isDark ? p.onAccent : AppColors.brandWhite;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? selectedBg : p.cardBackground,
          shape: StadiumBorder(
            side: BorderSide(color: selected ? selectedBg : p.border),
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
                    color: selected ? selectedFg : p.textPrimary,
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
  const _ProductCard({
    required this.product,
    required this.onAdd,
    this.stockLabel,
  });

  final PosCatalogItem product;
  final String? stockLabel;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final caption = [
      product.categoryName,
      product.brandName,
    ].where((part) => part.isNotEmpty).join(' · ').toUpperCase();
    final outOfStock = product.availableSaleQuantity <= 0;
    final addBg = p.isDark ? p.accent : AppColors.brandBlack;
    final addFg = p.isDark ? p.onAccent : AppColors.brandWhite;

    return Material(
      color: outOfStock ? p.surfaceSunken : p.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: outOfStock ? null : onAdd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CardImageHeader(
              imageUrl: product.imageUrl,
              outOfStock: outOfStock,
            ),
            Divider(height: 1, thickness: 1, color: p.border),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (caption.isNotEmpty) ...[
                      Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: p.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 3),
                    ],
                    Text(
                      product.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      product.variantName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: p.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    _StockBadge(
                      quantity: product.availableSaleQuantity,
                      unit: product.unit,
                      isLowStock: product.isLowStock,
                      amountLabel: stockLabel,
                    ),
                    const SizedBox(height: 8),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: formatPeso(product.unitPrice),
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          TextSpan(
                            text: ' / ${product.unit.toLowerCase()}',
                            style: TextStyle(
                              fontSize: 12,
                              color: p.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: outOfStock ? null : onAdd,
                        style: FilledButton.styleFrom(
                          backgroundColor: addBg,
                          foregroundColor: addFg,
                          minimumSize: const Size(64, 38),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Square (1:1) top photo frame for each POS material card: shows the
/// stocker-uploaded product image when available, or a themed placeholder.
class _CardImageHeader extends StatelessWidget {
  const _CardImageHeader({required this.imageUrl, required this.outOfStock});

  final String imageUrl;
  final bool outOfStock;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final placeholder = _CardImagePlaceholder(palette: p);

    final image = AspectRatio(
      aspectRatio: 1,
      child: ColoredBox(
        color: p.surfaceSunken,
        child: ProductsImage(
          imageUrl: imageUrl,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          placeholder: placeholder,
        ),
      ),
    );

    if (!outOfStock) return image;
    return Opacity(opacity: 0.55, child: image);
  }
}

class _CardImagePlaceholder extends StatelessWidget {
  const _CardImagePlaceholder({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: palette.surfaceSunken),
        IgnorePointer(
          child: CustomPaint(painter: _PlaceholderGridPainter(palette.accent)),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: palette.cardBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.border),
                ),
                child: Icon(
                  Icons.image_outlined,
                  size: 22,
                  color: palette.accentInk,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'No photo',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlaceholderGridPainter extends CustomPainter {
  const _PlaceholderGridPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    Blueprint.paintGrid(canvas, size, opacity: 0.45, color: accent);
  }

  @override
  bool shouldRepaint(covariant _PlaceholderGridPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

/// Stock on hand, in words AND color: the color alone would not reach a
/// color-blind cashier, and the tinted pill keeps small text readable.
class _StockBadge extends StatelessWidget {
  const _StockBadge({
    required this.quantity,
    required this.unit,
    required this.isLowStock,
    this.amountLabel,
  });

  final double quantity;
  final String unit;

  /// Amount and unit already worded (`2 BAG + 32.5 KG`); replaces both.
  final String? amountLabel;

  /// Derived from the server's threshold in base units, not the printed unit.
  final bool isLowStock;

  @override
  Widget build(BuildContext context) {
    // One quantity format for the whole app (formatQuantity, D7).
    final amount = amountLabel ?? formatQuantity(quantity);
    final unitLabel = amountLabel == null ? ' ${unit.toLowerCase()}' : '';
    final (Color text, Color tint, String label) = quantity <= 0
        ? (AppColors.errorText, AppColors.errorTint, 'Out of stock')
        : isLowStock
        ? (
            AppColors.warningText,
            AppColors.warningTint,
            'Low: $amount$unitLabel left',
          )
        : (
            AppColors.successText,
            AppColors.successTint,
            '$amount$unitLabel in stock',
          );
    return Container(
      constraints: const BoxConstraints(minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
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
