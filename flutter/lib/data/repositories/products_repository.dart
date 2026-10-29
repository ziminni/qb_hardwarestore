import 'package:client/data/models/product_writes.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/services/products_service.dart';

/// Which POST in the create chain failed.
///
/// The chain is three requests (product → variant → selling unit) and the server
/// has no transaction across them, so a failure halfway leaves a real row behind.
/// Naming the step is what lets the screen say "the variant could not be created"
/// instead of a generic "something went wrong" over a product that IS on the
/// server.
enum ProductWriteStep {
  product('product'),
  variant('variant'),
  sellingUnit('selling unit');

  const ProductWriteStep(this.label);

  final String label;
}

/// A refused write in the create chain: which step, and the server's words.
class ProductWriteException implements Exception {
  const ProductWriteException({required this.step, required this.message});

  final ProductWriteStep step;
  final String message;

  @override
  String toString() => message;
}

/// The repository layer between the inventory store and the products API.
///
/// It exists to keep the map's one-data-path invariant intact —
/// `View → ViewModel → Repository → Service → ApiClient` — so a viewmodel never
/// talks to Dio, and swapping the transport later touches this file rather than
/// every caller. Same shape as [AuthRepository].
///
/// The create chain lives here, in ONE method, because it is one user action:
/// "Add product" posting three rows through three call sites would scatter the
/// id-threading across widget code and turn a partial failure into an orphan
/// nobody reported.
class ProductsRepository {
  ProductsRepository(this.service);

  final ProductsService service;

  Future<ProductsSnapshot> loadCatalogue() => service.fetchCatalogue();

  /// Resolves a scanned code to the selling unit that owns it (decision 13).
  ///
  /// Returns the server's rows — including archived ones, whose names are how the
  /// till explains why a code cannot be sold. Read-only, so no [ProductWriteStep].
  Future<List<VariantUom>> lookupByBarcode(String code) =>
      service.lookupByBarcode(code);

  /// Creates the catalog item: product, its first variant, and that variant's
  /// factor-1 selling unit carrying the price and the optional barcode.
  ///
  /// Returns the three server ids in the order they were created. Nothing is
  /// invented locally: each id comes from the response of the previous POST, so a
  /// failure at step 2 reports the product id only through the error's step, and
  /// the caller reloads to show whatever really exists.
  Future<CreatedProduct> createProductChain(NewProductDraft draft) async {
    final productId = await _step(
      ProductWriteStep.product,
      () => service.createProduct(draft.productBody()),
    );
    final variantId = await _step(
      ProductWriteStep.variant,
      () => service.createVariant(draft.variantBody(productId)),
    );
    final sellingUnitId = await _step(
      ProductWriteStep.sellingUnit,
      () => service.createSellingUnit(
        draft.sellingUnitBody(variantId, draft.baseUomId),
      ),
    );
    return CreatedProduct(
      productId: productId,
      variantId: variantId,
      sellingUnitId: sellingUnitId,
    );
  }

  /// Applies an edit: one PATCH per row that actually changed.
  ///
  /// Which row each field lives on is the server's model, not a UI preference —
  /// the price on the selling unit, the thresholds on the variant, the rest on
  /// the product — so an empty body means "nothing to write here" and is skipped
  /// rather than sent as `{}`.
  Future<void> editProductChain(ProductEditDraft draft) async {
    await _step(
      ProductWriteStep.product,
      () => service.patchProduct(draft.productId, draft.productBody),
    );
    await _step(
      ProductWriteStep.variant,
      () => service.patchVariant(draft.variantId, draft.variantBody),
    );
    if (draft.sellingUnitId > 0) {
      await _step(
        ProductWriteStep.sellingUnit,
        () => service.patchSellingUnit(
          draft.sellingUnitId,
          draft.sellingUnitBody,
        ),
      );
    }
  }

  /// PATCHes one selling unit — today only its code (`barcode_qr`).
  ///
  /// A blank `barcodeQr` RESTORES the unit's own `QB` code: the server re-derives it
  /// (decision 16), which is why the field's hint says "leave blank".
  Future<void> patchSellingUnit(int id, Map<String, dynamic> body) => _step(
    ProductWriteStep.sellingUnit,
    () => service.patchSellingUnit(id, body),
  );

  /// Archive (`false`) or restore (`true`) through `PATCH is_active`.
  Future<void> setProductActive(int productId, bool isActive) => _step(
    ProductWriteStep.product,
    () => service.patchProduct(productId, {'is_active': isActive}),
  );

  Future<T> _step<T>(ProductWriteStep step, Future<T> Function() run) async {
    try {
      return await run();
    } on ProductsServiceException catch (error) {
      throw ProductWriteException(step: step, message: error.message);
    }
  }
}

/// The ids a successful create answered with.
class CreatedProduct {
  const CreatedProduct({
    required this.productId,
    required this.variantId,
    required this.sellingUnitId,
  });

  final int productId;
  final int variantId;
  final int sellingUnitId;
}
