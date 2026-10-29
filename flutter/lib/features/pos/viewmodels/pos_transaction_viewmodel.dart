import 'dart:math';

import 'package:client/data/models/customer.dart';
import 'package:client/data/models/held_cart.dart';
// `PosCheckoutResult` lives in TWO libraries (the model file kept the old
// response shape, pos_service.dart owns the checkout one). The checkout path uses
// the service's, so the stale duplicate is hidden rather than left ambiguous.
import 'package:client/data/models/pos_transaction.dart' hide PosCheckoutResult;
import 'package:client/data/models/product_tracking.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/repositories/customer_repository.dart';
import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/services/held_cart_service.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_scan_result.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:flutter/foundation.dart';

class PosTransactionViewmodel extends ChangeNotifier {
  PosTransactionViewmodel(
    this._inventory,
    this._tracking, {
    PosRepository? pos,
    CustomerRepository? customers,
    HeldCartService? heldCarts,
    ProductsRepository? products,
  }) : _pos = pos ?? PosRepository(PosService()),
       _customers = customers,
       _injectedHeldCarts = heldCarts,
       _injectedProducts = products {
    _inventory.addListener(_inventoryChanged);
    _tracking.addListener(_inventoryChanged);
  }

  final InventoryViewmodel _inventory;
  final ProductTrackingViewmodel _tracking;
  final PosRepository _pos;
  final CustomerRepository? _customers;

  /// The parked-cart endpoint, built on FIRST USE for the same reason as
  /// [_customerRepo]: a test about the cart must not construct a transport it never
  /// uses.
  final HeldCartService? _injectedHeldCarts;
  HeldCartService get _heldCartService =>
      _injectedHeldCarts ?? HeldCartService();

  /// The catalogue endpoint, for the scan fallback (decision 13). Injected by tests
  /// and built on FIRST USE, so a scan-free test never touches it.
  final ProductsRepository? _injectedProducts;
  ProductsRepository get _productRepo =>
      _injectedProducts ?? ProductsRepository(ProductsService());

  /// Built on FIRST USE, not in the constructor.
  ///
  /// Eager construction meant every test that only wanted the cart still built a real
  /// `CustomerService` over `ApiClient.instance`, and any test whose `ApiClient.init()` had
  /// not run died with `LateInitializationError: Field 'dio' has not been initialized` -
  /// a failure about the transport, in tests about the cart.
  CustomerRepository get _customerRepo =>
      _customers ?? CustomerRepository(CustomerService());
  final List<PosCartLine> _lines = [];
  final List<PosReceipt> _receipts = [];
  String _query = '';
  bool _isSubmitting = false;
  String? _submitError;

  /// The `Idempotency-Key` of the payment attempt in progress, or null when no
  /// attempt is pending.
  ///
  /// The server answers a repeat of (cashier, key) with the ORIGINAL transaction
  /// instead of writing a second one, so this value is the difference between a
  /// retry and a double sale. It is created on the FIRST submit of an attempt and
  /// reused by every retry of it, then dropped on success - or whenever the body
  /// could differ (cart edited, customer changed), because a changed body under a
  /// spent key earns a 409 `IDEMPOTENCY_KEY_REUSED` instead of ringing the sale.
  String? _attemptKey;
  int? _walkInCustomerId;
  int? _insufficientStockLineId;
  Customer? _selectedCustomer;
  final List<Customer> _customerList = [];
  String? _customersError;
  CustomerLedgerSummary? _ledgerSummary;
  String? _ledgerError;
  bool _isLoadingLedger = false;

  List<PosCartLine> get lines => List.unmodifiable(_lines);
  List<PosReceipt> get receipts => List.unmodifiable(_receipts);
  double get subtotal => _lines.fold(0, (sum, line) => sum + line.total);
  double get total => subtotal;
  int get itemCount => _lines.length;

  /// True while a sale is in flight. The submit action must be disabled, because the
  /// sale is one atomic server operation and a double submit would be two sales.
  bool get isSubmitting => _isSubmitting;

  /// The last submit failure, safe to show a cashier. Null after a success.
  String? get submitError => _submitError;

  /// The key the next submit will send, once an attempt has started.
  ///
  /// Null before the first press and after a success; tests and the error message
  /// for `IDEMPOTENCY_KEY_REUSED` both need to see which attempt is in flight.
  String? get idempotencyKey => _attemptKey;

