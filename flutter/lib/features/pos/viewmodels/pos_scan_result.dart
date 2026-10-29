import 'package:client/data/models/pos_transaction.dart';

/// What one scan resolved to (Phase 6 decision 13).
///
/// Sealed rather than a nullable item plus flags: the till turns each outcome into
/// exactly one message or one cart action, so a half-resolved scan cannot be
/// represented. Every branch is visible at the call site in `_handleScan`.
sealed class ScanResult {
  const ScanResult();
}

/// The catalogue holds that exact selling unit — add it.
class ScanHit extends ScanResult {
  const ScanHit(this.item);

  final PosCatalogItem item;
}

/// The server knows the code, but the product or the variant is archived.
class ScanArchived extends ScanResult {
  const ScanArchived({required this.code, required this.productName});

  final String code;
  final String productName;
}

/// Nothing on the server has that code.
class ScanNotFound extends ScanResult {
  const ScanNotFound(this.code);

  final String code;
}

/// The code is live and unarchived, but this till cannot sell it right now.
///
/// The catalogue skips a variant at zero stock, so an ACTIVE product that just
/// sold out resolved to "archived" — a false sentence in front of the customer.
/// "Out of stock" is the honest reason, and it names the unit so the cashier can
/// tell the piece from the box.
class ScanOutOfStock extends ScanResult {
  const ScanOutOfStock({
    required this.code,
    required this.productName,
    required this.unit,
  });

  final String code;
  final String productName;
  final String unit;
}

/// The lookup itself failed (network, server, contract break) — NOT "not found".
class ScanError extends ScanResult {
  const ScanError(this.message);

  final String message;
}
