# pyright: reportAttributeAccessIssue=false
"""Every stock deduction keeps the landed cost of the batch it drew from.

Without it the cost of goods sold can only be read from today's batch rows, which is a
guess once stock has moved. A deduction written before this column existed stays NULL so
a report can say how much of its cost history is missing.
"""

from decimal import Decimal

from .models import SalesItemDeduction
from .services import process_return, process_sale
from .tests import POSTestBase


class CostSnapshotTests(POSTestBase):
    def _sell(self, qty):
        return process_sale(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{"variant_id": self.vuom.id, "qty": qty}],
            payments_data=[
                {"method": "CASH", "amount_tendered": Decimal(qty) * Decimal(10)}
            ],
        )

    def test_a_sale_snapshots_each_batchs_cost(self):
        sale = self._sell(7)  # fixture: 5 @ 40.00 (oldest) then 5 @ 60.00

        rows = SalesItemDeduction.objects.filter(sales_item__transaction=sale)
        self.assertEqual(
            sorted((row.qty, row.unit_cost) for row in rows),
            [(Decimal(2), Decimal("60.00")), (Decimal(5), Decimal("40.00"))],
        )

    def test_a_linked_return_snapshots_the_cost_of_the_batch_it_restocks(self):
        sale = self._sell(7)

        returned = process_return(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{"variant_id": self.vuom.id, "qty": 1}],
            original_transaction_id=sale.id,
            reason="changed mind",
        )

        row = SalesItemDeduction.objects.get(sales_item__transaction=returned)
        self.assertLess(row.qty, 0)
        self.assertIn(row.unit_cost, (Decimal("40.00"), Decimal("60.00")))
        self.assertEqual(row.unit_cost, row.batch.unit_cost_landed)