  /// The parked cart the last successful sale removed, or null.
  ///
  /// The till posts the sale; the Held transactions list owns the ROWS. This is the
  /// one-shot hand-off between them, consumed by the page with
  /// [takeCompletedHeldCartId] so a rebuild cannot re-remove an id.
  int? _completedHeldCartId;
  int? get completedHeldCartId => _completedHeldCartId;

  /// Reads and clears [completedHeldCartId].
  int? takeCompletedHeldCartId() {
    final id = _completedHeldCartId;
    _completedHeldCartId = null;
    return id;
  }

  /// The parked cart this basket was RESUMED from, or null.
  ///
  /// Decision 05 says a parked basket is completed through
  /// `POST /held-carts/{id}/complete/`, where the server rings the sale and deletes the
  /// cart in one transaction. Remembering the id is what makes that possible - and what
  /// stops the defect this replaces: the till posted a resumed basket through
  /// `/transactions/`, left the parked cart on the server, and the same basket could be
  /// resumed and sold a second time.
  int? _resumedCartId;
  int? get resumedCartId => _resumedCartId;

  /// The basket as it stood when it was resumed, so `submit` can tell an UNCHANGED
  /// parked basket (safe to `complete`) from one the cashier edited (whose server copy
  /// is stale, so it must be rung from the till and the cart voided afterwards).
  String? _resumedSignature;

  /// Why the parked cart could not be removed after an EDITED basket was sold, or null.
  ///
  /// The sale is written and the money is in the drawer, so this is never a failed sale:
  /// it is a row the cashier must void by hand, because the cart surviving means the
  /// basket could be resumed and sold again. The page shows it as a warning.
  String? _heldCartCleanupError;
  String? get heldCartCleanupError => _heldCartCleanupError;

  /// Everything about the basket that a parked cart holds, as one comparable string.
  ///
  /// The cart's own copy is what `complete` sells, so the comparison has to cover the
  /// same facts: the selling units, their quantities and prices, and the account the
  /// sale is addressed to.
  String _basketSignature() => [
    for (final line in _lines)
      '${line.variantUomId}:${line.quantity}:${line.unitPrice}',
    'customer:${_selectedCustomer?.id}',
  ].join('|');

  bool _resumedBasketIsUnchanged() =>
      _resumedSignature != null && _resumedSignature == _basketSignature();

  void _forgetResumedCart() {
    _resumedCartId = null;
    _resumedSignature = null;
  }

  /// Removes the parked copy of a basket that was rung from the till instead.
  ///
  /// Never throws: the sale has already been written, so turning a failed DELETE into a
  /// failed sale would be a lie about money. A failure is REPORTED instead, naming the
  /// cart the cashier must void, because a surviving cart can be resumed and sold again.
  Future<void> _voidParkedCart(int cartId) async {
    try {
      await _heldCartService.voidCart(cartId);
      _completedHeldCartId = cartId;
    } on HeldCartServiceException catch (error) {
      _heldCartCleanupError =
          'The sale was completed, but parked cart #$cartId could not be removed '
          '(${error.message}) Void it in Held transactions, or it can be sold again.';
    }
  }

  /// 32 hex characters from a CSPRNG.
  ///
  /// Well inside the server's 64-character cap, and NOT a UUID dependency: the
  /// server only requires uniqueness per cashier, and `Random.secure()` gives that
  /// without adding a package.
  static String _newAttemptKey() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  /// Forgets the attempt key because the next submit will sell a DIFFERENT body.
  void _dropAttemptKey() => _attemptKey = null;

  /// The cart line the server rejected for stock, or null.
  ///
  /// Non-null means the failure is **recoverable in place**, as decision 06 section 3
  /// requires: the sale did not happen, the cart is intact, and this is the row to fix.
  /// A terminal failure (a 5xx, or a stock rejection naming a variant no line sells)
  /// leaves this null rather than pointing the cashier at an innocent row.
  ///
  /// The server blames a *variant* while the cart is keyed by `VariantUom`, so the id
  /// is mapped through the catalogue; the cart holds the row, the server holds the
  /// variant, and only the catalogue knows which units a variant sells.
  int? get insufficientStockLineId => _insufficientStockLineId;

