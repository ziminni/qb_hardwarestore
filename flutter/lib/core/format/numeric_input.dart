import 'package:flutter/services.dart';

/// Shared numeric input formatters and inline validators for POS forms.
///
/// Blocks letters and invalid symbols at the keystroke boundary while providing
/// human-readable inline validation warnings when an entered number is zero,
/// negative, or exceeds an allowed maximum.
List<TextInputFormatter> decimalInputFormatters({int maxDecimals = 2}) => [
  TextInputFormatter.withFunction((oldValue, newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    final pattern = maxDecimals > 0
        ? RegExp('^\\d*\\.?\\d{0,$maxDecimals}\$')
        : RegExp(r'^\d*$');
    return pattern.hasMatch(text) ? newValue : oldValue;
  }),
];

List<TextInputFormatter> integerInputFormatters() => [
  FilteringTextInputFormatter.digitsOnly,
];

/// Returns a user-friendly inline warning when [raw] is not a valid number in
/// range, or `null` when valid / empty (unless [required] is true).
String? validateNumericInput(
  String? raw, {
  String label = 'Amount',
  bool required = false,
  bool allowZero = false,
  double? max,
  String? maxError,
}) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) {
    return required ? '$label is required.' : null;
  }
  final parsed = double.tryParse(text);
  if (parsed == null || !parsed.isFinite) {
    return 'Enter a valid number (digits only).';
  }
  if (parsed < 0) {
    return '$label cannot be negative.';
  }
  if (!allowZero && parsed == 0) {
    return '$label must be greater than 0.';
  }
  if (max != null && parsed > max) {
    return maxError ?? '$label cannot exceed ${max.toStringAsFixed(2)}.';
  }
  return null;
}
