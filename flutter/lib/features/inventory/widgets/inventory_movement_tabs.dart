import 'package:client/data/models/inventory.dart';
import 'package:flutter/material.dart';

class InventoryMovementTabs extends StatelessWidget {
  const InventoryMovementTabs({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final InventoryMovementView selected;
  final ValueChanged<InventoryMovementView> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<InventoryMovementView>(
        segments: InventoryMovementView.values
            .map(
              (view) => ButtonSegment<InventoryMovementView>(
                value: view,
                label: Text(view.label),
              ),
            )
            .toList(),
        selected: {selected},
        onSelectionChanged: (value) => onSelected(value.first),
        showSelectedIcon: false,
      ),
    );
  }
}