  /// Who this sale is addressed to, or null for an **anonymous** sale.
  ///
  /// Null is the DEFAULT and not an error state: decision 14 made a walk-in stop being a
  /// customer record, so an anonymous sale is the ordinary case and reuses the seeded
  /// Walk-in Customer without asking the buyer anything. A non-null value means the cashier
  /// picked or created a named account, and the debt that may follow belongs to someone
  /// collectable.
  Customer? get selectedCustomer => _selectedCustomer;

  /// Whether the sale being rung up is ANONYMOUS, by the SERVER's definition.
  ///
  /// The server refuses a shortfall when `customer.customer_type == WALK_IN`, so anonymity is
  /// a property of the customer's TYPE, not of the selection being null. A `Customer` typed
  /// walk-in is selected and still cannot owe - treating it as named let the underpayment
  /// dialog promise a receivable the server then refused, which is the dead end task 6
  /// removed.
  ///
  /// This lives on the viewmodel so the rule has ONE home and can be tested; the dialog's
  /// copy and the picker's answer both read it rather than re-deriving it.
  bool get isAnonymousSelection => _selectedCustomer?.isWalkIn ?? true;

  /// The live customer list the picker searches, loaded by [loadCustomers].
  List<Customer> get customers => List.unmodifiable(_customerList);

  /// Set when the list could not be loaded. The picker shows this rather than looking empty,
  /// because "no customers" and "could not ask the server" are different statements.
  String? get customersError => _customersError;

  /// Loads the picker's list.
  ///
  /// On failure the existing list is KEPT: emptying it would read as "this store has no
  /// customers", which is a different and false claim, and the cashier could not tell the
  /// difference between a network blip and an empty database.
  Future<void> loadCustomers() async {
    try {
      final loaded = await _customerRepo.fetchCustomers();
      _customerList
        ..clear()
        ..addAll(loaded);
      _customersError = null;
    } on CustomerServiceException catch (error) {
      _customersError = error.message;
    }
    notifyListeners();
  }

  /// What the checkout shows as the buyer. Never empty, so the cashier can always tell who
  /// the sale is for. The `(anonymous)` marker matters: it is the difference between "this
  /// will be paid in full" and "this may become someone's debt".
  String get customerLabel =>
      _selectedCustomer?.name ?? 'Walk-in Customer (anonymous)';

  /// Chooses the buyer, or null to go back to an anonymous sale.
  ///
  /// Clears any loaded balance: a summary belonging to the PREVIOUS customer must never be
  /// displayed against the new one, which would show the cashier someone else's debt.
  void selectCustomer(Customer? customer) {
    if (_selectedCustomer?.id != customer?.id) {
      _ledgerSummary = null;
      _ledgerError = null;
      // A different buyer is a different sale body, so a key spent on the previous
      // attempt must not be replayed against this one.
      _dropAttemptKey();
    }
    _selectedCustomer = customer;
    notifyListeners();
  }

  /// The selected customer's outstanding utang, once loaded. Null for an anonymous sale.
  CustomerLedgerSummary? get ledgerSummary => _ledgerSummary;

  /// Set when the balance could not be loaded. The panel shows this rather than a zero
  /// balance, because a zero is a claim that the customer owes nothing.
  String? get ledgerError => _ledgerError;

  bool get isLoadingLedger => _isLoadingLedger;

  /// Loads the utang for whoever is currently selected.
  ///
  /// An ANONYMOUS sale makes no request at all: decision 14 says a walk-in cannot owe, so
  /// there is no balance to ask for - and asking would be asking about the shared placeholder.
  Future<void> loadLedgerForSelection() async {
    final customer = _selectedCustomer;
    if (customer == null) {
      _ledgerSummary = null;
      _ledgerError = null;
      _isLoadingLedger = false;
      notifyListeners();
      return;
    }

    _isLoadingLedger = true;
    _ledgerError = null;
    notifyListeners();

    try {
      final summary = await _customerRepo.fetchLedgerSummary(customer.id);
      // A response that lands after the cashier moved on belongs to the old customer - and
      // that applies to a FAILURE as much as a success. Guarding only the success path meant
      // a late failure for the previous customer could leave its message sitting over the
      // new one, and the panel reads the error BEFORE the summary.
      if (_selectedCustomer?.id == customer.id) {
        _ledgerSummary = summary;
        _ledgerError = null;
      }
    } on CustomerServiceException catch (error) {
      if (_selectedCustomer?.id == customer.id) {
        _ledgerError = error.message;
        _ledgerSummary = null;
      }
    } finally {
      _isLoadingLedger = false;
      notifyListeners();
    }
  }

