import 'dart:convert';

import 'package:client/data/models/customer.dart';
import 'package:client/data/models/sale_discount.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Standing discount preset attached to a regular customer profile.
///
/// When a customer with a standing discount is selected in "Who is this sale
/// for?", the transaction's Discount section is pre-populated automatically
/// while remaining editable by the cashier.
enum CustomerDiscountType {
  none('None', 'No automatic discount'),
  seniorCitizen('Senior Citizen (20%)', '20% statutory Senior Citizen discount'),
  pwd('PWD (20%)', '20% statutory Person with Disability discount'),
  customPercent('Regular % Discount', 'Standing percentage discount'),
  customAmount('Fixed ₱ Discount', 'Standing peso discount');

  const CustomerDiscountType(this.label, this.description);

  final String label;
  final String description;

  static CustomerDiscountType fromCode(String? raw) {
    for (final value in CustomerDiscountType.values) {
      if (value.name == raw) return value;
    }
    return CustomerDiscountType.none;
  }
}

/// Rich cashier-side profile for a regular customer.
///
/// Pairs with the server [Customer] record to hold phone number, delivery /
/// billing address, and any standing discount preset (e.g., Mang Kanor as a
/// Senior Citizen regular, or Manang Rosa with saved utang & delivery details).
class CustomerProfile {
  const CustomerProfile({
    this.customerId,
    required this.name,
    this.type = CustomerType.regular,
    this.phone = '',
    this.address = '',
    this.discountType = CustomerDiscountType.none,
    this.discountValue = 0,
    this.discountReason = '',
    this.idNumber = '',
  });

  final int? customerId;
  final String name;
  final CustomerType type;
  final String phone;
  final String address;
  final CustomerDiscountType discountType;
  final double discountValue;
  final String discountReason;

  /// Optional Senior Citizen / OSCA / PWD ID or account reference note.
  final String idNumber;

  bool get hasDiscount => toPosDiscount != null;

  bool get hasContactInfo =>
      phone.trim().isNotEmpty || address.trim().isNotEmpty;

  /// Effective discount value (20% for Senior Citizen / PWD when unset).
  double get effectiveDiscountValue => switch (discountType) {
    CustomerDiscountType.none => 0,
    CustomerDiscountType.seniorCitizen ||
    CustomerDiscountType.pwd => discountValue > 0 ? discountValue : 20,
    CustomerDiscountType.customPercent ||
    CustomerDiscountType.customAmount => discountValue,
  };

  /// Effective discount reason pre-filled into the POS Discount section.
  String get effectiveDiscountReason {
    final trimmedReason = discountReason.trim();
    final trimmedId = idNumber.trim();
    final base = switch (discountType) {
      CustomerDiscountType.none => '',
      CustomerDiscountType.seniorCitizen =>
        trimmedReason.isNotEmpty ? trimmedReason : 'Senior Citizen (20%)',
      CustomerDiscountType.pwd =>
        trimmedReason.isNotEmpty ? trimmedReason : 'PWD (20%)',
      CustomerDiscountType.customPercent =>
        trimmedReason.isNotEmpty
            ? trimmedReason
            : 'Regular customer (${_cleanNumber(effectiveDiscountValue)}%)',
      CustomerDiscountType.customAmount =>
        trimmedReason.isNotEmpty
            ? trimmedReason
            : 'Regular customer discount',
    };
    if (base.isEmpty) return '';
    if (trimmedId.isNotEmpty && !base.contains(trimmedId)) {
      return '$base · ID $trimmedId';
    }
    return base;
  }

  /// Short badge label shown on customer rows and in the POS cart header.
  String? get discountBadgeLabel => switch (discountType) {
    CustomerDiscountType.none => null,
    CustomerDiscountType.seniorCitizen =>
      'Senior Citizen · ${_cleanNumber(effectiveDiscountValue)}% off',
    CustomerDiscountType.pwd =>
      'PWD · ${_cleanNumber(effectiveDiscountValue)}% off',
    CustomerDiscountType.customPercent =>
      effectiveDiscountValue > 0
          ? '${_cleanNumber(effectiveDiscountValue)}% regular discount'
          : null,
    CustomerDiscountType.customAmount =>
      effectiveDiscountValue > 0
          ? '₱${_cleanNumber(effectiveDiscountValue)} regular discount'
          : null,
  };

  /// Converts this customer's standing discount preset into a [PosDiscount] for
  /// automatic pre-fill in the transaction's Discount section.
  PosDiscount? get toPosDiscount {
    final val = effectiveDiscountValue;
    if (discountType == CustomerDiscountType.none || val <= 0) return null;
    final kind = switch (discountType) {
      CustomerDiscountType.customAmount => DiscountKind.amount,
      CustomerDiscountType.none ||
      CustomerDiscountType.seniorCitizen ||
      CustomerDiscountType.pwd ||
      CustomerDiscountType.customPercent => DiscountKind.percent,
    };
    return PosDiscount(
      kind: kind,
      value: val,
      reason: effectiveDiscountReason,
    );
  }

