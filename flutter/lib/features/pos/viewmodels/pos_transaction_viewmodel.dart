import 'package:client/data/models/customer.dart';
import 'package:client/data/models/pos_transaction.dart';
import 'package:client/data/models/product_tracking.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/repositories/customer_repository.dart';
import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:flutter/foundation.dart';

class PosTransactionViewmodel extends ChangeNotifier {
  PosTransactionViewmodel(
    this._inventory,
    this._tracking, {
    PosRepository? pos,
    CustomerRepository? customers,
  }) : _pos = pos ?? PosRepository(PosService()),
       _customers = customers {
    _inventory.addListener(_inventoryChanged);
    _tracking.addListener(_inventoryChanged);
  }

  final InventoryViewmodel _inventory;
  final ProductTrackingViewmodel _tracking;
  final PosRepository _pos;
  final CustomerRepository? _customers;

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
            barcode: record.variant.barcode,
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

  PosCatalogItem? findByBarcode(String value) {
    final barcode = value.trim().toLowerCase();
    if (barcode.isEmpty) return null;
    for (final item in _catalog) {
      if (item.barcode.trim().toLowerCase() == barcode) return item;
    }
    return null;
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
    notifyListeners();
    return null;
  }

  void removeLine(int index) {
    _lines.removeAt(index);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
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
    required String paymentMethod,
    required double amountPaid,
  }) async {
    if (_lines.isEmpty) return false;

    _isSubmitting = true;
    _submitError = null;
    _insufficientStockLineId = null;
    notifyListeners();

    try {
      // The buyer is the SELECTED customer when the cashier picked or created one, and the
      // seeded Walk-in Customer otherwise - a walk-in sale still cannot omit the customer,
      // because the FK is not nullable (decision 06 section 2).
      final buyer =
          _selectedCustomer?.id ??
          (_walkInCustomerId ??= await _pos.walkInCustomerId());
      // Snapshot the lines being sold: the receipt must describe THIS sale, not
      // whatever the cart holds when the response lands.
      final sold = List<PosCartLine>.of(_lines);
      final result = await _pos.checkout(
        customerId: buyer,
        items: [
          for (final line in sold)
            PosCheckoutItem(
              variantUomId: line.variantUomId,
              quantity: line.quantity,
              unitPrice: line.unitPrice,
            ),
        ],
        payments: [
          PosCheckoutPayment(method: paymentMethod, amountTendered: amountPaid),
        ],
      );

      // The receipt's numbers are the SERVER's, not the cart's arithmetic: decision
      // 06 section 1 says the response is the finished transaction.
      _receipts.insert(
        0,
        PosReceipt(
          reference: result.transactionNo,
          officialReceiptNumber: result.orNumber,
          createdAt: result.transDate,
          lines: List.unmodifiable(sold),
          paymentMethod: paymentMethod,
          amountPaid: amountPaid,
          total: result.grandTotal,
        ),
      );
      _lines.clear();
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
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  String _quantity(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

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