  /// Records a customer at the counter and selects them.
  ///
  /// Returns null on success, or a message safe to show a cashier. On failure NOTHING is
  /// selected - selecting a customer that was never created would post the sale, and any
  /// utang with it, to a record that does not exist.
  ///
  /// The record is deliberately minimal (name + type): decision 14's locked decision 1 keeps
  /// contact details, TIN and the credit limit out of the cashier's hands at the till.
  Future<String?> createAndSelectCustomer({
    required String name,
    required CustomerType type,
  }) async {
    try {
      final created = await _customerRepo.createCustomer(
        name: name,
        type: type,
      );
      // Routed through selectCustomer so the utang state is cleared by the SAME rule that
      // clears it for a pick. Assigning the field directly left the previous customer's
      // balance on screen under the new customer's name whenever the caller did not follow
      // with loadLedgerForSelection - reachable because the picker's barrier is dismissible
      // while the create is in flight, so the page can take its "cancelled" early return.
      selectCustomer(created);
      return null;
    } on CustomerServiceException catch (error) {
      return error.message;
    }
  }

  /// The cart line selling [variantId], or null when the cart sells no such variant.
  int? _lineForVariant(int? variantId) {
    if (variantId == null) return null;
    for (final line in _lines) {
      if (_rowFor(line)?.variantId == variantId) return line.variantUomId;
    }
    return null;
  }

  List<PosCatalogItem> get _catalog {
    final items = <PosCatalogItem>[];
    for (final record in _inventory.stockRecords) {
      if (!record.product.isActive ||
          !record.variant.isActive ||
          _inventory.stockOnHandFor(record.variant.id) <= 0) {
        continue;
      }
      final tracking = _tracking.configurationFor(record.product.baseName);
      final usesTracking =
          tracking != null &&
          tracking.baseUnit.toLowerCase() ==
              record.variant.baseUomCode.toLowerCase();
      // Decision 06 section 2: the rows are built from the variant's REAL selling
      // units, because that is both what the catalogue can actually sell and the
      // only source of a valid `variantUomId` for the payload. Tracking supplies the
      // conversion factor and package price for whichever units it recognises; it can
      // no longer add a unit the catalogue does not sell, because such a row has no
      // id to submit.
      //
      // Building from tracking's labels instead produced DUPLICATE ids: variant 19 is
      // tracked with two sale units ('kg', 'g') but carries a single selling unit, so
      // both rows resolved to id 19. That silently merged two cart lines in `addLine`
      // (which de-duplicates on `variantUomId`) and made `complete()` price and deduct
      // a 'g' line as 'kg' (it takes the FIRST row matching the id).
      final sellableUnits = <String, VariantUom>{};
      for (final uom in record.variant.sellingUoms) {
        final code = uom.uomCode.trim();
        if (code.isEmpty) continue;
        sellableUnits.putIfAbsent(code.toLowerCase(), () => uom);
      }
      for (final uom in sellableUnits.values) {
        final unit = uom.uomCode;
        final factor = usesTracking ? _conversionFactor(tracking, unit) : 1.0;
        final configuredPackagePrice =
            usesTracking &&
                unit.toLowerCase() == tracking.packageType.toLowerCase()
            ? tracking.packageSellingPrice
            : 0.0;
        items.add(
          PosCatalogItem(
            variantUomId: uom.id,
            variantId: record.variant.id,
            productName: record.product.baseName,
            variantName: record.variant.variantName,
            unit: unit,
            // Decision 11 F3: the unit's OWN code. `record.variant.barcode` is the
            // variant's first non-blank code, so a piece and a box of one variant
            // answered to the same code and the box was unscannable.
            barcode: uom.barcodeQr,
            conversionFactor: factor,
            unitPrice: configuredPackagePrice > 0
                ? configuredPackagePrice
                : (_inventory.priceFor(record.variant.id) ?? 0) * factor,
            availableBaseStock: _inventory.stockOnHandFor(record.variant.id),
          ),
        );
      }
    }
    return items;
  }

