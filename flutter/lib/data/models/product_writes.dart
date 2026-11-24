import 'package:client/data/models/product_image_upload.dart';

/// The two write payloads the product form submits.
///
/// They live in the data layer rather than in the dialog because they are the
/// exact shape the server accepts, and because the create path is a CHAIN of
/// three POSTs (product → variant → selling unit) driven by the repository, not
/// by a widget. Phase 4 Task 4.
class NewProductDraft {
  const NewProductDraft({
    required this.categoryId,
    required this.brandId,
    required this.baseName,
    required this.description,
    required this.imageUrl,
    required this.variantName,
    required this.baseUomId,
    required this.minStockThreshold,
    required this.maxStockLevel,
    required this.sellingPrice,
    this.barcodeQr = '',
    this.creditMarkupKind = 'NONE',
    this.creditMarkupValue = 0,
    this.extraSellingUnits = const [],
    this.locationHint = '',
    this.storedAtId,
    this.image,
    this.sku = '',
    this.openingQty = 0,
    this.openingUnitCost = 0,
    this.allowDiscount = true,
  });

  /// The shop's own stock-keeping code (owner 2026-11-18). Optional.
  final String sku;

  /// Opening stock in BASE units and its cost per base unit (owner 2026-11-18).
  /// Zero means none: the product's first stock then arrives through Receiving.
  /// Posted last, to `/variants/{id}/opening-stock/`, as a bill-free delivery
  /// onto the product's Stored at shelf (a Bodega product waits for the checker).
  final double openingQty;
  final double openingUnitCost;

  /// Whether the till may discount a LINE of this product (owner ruling: cement is
  /// never discounted). Sent explicitly so a create states the same thing the form
  /// shows; the server's own default is true.
  final bool allowDiscount;

  final int categoryId;
  final int brandId;
  final String baseName;
  final String description;
  final String imageUrl;
  final String variantName;
  final int baseUomId;
  final double minStockThreshold;
  final double maxStockLevel;

  /// The factor-1 selling unit's price. The till charges this (decision 08).
  final double sellingPrice;

  /// The utang markup of the factor-1 unit (owner ruling): `NONE` / `AMOUNT` /
  /// `PERCENT`, with the peso or percent value. `NONE` is the server's default,
  /// so a shop that configures nothing behaves exactly as before.
  final String creditMarkupKind;
  final double creditMarkupValue;

  /// Optional: the server defaults it to an empty string, and the seeded
  /// catalogue has no barcodes at all.
  final String barcodeQr;

  /// How else this product is sold, beyond the base unit (decision 15).
  ///
  /// Posted AFTER the factor-1 unit, in this order, because the server refuses a
  /// second factor-1 unit and a unit can only be attached to a variant that
  /// exists.
  final List<NewSellingUnit> extraSellingUnits;

  /// Where the stock sits, remembered on THIS device only (decision 15): the
  /// server has no location column, so this never travels in a POST body.
  final String locationHint;

  /// The SERVER's pick-up point for the product (Phase 5 B4). Null means "the
  /// form had no verified choice", and the field is then left off the body so
  /// the server's own default answers — never a guessed id.
  final int? storedAtId;

  /// The photo the clerk picked, or null when they picked none.
  ///
  /// Sent as `multipart/form-data` on the product POST — the ONE request that
  /// creates the catalogue item, not a second upload after it (a post-create
  /// request would leave a product with no photo whenever it failed).
  final ProductImageUpload? image;

  /// The product row. Opening stock is NOT here: it is its own request after
  /// the variant exists ([openingQty]).
  Map<String, dynamic> productBody() => {
    'category': categoryId,
    'brand': brandId,
    'base_name': baseName,
    'description': description,
    'image_url': imageUrl,
    if (storedAtId != null) 'stored_at': storedAtId,
    'is_active': true,
    'allow_discount': allowDiscount,
  };

  Map<String, dynamic> variantBody(int productId) => {
    'product': productId,
    'variant_name': variantName,
    'sku': sku,
    'base_uom': baseUomId,
    'min_stock_threshold': minStockThreshold,
    'max_stock_level': maxStockLevel,
  };

