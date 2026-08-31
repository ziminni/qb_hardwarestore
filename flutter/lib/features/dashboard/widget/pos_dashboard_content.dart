import 'package:client/features/dashboard/widget/mock_action.dart';
import 'package:client/features/dashboard/widget/mock_section.dart';
import 'package:client/features/dashboard/widget/pos_cart_panel.dart';
import 'package:flutter/material.dart';

class PosDashboardContent extends StatelessWidget {
  const PosDashboardContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(
              child: Text(
                'Point of Sale',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            MockAction(label: 'Hold transaction', icon: Icons.pause),
            SizedBox(width: 8),
            MockAction(label: 'Transaction history', icon: Icons.history),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  MockSection(
                    title: 'Product search',
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: '[ Scan barcode or search product ]',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) {},
                    ),
                  ),
                  const SizedBox(height: 16),
                  const MockSection(
                    title: 'Product results',
                    child: SizedBox(
                      height: 310,
                      child: Center(
                        child: Text('[ PRODUCT GRID / SEARCH RESULTS ]'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(flex: 2, child: PosCartPanel()),
          ],
        ),
      ],
    );
  }
}
