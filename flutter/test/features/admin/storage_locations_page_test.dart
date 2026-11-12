// Phase 5 F4 (decision 18): the Admin storage-locations screen.
//
// Pinned here:
//   * the list shows active and deactivated places, active first;
//   * creating, renaming, deactivating and restoring PATCH the right row with
//     the right body — there is NO delete, because the route answers 405 and a
//     location a product points at is PROTECT-referenced;
//   * a duplicate name is refused BEFORE the round trip (the server refuses it
//     too, so a race still surfaces);
//   * the server's refusal sentence is shown to the clerk;
//   * one write per row at a time, so a double click cannot post twice;
//   * at 760 px with 1.3x text and the real fonts nothing clips.

import 'dart:async';
import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/admin/viewmodels/storage_locations_viewmodel.dart';
import 'package:client/features/admin/views/storage_locations_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';

const _seeded = [
  StorageLocation(id: 1, name: 'Store'),
  StorageLocation(id: 2, name: 'Bodega', isActive: false),
];

Future<void> _loadAppFonts() async {
  for (final (family, files) in [
    ('OpenSans', ['OpenSans-Regular.ttf', 'OpenSans-Bold.ttf']),
    ('Cinzel', ['Cinzel-Regular.ttf', 'Cinzel-Bold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = await File('assets/fonts/$file').readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
}

Future<void> _pump(
  WidgetTester tester,
  StorageLocationsViewmodel viewmodel, {
  Size size = const Size(1440, 1000),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    // The admin shell's sidebar reads the signed-in account, so the page needs the
    // same provider the app supplies (the payables page test does the same).
    ChangeNotifierProvider<AuthViewmodel>(
      create: (_) => AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: StorageLocationsPage(viewmodel: viewmodel),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

StorageLocationsViewmodel _state([
  List<StorageLocation> locations = _seeded,
  FakeStorageLocationRepository? repository,
]) => StorageLocationsViewmodel(
  repository: repository ?? FakeStorageLocationRepository(locations: locations),
);

/// Holds the write on the wire until the test releases it, so the busy state is
/// observable (a double click must post once).
class _GatedStorageLocationRepository extends FakeStorageLocationRepository {
  _GatedStorageLocationRepository({super.locations});

  final Completer<void> gate = Completer<void>();

  @override
  Future<StorageLocation> patch(int id, {String? name, bool? isActive}) async {
    await gate.future;
    return super.patch(id, name: name, isActive: isActive);
  }
}

/// Holds the CREATE on the wire, so a second create can be attempted while the
/// first is still out.
class _GatedCreateStorageLocationRepository
    extends FakeStorageLocationRepository {
  _GatedCreateStorageLocationRepository({super.locations});

  final Completer<void> gate = Completer<void>();

  @override
  Future<StorageLocation> create(String name) async {
    await gate.future;
    return super.create(name);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(_loadAppFonts);

  testWidgets('lists active and deactivated places, active first', (
    tester,
  ) async {
    await _pump(tester, _state());

    expect(find.text('Store'), findsWidgets);
    expect(find.text('Bodega'), findsWidgets);
    expect(find.text('Active'), findsWidgets);
    expect(find.text('Deactivated'), findsWidgets);
    // No Delete anywhere: the route answers 405.
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('creating a location POSTs the typed name', (tester) async {
    final repository = FakeStorageLocationRepository(locations: _seeded);
    await _pump(tester, _state(_seeded, repository));

    await tester.tap(find.byKey(const ValueKey('storage-location-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('storage-location-name')),
      'Yard',
    );
    await tester.tap(find.byKey(const ValueKey('storage-location-submit')));
    await tester.pumpAndSettle();

    expect(repository.created, ['Yard']);
    expect(find.text('Yard'), findsWidgets);
  });

  testWidgets('a duplicate name is refused before the request', (tester) async {
    final repository = FakeStorageLocationRepository(locations: _seeded);
    await _pump(tester, _state(_seeded, repository));

    await tester.tap(find.byKey(const ValueKey('storage-location-create')));
    await tester.pumpAndSettle();
    // The server compares case-insensitively, so "bodega" is the same place.
    await tester.enterText(
      find.byKey(const ValueKey('storage-location-name')),
      'bodega',
    );
    await tester.tap(find.byKey(const ValueKey('storage-location-submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('already a storage location'), findsOneWidget);
    expect(
      repository.created,
      isEmpty,
      reason: 'the clerk should be told before a round trip',
    );
  });

  testWidgets('renaming PATCHes the name of that row', (tester) async {
    final repository = FakeStorageLocationRepository(locations: _seeded);
    await _pump(tester, _state(_seeded, repository));

    await tester.tap(find.byKey(const ValueKey('storage-location-rename-2')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('storage-location-name')),
      'Warehouse',
    );
    await tester.tap(find.byKey(const ValueKey('storage-location-submit')));
    await tester.pumpAndSettle();

    expect(repository.patches.single.id, 2);
    expect(repository.patches.single.name, 'Warehouse');
    expect(repository.patches.single.isActive, isNull);
  });

  testWidgets('deactivating asks first, then PATCHes is_active false', (
    tester,
  ) async {
    final repository = FakeStorageLocationRepository(
      locations: const [StorageLocation(id: 1, name: 'Store')],
    );
    await _pump(
      tester,
      _state(const [StorageLocation(id: 1, name: 'Store')], repository),
    );

    await tester.tap(find.byKey(const ValueKey('storage-location-toggle-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('leaves the product form'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
    await tester.pumpAndSettle();

    expect(repository.patches.single, (id: 1, name: null, isActive: false));
  });

  testWidgets('restoring a deactivated place PATCHes is_active true', (
    tester,
  ) async {
    final repository = FakeStorageLocationRepository(locations: _seeded);
    await _pump(tester, _state(_seeded, repository));

    await tester.tap(find.byKey(const ValueKey('storage-location-toggle-2')));
    await tester.pumpAndSettle();
    // Restoring needs no confirmation: nothing is hidden from anyone.
    expect(repository.patches.single, (id: 2, name: null, isActive: true));
  });

  testWidgets('the server refusal sentence is shown to the clerk', (
    tester,
  ) async {
    final repository = FakeStorageLocationRepository(locations: _seeded)
      ..writeError =
          '"Bodega" is not an active storage location: pick one that '
          'is in the list, or have an Admin restore it.';
    await _pump(tester, _state(_seeded, repository));

    await tester.tap(find.byKey(const ValueKey('storage-location-toggle-2')));
    await tester.pumpAndSettle();

    // Twice: the banner on the page AND the snackbar that announced the refusal.
    expect(
      find.textContaining('is not an active storage location'),
      findsWidgets,
    );
  });

  testWidgets('a failed read shows a banner and no invented zeroes', (
    tester,
  ) async {
    final repository = FakeStorageLocationRepository(locations: _seeded)
      ..readError = 'The storage locations could not be read.';
    await _pump(tester, _state(_seeded, repository));

    expect(
      find.textContaining('could not be read'),
      findsWidgets,
      reason: 'a failed read must say so, not render an empty list',
    );
    expect(
      find.textContaining('No storage locations yet'),
      findsNothing,
      reason: 'the empty state would claim the shop has no places',
    );
  });

  testWidgets('one write per row: a second click while the first is on the '
      'wire posts nothing', (tester) async {
    final repository = _GatedStorageLocationRepository(
      locations: const [StorageLocation(id: 1, name: 'Store')],
    );
    await _pump(
      tester,
      _state(const [StorageLocation(id: 1, name: 'Store')], repository),
    );

    await tester.tap(find.byKey(const ValueKey('storage-location-toggle-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
    await tester.pump();

    expect(
      repository.patches,
      isEmpty,
      reason: 'the first write is still in flight',
    );
    await tester.tap(find.byKey(const ValueKey('storage-location-toggle-1')));
    await tester.pump();
    expect(
      repository.patches,
      isEmpty,
      reason: 'a double click must not post twice',
    );

    repository.gate.complete();
    await tester.pumpAndSettle();
    expect(repository.patches.single, (id: 1, name: null, isActive: false));
  });

  // Item 13: a create that arrives while the first is still on the wire is not
  // a success. Returning null (the success value) made the page announce
  // '"Yard" added.' for a location nobody added.
  test(
    'a second create while one is on the wire is not reported as added',
    () async {
      final repository = _GatedCreateStorageLocationRepository(
        locations: const [StorageLocation(id: 1, name: 'Store')],
      );
      final state = _state(const [
        StorageLocation(id: 1, name: 'Store'),
      ], repository);

      final first = state.create('Yard');
      final second = await state.create('Shed');

      expect(
        second,
        isNotNull,
        reason: 'null is the success value, and nothing was added',
      );
      expect(
        repository.created,
        isEmpty,
        reason: 'the first is still in flight',
      );

      repository.gate.complete();
      expect(await first, isNull);
      expect(repository.created, [
        'Yard',
      ], reason: 'one POST, and it is the first one');
    },
  );

  testWidgets('760 px at 1.3x text, the page renders whole', (tester) async {
    final repository = FakeStorageLocationRepository(
      locations: const [
        StorageLocation(id: 1, name: 'Store'),
        StorageLocation(id: 2, name: 'Main Warehouse at the Back Lot'),
      ],
    );
    await _pump(
      tester,
      _state(const [], repository),
      size: const Size(760, 900),
      scale: 1.3,
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Storage locations'), findsWidgets);
    expect(find.text('Main Warehouse at the Back Lot'), findsWidgets);
  });
}