  Map<String, dynamic> sellingUnitBody(int variantId, int uomId) => {
    'variant': variantId,
    'uom': uomId,
    'conversion_factor': 1,
    'default_selling_price': sellingPrice,
    'barcode_qr': barcodeQr,
    // Sent explicitly so a create states the same thing the form shows, and
    // `NONE` + 0 is what "no markup" means to the server.
    'credit_markup_kind': creditMarkupKind,
    'credit_markup_value': creditMarkupValue,
  };
}

/// One extra selling unit of a NEW product: "1 Bag = 40 kg at ₱270".
///
/// [uomCode] is carried for the message a partial failure has to print — the
/// clerk must know WHICH unit was not saved, and an id would name nothing.
class NewSellingUnit {
  const NewSellingUnit({
    required this.uomId,
    required this.uomCode,
    required this.conversionFactor,
    required this.sellingPrice,
    this.unitsPerBase,
    this.barcodeQr = '',
    this.creditMarkupKind = 'NONE',
    this.creditMarkupValue = 0,
  });

  final int uomId;
  final String uomCode;
  final double conversionFactor;
  final double sellingPrice;

  /// When non-null (> 1), this unit is SMALLER than the variant's current base
  /// unit (`1 base = unitsPerBase of this unit`, e.g. `1 BOX = 24 CAN`). The
  /// repository posts to `/variants/{id}/add-smaller-unit/` so the server can
  /// rebase cleanly onto the smaller unit without 2-decimal rounding loss.
  final double? unitsPerBase;

  /// Blank asks the server for this unit's own `QB` code.
  final String barcodeQr;
  final String creditMarkupKind;
  final double creditMarkupValue;

  Map<String, dynamic> body(int variantId) => {
    'variant': variantId,
    'uom': uomId,
    'conversion_factor': conversionFactor,
    'default_selling_price': sellingPrice,
    'barcode_qr': barcodeQr,
    if (creditMarkupKind != 'NONE' && creditMarkupValue > 0) ...{
      'credit_markup_kind': creditMarkupKind,
      'credit_markup_value': creditMarkupValue,
    },
  };

  Map<String, dynamic> smallerUnitBody() => {
    'uom': uomId,
    'units_per_base': unitsPerBase,
    'default_selling_price': sellingPrice,
    'barcode_qr': barcodeQr,
    if (creditMarkupKind != 'NONE' && creditMarkupValue > 0) ...{
      'credit_markup_kind': creditMarkupKind,
      'credit_markup_value': creditMarkupValue,
    },
  };
}

/// A new standalone variant added directly to an existing product (with its own
/// base selling unit, price, optional utang markup, barcode, reorder level, and
/// optional opening stock — no conversion factor needed).
class NewVariantDraft {
  const NewVariantDraft({
    required this.productId,
    required this.variantName,
    required this.baseUomId,
    required this.baseUomCode,
    required this.sellingPrice,
    required this.minStockThreshold,
    this.sku = '',
    this.barcodeQr = '',
    this.creditMarkupKind = 'NONE',
    this.creditMarkupValue = 0,
    this.openingQty = 0,
    this.openingUnitCost = 0,
  });

  final int productId;
  final String variantName;
  final String sku;
  final int baseUomId;
  final String baseUomCode;
  final double sellingPrice;
  final double minStockThreshold;
  final String barcodeQr;
  final String creditMarkupKind;
  final double creditMarkupValue;
  final double openingQty;
  final double openingUnitCost;

  Map<String, dynamic> variantBody() => {
    'product': productId,
    'variant_name': variantName,
    'sku': sku,
    'base_uom': baseUomId,
    'min_stock_threshold': minStockThreshold,
    'max_stock_level': 0,
  };

  Map<String, dynamic> sellingUnitBody(int variantId) => {
    'variant': variantId,
    'uom': baseUomId,
    'conversion_factor': 1,
    'default_selling_price': sellingPrice,
    'barcode_qr': barcodeQr,
    'credit_markup_kind': creditMarkupKind,
    'credit_markup_value': creditMarkupValue,
  };
}

