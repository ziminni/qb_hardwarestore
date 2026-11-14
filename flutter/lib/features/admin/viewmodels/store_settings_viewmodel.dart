import 'package:client/data/models/store_settings.dart';
import 'package:client/data/services/store_settings_service.dart';
import 'package:flutter/foundation.dart';

/// Holds the store-wide settings for the whole session.
///
/// App-scoped on purpose: the Admin saves the VAT rate and discount cap here,
/// and the till (Phase 4 F4) applies the same cap and VAT on the next sale. A
/// per-page instance would leave the till on yesterday's cap until a restart.
///
/// Before the first answer [settings] is [StoreSettings.defaults], the server's
/// own defaults, so no screen is blocked by a request that has not finished.
class StoreSettingsViewmodel extends ChangeNotifier {
  StoreSettingsViewmodel({StoreSettingsService? service})
    : _service = service ?? StoreSettingsService();

  final StoreSettingsService _service;

  StoreSettings? _settings;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _loadError;
  String? _saveError;
  Map<String, String> _fieldErrors = const {};

  /// What the till and the settings page read. Never null: the defaults stand
  /// in until the first load answers.
  StoreSettings get settings => _settings ?? StoreSettings.defaults;

  /// True once the server has answered at least once.
  bool get hasLoaded => _settings != null;

  bool get vatRegistered => settings.vatRegistered;
  double get vatRate => settings.vatRate;
  double get discountCapPercent => settings.discountCapPercent;

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get loadError => _loadError;
  String? get saveError => _saveError;

  /// Per-field sentences from the last refused save, empty when none.
  Map<String, String> get fieldErrors => _fieldErrors;

  /// Reads the settings. A failed load keeps the last good values and names
  /// the failure: falling back to the defaults silently would show a cap the
  /// store may not have.
  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      _settings = await _service.fetch();
    } on StoreSettingsException catch (error) {
      _loadError = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Stores [vatRegistered], [vatRate] and [discountCapPercent], then publishes
  /// what the server kept.
  ///
  /// Returns false without a request when a percent breaks the shared rule:
  /// the round trip would only repeat what the form already knows.
  Future<bool> save({
    required bool vatRegistered,
    required double vatRate,
    required double discountCapPercent,
  }) async {
    final invalid =
        StoreSettings.percentError(vatRate.toStringAsFixed(2)) ??
        StoreSettings.percentError(discountCapPercent.toStringAsFixed(2));
    if (invalid != null) {
      _saveError = invalid;
      _fieldErrors = const {};
      notifyListeners();
      return false;
    }
    _saveError = null;
    _fieldErrors = const {};
    _isSaving = true;
    notifyListeners();
    try {
      _settings = await _service.save(
        StoreSettings(
          vatRegistered: vatRegistered,
          vatRate: vatRate,
          discountCapPercent: discountCapPercent,
        ),
      );
      return true;
    } on StoreSettingsException catch (error) {
      _saveError = error.message;
      _fieldErrors = error.fieldErrors;
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Clears a stale refusal, e.g. as soon as the user edits a field.
  void clearSaveError() {
    if (_saveError == null) return;
    _saveError = null;
    _fieldErrors = const {};
    notifyListeners();
  }
}
