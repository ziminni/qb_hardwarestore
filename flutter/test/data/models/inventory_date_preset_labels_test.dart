// Z2 fix task B (D-07): the Stock adjustments date chips read "This Week" and
// "Custom Range" among sentence-case neighbours ("Today", "This Month").
//
// The chips are built from `InventoryDatePreset.label` (the one place the words
// live), so the label is what this pins. Nothing else spells these presets out.
import 'package:client/data/models/inventory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the date presets read in sentence case', () {
    expect(InventoryDatePreset.values.map((preset) => preset.label), [
      'Today',
      'This week',
      'This month',
      'Custom range',
    ]);
  });
}