  /// Formats phone and address into the server `contact_details` wire format
  /// (`"phone · address"`).
  String get wireContactDetails {
    final p = phone.trim();
    final a = address.trim();
    if (p.isNotEmpty && a.isNotEmpty) return '$p · $a';
    if (p.isNotEmpty) return p;
    return a;
  }

  /// Converts this profile into a [Customer] record so a locally registered
  /// regular customer can be selected in the till even before a server round-trip.
  Customer toCustomer({int fallbackId = -1}) => Customer(
    id: customerId ?? fallbackId,
    name: name.trim(),
    customerType: type == CustomerType.unknown || type == CustomerType.walkIn
        ? CustomerType.regular.apiValue
        : type.apiValue,
    contactDetails: wireContactDetails,
  );

  CustomerProfile copyWith({
    int? customerId,
    String? name,
    CustomerType? type,
    String? phone,
    String? address,
    CustomerDiscountType? discountType,
    double? discountValue,
    String? discountReason,
    String? idNumber,
  }) => CustomerProfile(
    customerId: customerId ?? this.customerId,
    name: name ?? this.name,
    type: type ?? this.type,
    phone: phone ?? this.phone,
    address: address ?? this.address,
    discountType: discountType ?? this.discountType,
    discountValue: discountValue ?? this.discountValue,
    discountReason: discountReason ?? this.discountReason,
    idNumber: idNumber ?? this.idNumber,
  );

  Map<String, dynamic> toJson() => {
    if (customerId != null) 'customer_id': customerId,
    'name': name,
    'type': type.apiValue,
    'phone': phone,
    'address': address,
    'discount_type': discountType.name,
    'discount_value': discountValue,
    'discount_reason': discountReason,
    'id_number': idNumber,
  };

  factory CustomerProfile.fromJson(Map<String, dynamic> json) =>
      CustomerProfile(
        customerId: (json['customer_id'] as num?)?.toInt(),
        name: (json['name'] as String?) ?? '',
        type: CustomerType.fromApiValue((json['type'] as String?) ?? 'REGULAR'),
        phone: (json['phone'] as String?) ?? '',
        address: (json['address'] as String?) ?? '',
        discountType: CustomerDiscountType.fromCode(
          json['discount_type'] as String?,
        ),
        discountValue: (json['discount_value'] as num?)?.toDouble() ?? 0,
        discountReason: (json['discount_reason'] as String?) ?? '',
        idNumber: (json['id_number'] as String?) ?? '',
      );

  /// Parses `"phone · address"` (or a bare phone / address) from
  /// [Customer.contactDetails].
  static ({String phone, String address}) splitContactDetails(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return (phone: '', address: '');
    if (trimmed.contains('·')) {
      final parts = trimmed.split('·');
      final first = parts.first.trim();
      final rest = parts.sublist(1).join('·').trim();
      return (phone: first, address: rest);
    }
    // Check if it looks like a phone number (mostly digits, spaces, +, -).
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 7 && digits.length >= trimmed.length ~/ 2) {
      return (phone: trimmed, address: '');
    }
    return (phone: '', address: trimmed);
  }

  static String _cleanNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }
}

/// Device-persisted store of enriched customer profiles (standing discount,
/// phone number, and delivery/utang address).
///
/// Merges seamlessly with live [Customer] records from [CustomerRepository] so:
/// 1. Choosing Mang Kanor (Senior Citizen regular) automatically fills the
///    20% Senior Citizen discount in the transaction.
/// 2. Choosing Manang Rosa (Regular) automatically fills Name, Contact number,
///    and Address in Utang or Delivery forms while keeping all fields editable.
class CustomerProfileStore extends ChangeNotifier {
  CustomerProfileStore._() {
    _seedDefaults();
  }

  static final CustomerProfileStore instance = CustomerProfileStore._();

  static const String _prefsKey = 'pos.customer_profiles.v1';

  /// Keyed by normalized lowercase customer name.
  final Map<String, CustomerProfile> _byName = {};

  bool _loaded = false;

  static const List<CustomerProfile> defaultProfiles = [
    CustomerProfile(
      customerId: -101,
      name: 'Mang Kanor',
      type: CustomerType.regular,
      phone: '0917-412-8890',
      address: 'Purok 2, Brgy. San Isidro',
      discountType: CustomerDiscountType.seniorCitizen,
      discountValue: 20,
      discountReason: 'Senior Citizen (20%)',
      idNumber: 'OSCA-20419',
    ),
    CustomerProfile(
      customerId: -102,
      name: 'Manang Rosa',
      type: CustomerType.regular,
      phone: '0918-634-5521',
      address: '142 Mabini St., Brgy. San Jose',
      discountType: CustomerDiscountType.none,
    ),
    CustomerProfile(
      customerId: -103,
      name: 'Engr. Mateo Reyes',
      type: CustomerType.contractor,
      phone: '0917-905-1188',
      address: 'Lot 8 Block 3, Golden Horizon Subd.',
      discountType: CustomerDiscountType.customPercent,
      discountValue: 5,
      discountReason: 'Regular Contractor (5%)',
    ),
  ];