  List<PosCatalogItem> get filteredProducts {
    final matched = _query.isEmpty
        ? _catalog
        : _catalog
              .where(
                (item) =>
                    item.productName.toLowerCase().contains(_query) ||
                    item.variantName.toLowerCase().contains(_query) ||
                    item.barcode.toLowerCase().contains(_query) ||
                    item.unit.toLowerCase().contains(_query),
              )
              .toList(growable: false);
    final variants = <int, PosCatalogItem>{};
    for (final item in matched) {
      variants.putIfAbsent(item.variantId, () => item);
    }
    return variants.values.toList(growable: false);
  }

  List<PosCatalogItem> saleOptionsFor(PosCatalogItem product) => _catalog
      .where((item) => item.variantId == product.variantId)
      .toList(growable: false);

  /// The catalogue line whose OWN selling unit carries [value], or null.
  ///
  /// Both sides are normalised the one way the server stores codes
  /// ([VariantUom.normalise]), so a scanner's padded lower-case text matches the
  /// stored `QB000013-0` (decision 11).
  PosCatalogItem? findByBarcode(String value) {
    final barcode = VariantUom.normalise(value);
    if (barcode.isEmpty) return null;
    for (final item in _catalog) {
      if (VariantUom.normalise(item.barcode) == barcode) return item;
    }
    return null;
  }

  /// Resolves a scanned code to the exact selling unit it names (decision 13).
  ///
  /// Loaded catalogue first — the common case, no round trip. On a miss ONE server
  /// lookup, then a catalogue reload, because the usual reason a code is missing at
  /// the till is that the unit was created after the till opened. No retry loop: a
  /// second scan is the retry.
  Future<ScanResult> resolveScan(String raw) async {
    final code = VariantUom.normalise(raw);
    if (code.isEmpty) return const ScanNotFound('');
    final cached = findByBarcode(code);
    if (cached != null) return ScanHit(cached);

    final List<VariantUom> rows;
    try {
      rows = await _productRepo.lookupByBarcode(code);
    } on ProductsServiceException catch (error) {
      // A failed lookup is NOT "no product has that code": the cashier would go
      // hunting for a product that may well exist.
      return ScanError(error.message);
    }
    if (rows.isEmpty) return ScanNotFound(code);

    final row = rows.first;
    if (!row.productIsActive || !row.variantIsActive) {
      // Archived: the server still holds the code, so reloading cannot help. The
      // names are what let the till say WHICH product this was.
      return ScanArchived(code: code, productName: row.productName);
    }

    // Active on the server but missing from the catalogue: the unit was created
    // after the till loaded. Reload once, then look again.
    await _inventory.load();
    final reloaded = findByBarcode(code);
    if (reloaded != null) return ScanHit(reloaded);
    if (_inventory.loadError case final message?) return ScanError(message);
    return ScanArchived(code: code, productName: row.productName);
  }

  void setQuery(String value) {
    _query = value.trim().toLowerCase();
    notifyListeners();
  }

  void _inventoryChanged() => notifyListeners();

  @override
  void dispose() {
    _inventory.removeListener(_inventoryChanged);
    _tracking.removeListener(_inventoryChanged);
    super.dispose();
  }

  String? addLine(PosCatalogItem item, double quantity) {
    if (quantity <= 0) return 'Enter a quantity greater than zero.';
    final index = _lines.indexWhere(
      (line) => line.variantUomId == item.variantUomId,
    );
    final cartQuantity = index < 0 ? 0.0 : _lines[index].quantity;
    // Walked as a loop rather than a where/fold chain so a stale line can be SKIPPED.
    var reservedBaseStock = 0.0;
    for (final line in _lines) {
      final option = _rowFor(line);
      // A line whose catalogue row is gone reserves nothing, and validate() refuses
      // the sale while it is there, so ignoring it here cannot oversell.
      if (option == null) continue;
      if (option.variantId != item.variantId) continue;
      reservedBaseStock += line.quantity * option.conversionFactor;
    }
    final requestedBaseStock = quantity * item.conversionFactor;
    if (reservedBaseStock + requestedBaseStock > item.availableBaseStock) {
      return 'Only ${_quantity(item.availableSaleQuantity)} ${item.unit} available.';
    }
    if (index < 0) {
      _lines.add(
        PosCartLine(
          variantUomId: item.variantUomId,
          productName: item.productName,
          variantName: item.variantName,
          quantity: quantity,
          unit: item.unit,
          unitPrice: item.unitPrice,
          availableQuantity: item.availableSaleQuantity,
        ),
      );
    } else {
      _lines[index] = _lines[index].copyWith(quantity: cartQuantity + quantity);
    }
    // The payload changed, so any attempt already started is no longer this sale.
    _dropAttemptKey();
    notifyListeners();
    return null;
  }

