// Tests for the client-local storage-location hint store.
//
// Decision 10: location is NOT API data — the backend has no such field. It is a
// store-local hint ("where we put it"), persisted so it survives restarts.
// Keyed by variantId, held as one JSON blob.

import 'package:client/data/services/location_hint_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('LocationHintStore', () {
    test('returns no hints on a fresh install', () async {
      expect(await LocationHintStore().loadAll(), isEmpty);
    });

    test('saves a hint for a variant', () async {
      final store = LocationHintStore();

      await store.save(7, 'Rack A-01');

      expect(await store.loadAll(), {7: 'Rack A-01'});
    });

    test('keeps several hints side by side', () async {
      final store = LocationHintStore();

      await store.save(1, 'Rack A-01');
      await store.save(2, 'Yard E-02');

      expect(await store.loadAll(), {1: 'Rack A-01', 2: 'Yard E-02'});
    });

    test('overwrites an existing hint', () async {
      final store = LocationHintStore();

      await store.save(1, 'Rack A-01');
      await store.save(1, 'Rack B-09');

      expect(await store.loadAll(), {1: 'Rack B-09'});
    });

    test('an empty location clears the hint', () async {
      // Blank means "we do not know where it is", which must not render as a
      // placeholder or an empty-looking location.
      final store = LocationHintStore();
      await store.save(1, 'Rack A-01');

      await store.save(1, '   ');

      expect(await store.loadAll(), isEmpty);
    });

    test('clears a hint explicitly', () async {
      final store = LocationHintStore();
      await store.save(1, 'Rack A-01');

      await store.clear(1);

      expect(await store.loadAll(), isEmpty);
    });

    test('survives a new store instance (i.e. it is persisted)', () async {
      await LocationHintStore().save(3, 'Shelf G-02');

      expect(await LocationHintStore().loadAll(), {3: 'Shelf G-02'});
    });

    test('hintFor reads a single variant', () async {
      final store = LocationHintStore();
      await store.save(5, 'Bin H-01');

      expect(await store.hintFor(5), 'Bin H-01');
      expect(await store.hintFor(999), isNull);
    });

    test('ignores stored data that is not valid JSON', () async {
      // A corrupt blob must not crash the inventory screen.
      SharedPreferences.setMockInitialValues({
        'stock_location_hints': 'not json at all',
      });

      expect(await LocationHintStore().loadAll(), isEmpty);
    });

    test('ignores entries whose keys are not variant ids', () async {
      SharedPreferences.setMockInitialValues({
        'stock_location_hints': '{"1":"Rack A-01","oops":"Rack B-02"}',
      });

      expect(await LocationHintStore().loadAll(), {1: 'Rack A-01'});
    });
  });
}
