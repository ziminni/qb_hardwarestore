// Phase 4 Task F3a: the app-scoped settings viewmodel F4's till will read the
// discount cap and VAT rate from. It is shared, not per page: the admin saves
// and the till must see the new cap without a restart.

import 'package:client/data/models/store_settings.dart';
import 'package:client/data/services/store_settings_service.dart';
import 'package:client/features/admin/viewmodels/store_settings_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubService extends StoreSettingsService {
  _StubService({
    this.loaded = StoreSettings.defaults,
    this.failure,
    this.saveFailure,
  });

  StoreSettings loaded;
  String? failure;
  StoreSettingsException? saveFailure;
  final List<StoreSettings> saved = [];

  @override
  Future<StoreSettings> fetch() async {
    final failure = this.failure;
    if (failure != null) throw StoreSettingsException(failure);
    return loaded;
  }

  @override
  Future<StoreSettings> save(StoreSettings settings) async {
    final saveFailure = this.saveFailure;
    if (saveFailure != null) throw saveFailure;
    saved.add(settings);
    loaded = settings;
    return settings;
  }
}

const _stored = StoreSettings(
  vatRegistered: true,
  vatRate: 12,
  discountCapPercent: 10,
);

void main() {
  test('load publishes the server values for the till', () async {
    final viewmodel = StoreSettingsViewmodel(
      service: _StubService(
        loaded: const StoreSettings(
          vatRegistered: false,
          vatRate: 0,
          discountCapPercent: 18.5,
        ),
      ),
    );

    expect(viewmodel.hasLoaded, isFalse);
    // Before the first answer the server defaults stand in, so a till is never
    // blocked by a settings request that has not finished.
    expect(viewmodel.vatRegistered, isTrue);
    expect(
      viewmodel.discountCapPercent,
      StoreSettings.defaultDiscountCapPercent,
    );

    await viewmodel.load();

    expect(viewmodel.hasLoaded, isTrue);
    expect(viewmodel.vatRegistered, isFalse);
    expect(viewmodel.vatRate, 0);
    expect(viewmodel.discountCapPercent, 18.5);
  });

  test('a failed load keeps the defaults and names the failure', () async {
    final viewmodel = StoreSettingsViewmodel(
      service: _StubService(failure: 'The store settings could not be loaded.'),
    );

    await viewmodel.load();

    expect(viewmodel.loadError, 'The store settings could not be loaded.');
    expect(viewmodel.vatRegistered, isTrue);
    expect(
      viewmodel.discountCapPercent,
      StoreSettings.defaultDiscountCapPercent,
    );
  });

  test('save publishes the stored values', () async {
    final service = _StubService(loaded: _stored);
    final viewmodel = StoreSettingsViewmodel(service: service);
    await viewmodel.load();

    final ok = await viewmodel.save(
      vatRegistered: false,
      vatRate: 0,
      discountCapPercent: 20,
    );

    expect(ok, isTrue);
    expect(service.saved.single.discountCapPercent, 20);
    expect(viewmodel.vatRegistered, isFalse);
    expect(viewmodel.discountCapPercent, 20);
    expect(viewmodel.saveError, isNull);
  });

  test(
    'a refused save keeps the loaded values and names the refusal',
    () async {
      final viewmodel = StoreSettingsViewmodel(
        service: _StubService(
          loaded: _stored,
          saveFailure: const StoreSettingsException(
            'Only an Admin may change store settings.',
            isForbidden: true,
          ),
        ),
      );
      await viewmodel.load();

      final ok = await viewmodel.save(
        vatRegistered: true,
        vatRate: 12,
        discountCapPercent: 50,
      );

      expect(ok, isFalse);
      expect(viewmodel.saveError, 'Only an Admin may change store settings.');
      expect(viewmodel.discountCapPercent, 10);
    },
  );

  test('an out-of-range percent never reaches the server', () async {
    final service = _StubService(loaded: _stored);
    final viewmodel = StoreSettingsViewmodel(service: service);
    await viewmodel.load();

    final ok = await viewmodel.save(
      vatRegistered: true,
      vatRate: 120,
      discountCapPercent: 10,
    );

    expect(ok, isFalse);
    expect(service.saved, isEmpty);
    expect(viewmodel.saveError, isNotNull);
  });
}