  void removeLine(int index) {
    _lines.removeAt(index);
    _dropAttemptKey();
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    // The till no longer holds the parked basket, so a later sale must not try to
    // complete (or void) a cart this basket came from.
    _forgetResumedCart();
    _dropAttemptKey();
    notifyListeners();
  }

  /// Restores a PARKED basket into the till (Phase 3 resume).
  ///
  /// Three rules, each of which the counter depends on:
  ///
  /// * **The held prices are the quoted prices.** The cart is rebuilt with the
  ///   prices the customer was told when the basket was parked, not today's
  ///   catalogue price — a resumed basket that silently re-prices is a different
  ///   sale from the one the customer agreed to.
  /// * **A line whose catalogue row is gone is KEPT, not dropped.** Dropping it
  ///   would silently shorten the customer's order; keeping it makes
  ///   [validate] name the row and refuse the sale until the cashier removes it.
  /// * **The cart is REPLACED.** Resume means "this basket", so the till holds
  ///   exactly what was parked.
  ///
  /// Names and units come from the catalogue because a held line carries only
  /// ids, a quantity and a price (`HeldCartItem`); the catalogue is the only
  /// place that knows a `variant_uom` id sells kilograms or pieces.
  ///
  /// Returns how many lines were restored.
  int loadHeldCart(HeldCart cart) {
    _lines.clear();
    // A resumed basket is a new body, so the parked till starts a new attempt.
    _dropAttemptKey();
    for (final item in cart.items) {
      // One lookup per line: the row supplies names and unit, and null means the
      // catalogue no longer sells that unit (kept anyway, see above).
      final row = _catalogRowFor(item.variantUom);
      _lines.add(
        PosCartLine(
          variantUomId: item.variantUom,
          productName: row?.productName ?? 'Held item',
          variantName: row?.variantName ?? '',
          quantity: item.qty,
          unit: row?.unit ?? '',
          unitPrice: item.unitPrice,
          availableQuantity: row?.availableSaleQuantity ?? 0,
        ),
      );
    }
    // A parked cart keeps its account: a basket held for a named customer must
    // come back addressed to them, or the resumed sale would post to nobody and
    // any utang with it would land nowhere.
    final customerId = cart.customerId;
    if (customerId != null && cart.customerName != null) {
      selectCustomer(
        Customer(id: customerId, name: cart.customerName!, customerType: ''),
      );
    }
    // Remember WHICH parked cart this is, and what it looked like when it arrived:
    // `submit` completes the cart when nothing changed (server rings and deletes it
    // atomically) and rings from the till when the cashier edited it.
    _resumedCartId = cart.id;
    _resumedSignature = _basketSignature();
    notifyListeners();
    return _lines.length;
  }

  /// The catalogue row selling [variantUomId], or null when it no longer exists.
  ///
  /// Looked up by `variantUomId` rather than by line, because a held line has no
  /// [PosCartLine] to look up yet. Nullable on purpose: the same reasoning as
  /// [_rowFor] — a missing row must not throw inside a resume.
  PosCatalogItem? _catalogRowFor(int variantUomId) {
    for (final item in _catalog) {
      if (item.variantUomId == variantUomId) return item;
    }
    return null;
  }

  String? validate() {
    if (_lines.isEmpty) return 'Add at least one product to the transaction.';
    final requestedByVariant = <int, double>{};
    for (final line in _lines) {
      final item = _rowFor(line);
      // The catalogue is rebuilt from live stock and skips a variant at zero, so a
      // line can outlive its row. Refusing by NAME is the honest outcome: silently
      // dropping the line would submit a sale the cashier did not assemble, and
      // pricing it anyway would sell something the catalogue says is gone.
      if (item == null) {
        return '${line.productName} ${line.variantName} is no longer '
            'available. Remove it from the cart.';
      }
      requestedByVariant[item.variantId] =
          (requestedByVariant[item.variantId] ?? 0) +
          line.quantity * item.conversionFactor;
      if (requestedByVariant[item.variantId]! > item.availableBaseStock) {
        return '${line.productName}: the combined units exceed available stock.';
      }
    }
    return null;
  }

