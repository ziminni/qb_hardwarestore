/// Strict JSON field readers for the API models.
///
/// DRF sends every `DecimalField` as a JSON **string** (`"315.00"`), never a
/// number — verified against the running API. The previous models used
/// `?? 0` fallbacks throughout, which is how a variant missing its price
/// silently rendered as PHP 0.00 instead of failing.
///
/// These helpers invert that: a *required* field that is absent, null or
/// unparseable throws a [FormatException]. Only genuinely optional fields
/// (timestamps, nullable dates) are allowed to be missing.
library;

/// Reads a required decimal, accepting the string form DRF sends.
double decimalField(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    throw FormatException('Missing required decimal field "$key"');
  }
  if (value is num) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed == null) {
      throw FormatException('Field "$key" is not a decimal: "$value"');
    }
    return parsed;
  }
  throw FormatException(
    'Field "$key" has unsupported type ${value.runtimeType}',
  );
}

/// Reads a required non-empty-or-empty string.
String stringField(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    throw FormatException('Missing required string field "$key"');
  }
  if (value is! String) {
    throw FormatException('Field "$key" is not a string: ${value.runtimeType}');
  }
  return value;
}

/// Reads a required integer id.
int intField(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    throw FormatException('Missing required int field "$key"');
  }
  if (value is int) return value;
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed == null) {
      throw FormatException('Field "$key" is not an int: "$value"');
    }
    return parsed;
  }
  throw FormatException('Field "$key" is not an int: ${value.runtimeType}');
}

/// Reads an optional boolean, defaulting to true when absent.
bool boolFieldOr(Map<String, dynamic> json, String key, {required bool or}) {
  final value = json[key];
  if (value == null) return or;
  if (value is bool) return value;
  throw FormatException('Field "$key" is not a bool: ${value.runtimeType}');
}

/// Reads an optional date, returning null when absent or null.
DateTime? nullableDateField(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('Field "$key" is not a date string');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('Field "$key" is not a parseable date: "$value"');
  }
  return parsed;
}

/// Parses a nested list of objects, tolerating an absent list as empty.
///
/// A *missing* nested list is treated as empty rather than an error because the
/// API omits `selling_uoms`/`variants` in some nested representations.
List<T> nestedList<T>(
  Map<String, dynamic> json,
  String key,
  T Function(Map<String, dynamic>) fromJson,
) {
  final value = json[key];
  if (value == null) return const [];
  if (value is! List) {
    throw FormatException('Field "$key" is not a list: ${value.runtimeType}');
  }
  return value
      .map((item) => fromJson(item as Map<String, dynamic>))
      .toList(growable: false);
}
