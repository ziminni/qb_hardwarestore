// The till's catalogue is built from every variant and every stock batch.
// It used to be rebuilt on each read, several times per keystroke; now it is
// built once per inventory change (temp/ui-refresh/PERFORMANCE.md, #3).

import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

void main() {
  test('typing in the search reuses the catalogue', () {
    final till = PosTransactionViewmodel(
      seededInventory(),
      pos: PosRepository(PosService()),
    );
    final before = till.catalogueBuilds;

    for (final query in ['p', 'pv', 'pvc', 'pv', 'p', '']) {
      till.setQuery(query);
      till.filteredProducts;
      till.categories;
    }

    expect(till.catalogueBuilds - before, lessThanOrEqualTo(1));
  });

  test('an inventory change rebuilds it, so stock and prices stay live', () {
    final inventory = seededInventory();
    final till = PosTransactionViewmodel(
      inventory,
      pos: PosRepository(PosService()),
    );
    till.filteredProducts;
    final before = till.catalogueBuilds;

    // Any notification from the inventory means its rows may have changed.
    inventory.notifyListeners();
    till.filteredProducts;

    expect(till.catalogueBuilds, before + 1);
  });
}