  /// The catalogue row a cart line refers to, or null when the row is gone.
  ///
  /// The catalogue is a getter rebuilt from live stock and it SKIPS any variant whose
  /// stock has reached zero. A line can outlive its row: a server refresh (`load()`) or
  /// a sale on another screen sharing this InventoryViewmodel can drain the variant
  /// while the basket still holds it. Every lookup by line must go through here,
  /// because `_catalog.firstWhere(...)` with no `orElse` throws
  /// `StateError: Bad state: No element` and takes the whole POS down.
  ///
  /// Found by the Phase 3 review's adversarial pass, which reproduced the crash before
  /// it was fixed. `addLine`'s reserved-stock arithmetic threw first, on the line it
  /// was not even looking at.
  PosCatalogItem? _rowFor(PosCartLine line) {
    for (final item in _catalog) {
      if (item.variantUomId == line.variantUomId) return item;
    }
    return null;
  }

  /// Completes the sale ON THE SERVER, then clears the cart.
  ///
  /// Decision 06 sections 3 and 5. Three rules are load-bearing here:
  ///
  /// * The cart is cleared **only** after a successful sale. `process_sale` runs in one
  ///   `transaction.atomic()`, so a failure rolls back wholesale - the server state is
  ///   unchanged, and the cashier's basket must survive so it can be corrected and
  ///   retried. Clearing optimistically would lose a real order.
  /// * An empty cart is never submitted. The server has no guard on an empty `items`
  ///   list, so an empty sale would **succeed** and mint a zero-value receipt.
  /// * Insufficient stock and a server failure both keep the cart, but they are
  ///   different messages. The distinction comes from the server's code, never from
  ///   the status alone.
  ///
  /// Returns whether the sale was confirmed, so a caller cannot announce success
  /// unconditionally.
  Future<bool> submit({
    required TenderMethod method,
    required double amountPaid,
  }) async {
    if (_lines.isEmpty) return false;

    _isSubmitting = true;
    _submitError = null;
    _insufficientStockLineId = null;
    _heldCartCleanupError = null;
    notifyListeners();

    try {
      // Snapshot the lines being sold: the receipt must describe THIS sale, not
      // whatever the cart holds when the response lands.
      final sold = List<PosCartLine>.of(_lines);
      // One key per ATTEMPT: created on the first press and reused by a retry, so
      // a dropped response cannot turn one basket into two sales.
      final attemptKey = _attemptKey ??= _newAttemptKey();
      // The tender goes on the wire as a CODE, never as the label the cashier read.
      final payments = [
        PosCheckoutPayment(method: method.code, amountTendered: amountPaid),
      ];
      final resumedCartId = _resumedCartId;
      // An UNCHANGED resumed basket is sold through the parked cart, so the server
      // writes the sale and deletes the cart in ONE transaction (decision 05). A basket
      // the cashier edited must NOT go that way: `complete` sells the SERVER's copy,
      // which is now stale, so it would ring what they removed.
      final completeCartId =
          resumedCartId != null && _resumedBasketIsUnchanged()
          ? resumedCartId
          : null;

      final PosCheckoutResult result;
      if (completeCartId != null) {
        result = PosCheckoutResult.fromJson(
          await _heldCartService.complete(
            completeCartId,
            payments: payments,
            idempotencyKey: attemptKey,
          ),
        );
        _completedHeldCartId = completeCartId;
      } else {
        // The buyer is the SELECTED customer when the cashier picked or created one, and
        // the seeded Walk-in Customer otherwise - a walk-in sale still cannot omit the
        // customer, because the FK is not nullable (decision 06 section 2).
        final buyer =
            _selectedCustomer?.id ??
            (_walkInCustomerId ??= await _pos.walkInCustomerId());
        result = await _pos.checkout(
          customerId: buyer,
          items: [
            for (final line in sold)
              PosCheckoutItem(
                variantUomId: line.variantUomId,
                quantity: line.quantity,
                unitPrice: line.unitPrice,
              ),
          ],
          payments: payments,
          idempotencyKey: attemptKey,
        );
        if (resumedCartId != null) {
          // The edited basket is sold, so the parked copy must not survive to be resumed
          // and sold again. Voided AFTER the 201: voiding first would destroy the cart
          // for a sale that then failed.
          await _voidParkedCart(resumedCartId);
        }
      }

      // The receipt's numbers are the SERVER's, not the cart's arithmetic: decision
      // 06 section 1 says the response is the finished transaction. That now covers
      // the LINES too - the server prices from VariantUOM.default_selling_price and
      // ignores the client's `unit_price`, so a receipt printed from the cart could
      // print a price the customer was never charged.
      _receipts.insert(
        0,
        PosReceipt(
          reference: result.transactionNo,
          officialReceiptNumber: result.orNumber,
          createdAt: result.transDate,
          lines: List.unmodifiable(_serverLines(result.lines, sold)),
          paymentMethod: method.code,
          amountPaid: amountPaid,
          total: result.grandTotal,
        ),
      );
      _lines.clear();
      // The basket is sold, so it is no longer a resumed cart: a second sale must not
      // try to complete the same parked cart again.
      _forgetResumedCart();
      // The sale is written, so this attempt is finished and its key is spent.
      _dropAttemptKey();
      return true;
    } on PosServiceException catch (error) {
      _submitError = error.message;
      // Decision 06 section 3 separates a recoverable stock rejection from a terminal
      // failure. Recording WHICH line is what makes it recoverable: the cashier is
      // told which row to fix instead of being left to re-read the basket.
      _insufficientStockLineId = error.isInsufficientStock
          ? _lineForVariant(error.variantId)
          : null;
      return false;
    } on HeldCartServiceException catch (error) {
      // A resumed basket is sold by the SERVER's `complete` action, which runs
      // `process_sale` — so its refusals (stock, credit limit, no open shift) arrive here
      // with the same codes. The cart stays: nothing was written.
      _submitError = error.message;
      _insufficientStockLineId = error.isInsufficientStock
          ? _lineForVariant(error.variantId)
          : null;
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  String _quantity(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  /// The receipt's lines, priced by the SERVER.
  ///
  /// The response carries ids, quantities and money but no product names, so each
  /// server line borrows the NAME and UNIT of the cart line it belongs to and takes
  /// its quantity and price from the server. Falls back to the cart snapshot when
  /// the response omitted `items`, so a cosmetic omission still prints a receipt
  /// for a sale that really happened.
  List<PosCartLine> _serverLines(
    List<PosCheckoutLine> serverLines,
    List<PosCartLine> sold,
  ) {
    if (serverLines.isEmpty) return sold;
    return [
      for (final line in serverLines)
        PosCartLine(
          variantUomId: line.variantUomId,
          productName:
              _soldLine(line.variantUomId, sold)?.productName ?? 'Sale line',
          variantName: _soldLine(line.variantUomId, sold)?.variantName ?? '',
          quantity: line.quantity,
          unit: _soldLine(line.variantUomId, sold)?.unit ?? '',
          unitPrice: line.unitPrice,
          availableQuantity:
              _soldLine(line.variantUomId, sold)?.availableQuantity ?? 0,
        ),
    ];
  }

  /// The sold cart line for [variantUomId], or null when the server wrote a line
  /// the cart no longer names.
  PosCartLine? _soldLine(int variantUomId, List<PosCartLine> sold) {
    for (final line in sold) {
      if (line.variantUomId == variantUomId) return line;
    }
    return null;
  }

  double _conversionFactor(ProductTrackingConfiguration tracking, String unit) {
    if (unit.toLowerCase() == tracking.packageType.toLowerCase()) {
      return tracking.stockForm == ProductStockForm.standardLengths
          ? tracking.standardLength
          : tracking.packageSize;
    }
    const factors = {
      'g': .001,
      'kg': 1.0,
      'mm': .001,
      'cm': .01,
      'meter': 1.0,
      'm': 1.0,
      'inch': .0254,
      'foot': .3048,
      'ml': .001,
      'l': 1.0,
      'piece': 1.0,
    };
    final from = factors[unit.toLowerCase()] ?? 1;
    final base = factors[tracking.baseUnit.toLowerCase()] ?? 1;
    return from / base;
  }
}
