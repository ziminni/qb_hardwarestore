// The till's category chips and the cart's +/- steppers (2026-10-29 UI
// refresh, matching the design canvas). Both live in the viewmodel so the
// stock rule that guards addLine also guards a + tap.

import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

void main() {
  late PosTransactionViewmodel till;

  setUp(() {
    till = PosTransactionViewmodel(
      seededInventory(),
      pos: PosRepository(PosService()),
    );
  });

  group('categories', () {
    test('the catalogue rows carry their category and brand', () {
      final cement = till.filteredProducts.firstWhere(
        (item) => item.productName == 'Portland Cement',
      );
      expect(cement.categoryName, 'Cement');
      expect(cement.brandName, 'Holcim');
    });

    test('the chips list each category once, sorted', () {
      expect(till.categories, ['Cement', 'Plumbing']);
    });

    test('choosing a category narrows the products; null shows all', () {
      till.setCategory('Plumbing');
      expect(till.selectedCategory, 'Plumbing');
      expect(till.filteredProducts.map((item) => item.productName), [
        'PVC Pipe',
      ]);

      till.setCategory(null);
      expect(till.filteredProducts, hasLength(2));
    });

    test('a category and a search combine', () {
      till.setCategory('Cement');
      till.setQuery('pvc');
      expect(till.filteredProducts, isEmpty);
    });
  });

  group('steppers', () {
    setUp(() {
      final pipe = till.filteredProducts.firstWhere(
        (item) => item.productName == 'PVC Pipe',
      );
      expect(till.addLine(pipe, 2), isNull);
    });

    test('+ adds one of the same unit', () {
      expect(till.stepLine(0, 1), isNull);
      expect(till.lines.single.quantity, 3);
    });

    test('- takes one away, and removes the line at zero', () {
      expect(till.stepLine(0, -1), isNull);
      expect(till.lines.single.quantity, 1);
      expect(till.stepLine(0, -1), isNull);
      expect(till.lines, isEmpty);
    });

    test('+ past the stock on hand is refused and changes nothing', () {
      // 40 pipes in stock, 2 in the cart: 38 more fit, the 39th does not.
      for (var i = 0; i < 38; i++) {
        expect(till.stepLine(0, 1), isNull);
      }
      expect(till.stepLine(0, 1), contains('available'));
      expect(till.lines.single.quantity, 40);
    });
  });
}