  static String _keyFor(String name) => name.trim().toLowerCase();

  void _seedDefaults() {
    for (final profile in defaultProfiles) {
      _byName[_keyFor(profile.name)] = profile;
    }
  }

  /// Resets in-memory state to the built-in defaults (useful in tests).
  @visibleForTesting
  void resetToDefaults() {
    _byName.clear();
    _seedDefaults();
    _loaded = false;
    notifyListeners();
  }

  /// All stored customer profiles, sorted alphabetically by name.
  List<CustomerProfile> get profiles {
    final list = _byName.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Loads any saved customer profiles from [SharedPreferences].
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            final profile = CustomerProfile.fromJson(item);
            if (profile.name.trim().isNotEmpty) {
              _byName[_keyFor(profile.name)] = profile;
            }
          }
        }
        notifyListeners();
      }
    } catch (_) {
      // Keep defaults if local storage cannot be read.
    }
  }

  /// Saves or updates a customer's profile and persists to [SharedPreferences].
  Future<CustomerProfile> upsertProfile(
    CustomerProfile profile, {
    String? previousName,
  }) async {
    if (previousName != null &&
        _keyFor(previousName) != _keyFor(profile.name)) {
      _byName.remove(_keyFor(previousName));
    }
    final key = _keyFor(profile.name);
    final existing = _byName[key];
    final nextId =
        profile.customerId ??
        existing?.customerId ??
        -(_byName.length + 200);
    final saved = profile.copyWith(customerId: nextId);
    _byName[key] = saved;
    notifyListeners();
    await _persist();
    return saved;
  }

  /// Removes a locally stored profile by name.
  Future<void> removeProfile(String name) async {
    _byName.remove(_keyFor(name));
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode([
        for (final profile in _byName.values) profile.toJson(),
      ]);
      await prefs.setString(_prefsKey, encoded);
    } catch (_) {
      // Ignore persistence errors in restricted test environments.
    }
  }

  /// Resolves the enriched [CustomerProfile] for [customer], combining any
  /// saved profile (by ID or name) with phone/address parsed from
  /// [Customer.contactDetails].
  CustomerProfile? resolveFor(Customer? customer) {
    if (customer == null || customer.isWalkIn) return null;
    final byName = _byName[_keyFor(customer.name)];
    final byId = customer.id > 0
        ? _byName.values
              .where((p) => p.customerId == customer.id)
              .firstOrNull
        : null;
    final stored = byId ?? byName;
    final parsed = CustomerProfile.splitContactDetails(customer.contactDetails);

    if (stored != null) {
      return stored.copyWith(
        customerId: customer.id,
        name: customer.name,
        type: customer.type == CustomerType.unknown
            ? stored.type
            : customer.type,
        phone: stored.phone.trim().isNotEmpty ? stored.phone : parsed.phone,
        address: stored.address.trim().isNotEmpty
            ? stored.address
            : parsed.address,
      );
    }

    return CustomerProfile(
      customerId: customer.id,
      name: customer.name,
      type: customer.type == CustomerType.unknown
          ? CustomerType.regular
          : customer.type,
      phone: parsed.phone,
      address: parsed.address,
    );
  }

  /// Merges the server's [serverCustomers] list with all locally saved profiles
  /// so the Cashier Customers page and picker show every regular customer with
  /// their complete contact and standing discount details.
  List<({Customer customer, CustomerProfile profile})> mergeCustomers(
    List<Customer> serverCustomers,
  ) {
    final result = <String, ({Customer customer, CustomerProfile profile})>{};

    for (final c in serverCustomers) {
      if (c.isWalkIn) continue;
      final key = _keyFor(c.name);
      final profile = resolveFor(c)!;
      result[key] = (
        customer: Customer(
          id: c.id,
          name: c.name,
          customerType: c.customerType,
          totalCreditLimit: c.totalCreditLimit,
          contactDetails: c.contactDetails.trim().isNotEmpty
              ? c.contactDetails
              : profile.wireContactDetails,
        ),
        profile: profile,
      );
    }

    var fallbackId = -101;
    for (final profile in _byName.values) {
      final key = _keyFor(profile.name);
      if (result.containsKey(key)) continue;
      final customer = profile.toCustomer(fallbackId: fallbackId--);
      result[key] = (customer: customer, profile: profile);
    }

    final list = result.values.toList()
      ..sort(
        (a, b) => a.customer.name.toLowerCase().compareTo(
          b.customer.name.toLowerCase(),
        ),
      );
    return list;
  }
}