/// An edit of an existing product: name, description, category, brand,
/// threshold, max level, price and barcode, and the archive flag.
///
/// Every field is optional because each one is a separate PATCH target: the
/// price lives on the selling unit, the threshold on the variant and the rest on
/// the product, and sending a field the user did not touch would write a value
/// nobody asked for.
class ProductEditDraft {
  const ProductEditDraft({
    required this.productId,
    required this.variantId,
    required this.sellingUnitId,
    this.baseName,
    this.description,
    this.categoryId,
    this.brandId,
    this.variantName,
    this.minStockThreshold,
    this.maxStockLevel,
    this.sellingPrice,
    this.barcodeQr,
    this.creditMarkupKind,
    this.creditMarkupValue,
    this.isActive,
    this.locationHint = '',
    this.storedAtId,
    this.image,
    this.sku,
    this.allowDiscount,
  });

  /// Null leaves the variant's SKU untouched.
  final String? sku;

  final int productId;
  final int variantId;

  /// 0 when the variant has no selling unit yet — a price cannot be PATCHed
  /// onto a row that does not exist, so the repository skips it.
  final int sellingUnitId;

  final String? baseName;
  final String? description;
  final int? categoryId;
  final int? brandId;
  final String? variantName;
  final double? minStockThreshold;
  final double? maxStockLevel;
  final double? sellingPrice;
  final String? barcodeQr;

  /// The utang markup, and ONLY when the clerk changed it. Null means "leave the
  /// stored markup alone", exactly like [sellingPrice]: an edit that only fixes a
  /// name must not wipe a configured markup.
  final String? creditMarkupKind;
  final double? creditMarkupValue;
  final bool? isActive;

  /// The never-discount flag, and ONLY when the clerk touched the switch. Null means
  /// "leave the stored flag alone", like [sellingPrice]: a save that only fixes a
  /// name must not silently re-enable discounting on cement.
  final bool? allowDiscount;

  /// Device-local, like the create draft's. Never in a PATCH body.
  final String locationHint;

  /// The product's SERVER pick-up point, and ONLY when the clerk changed it.
  ///
  /// Null means "leave the stored one alone". That is not politeness: the server
  /// refuses a NEW assignment of a deactivated location, so an edit that named the
  /// product's current (now inactive) location again would be answered
  /// `INVALID_STORAGE_LOCATION` and fail a save the clerk never asked to touch.
  final int? storedAtId;

  /// A REPLACEMENT photo, or null to leave the stored one alone.
  ///
  /// Null is the normal case: an edit that only touches a price must not send an
  /// image, because the server would replace the product's photo with nothing.
  final ProductImageUpload? image;

  Map<String, dynamic> get productBody => {
    if (baseName != null) 'base_name': baseName,
    if (description != null) 'description': description,
    if (categoryId != null) 'category': categoryId,
    if (brandId != null) 'brand': brandId,
    if (isActive != null) 'is_active': isActive,
    if (allowDiscount != null) 'allow_discount': allowDiscount,
    if (storedAtId != null) 'stored_at': storedAtId,
  };

  Map<String, dynamic> get variantBody => {
    if (variantName != null) 'variant_name': variantName,
    if (sku != null) 'sku': sku,
    if (minStockThreshold != null) 'min_stock_threshold': minStockThreshold,
    if (maxStockLevel != null) 'max_stock_level': maxStockLevel,
  };

  /// `variant`, `uom` and `conversion_factor` are frozen once the unit has been
  /// sold (400 `SELLING_UNIT_IN_USE`), so a price edit must never resend them.
  Map<String, dynamic> get sellingUnitBody => {
    if (sellingPrice != null) 'default_selling_price': sellingPrice,
    if (barcodeQr != null) 'barcode_qr': barcodeQr,
    if (creditMarkupKind != null) 'credit_markup_kind': creditMarkupKind,
    if (creditMarkupValue != null) 'credit_markup_value': creditMarkupValue,
  };
}
