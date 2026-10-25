# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directives and reasons as apps/inventory/tests.py: this checker runs from a
# working directory outside the repo, so `Model.objects` is a false positive on valid
# Django, and `**auth` splats HTTP_AUTHORIZATION into the test client, which pyright
# reads as `follow=`.

"""Phase 4 Task 3 — low-stock alerts on EVERY stock-out, and never twice.

The gap this closes: `_check_low_stock` existed and `allocate_fifo` did not call it, so
only a goods receipt and a manual adjustment ever raised an alert. A shop could sell its
last bag and the low-stock screen stayed empty — the one screen a stocker actually
watches. Two paths move stock OUT: `process_sale` (which a held-cart completion also
goes through) and `release_materials`.

The second half is dedup, and it is what makes calling the check from a sale safe: until
now every receipt re-raised the same alert, so the screen collected duplicates. Now an
**unresolved** alert of the same type suppresses a second one, checked with the variant
row LOCKED so two concurrent tills cannot both miss it. Escalation still happens — going
from LOW to OUT_OF_STOCK adds the OUT alert while the open LOW alert stays as it is — and
a restock does NOT auto-resolve anything (resolving is a named act, decision 06).
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.utils.crypto import get_random_string

from apps.pos.models import Customer, Shift
from apps.requisitions.models import Project, Requisition, RequisitionItem
from apps.requisitions.services import (
    approve_requisition,
    release_materials,
    submit_requisition,
)

from .exceptions import InsufficientStock
from .models import SystemAlert, VariantUOM
from .services import process_goods_receipt
from .tests import InventoryTestBase

User = get_user_model()


class AlertTriggerTestBase(InventoryTestBase):
    """Threshold 5, eight units on hand, a cashier with an open shift."""

    def setUp(self):
        super().setUp()
        self.password = get_random_string(16)
        self.cashier = self._make_user('alert_trig_cashier', 'Cashier')
        self.manager = self._make_user('alert_trig_manager', 'Store Manager')
        # A release needs a requisition SOMEBODY ELSE requested: `approve_requisition`
        # refuses the requester (separation of duties), so the foreman raises it and the
        # store manager approves.
        self.foreman = self._make_user('alert_trig_foreman', 'Site Foreman')
        self.shift = Shift.objects.create(
            cashier=self.cashier, opening_float=Decimal('5000'))
        self.customer = Customer.objects.create(
            name='Dela Cruz Construction',
            customer_type=Customer.Type.CONTRACTOR)
        self.vuom = VariantUOM.objects.create(
            variant=self.variant, uom=self.uom,
            conversion_factor=Decimal('1'),
            default_selling_price=Decimal('10'),
        )
        self._stock('8')

    # -- fixture helpers ---------------------------------------------------
    def _make_user(self, username, *groups):
        user = User.objects.create_user(
            username=username, email=f'{username}@example.com',
            password=self.password, full_name=username)
        for name in groups:
            user.groups.add(Group.objects.get_or_create(name=name)[0])
        return user

    def _stock(self, qty):
        """A processed delivery: the stock the tests then take away."""
        _po, _item, receipt = self._receive(qty)
        return process_goods_receipt(receipt=receipt, user=self.user)

    def _on_hand(self):
        return sum(
            self.variant.batches.values_list('current_qty', flat=True),
            Decimal('0'),
        )

    def _sell(self, qty):
        from apps.pos.services import process_sale

        qty = Decimal(str(qty))
        return process_sale(
            customer_id=self.customer.pk,
            cashier=self.cashier,
            items_data=[{'variant_id': self.vuom.pk, 'qty': qty}],
            payments_data=[{
                'method': 'CASH',
                'amount_tendered': qty * Decimal('10'),
            }],
        )

    def _release(self, qty):
        """Release `qty` base units against an approved requisition token."""
        project = Project.objects.create(
            name='House Build', customer=self.customer)
        requisition = Requisition.objects.create(
            project=project, requested_by=self.foreman)
        RequisitionItem.objects.create(
            requisition=requisition, variant=self.variant,
            quantity=Decimal(str(qty)))
        submit_requisition(requisition=requisition)
        token = approve_requisition(
            requisition=requisition, approver=self.manager)
        return release_materials(
            token_value=str(token.token), cashier=self.cashier)

    def _alerts(self, alert_type=None):
        rows = SystemAlert.objects.filter(variant=self.variant)
        if alert_type is not None:
            rows = rows.filter(alert_type=alert_type)
        return rows


class SaleTriggersTheCheckTests(AlertTriggerTestBase):
    def test_a_sale_below_the_threshold_raises_one_low_stock_alert(self):
        self.assertEqual(self._alerts().count(), 0, 'the fixture must start clear')

        self._sell('4')

        self.assertEqual(self._on_hand(), Decimal('4'))
        alerts = self._alerts(SystemAlert.AlertType.LOW_STOCK)
        self.assertEqual(alerts.count(), 1, list(alerts.values_list('message', flat=True)))
        alert = alerts.get()
        self.assertFalse(alert.is_resolved)
        self.assertIn('below', alert.message)

    def test_a_second_low_sale_does_not_duplicate_the_alert(self):
        self._sell('4')
        self.assertEqual(self._alerts(SystemAlert.AlertType.LOW_STOCK).count(), 1)

        self._sell('1')

        self.assertEqual(self._on_hand(), Decimal('3'))
        self.assertEqual(
            self._alerts(SystemAlert.AlertType.LOW_STOCK).count(), 1,
            'an unresolved alert of the same type must not be raised twice')

    def test_selling_out_adds_an_out_of_stock_alert_and_keeps_the_low_one(self):
        self._sell('5')
        self.assertEqual(self._alerts(SystemAlert.AlertType.LOW_STOCK).count(), 1)

        self._sell('3')

        self.assertEqual(self._on_hand(), Decimal('0'))
        self.assertEqual(self._alerts(SystemAlert.AlertType.OUT_OF_STOCK).count(), 1)
        self.assertEqual(
            self._alerts(SystemAlert.AlertType.LOW_STOCK).count(), 1,
            'the open LOW alert stays as it is on escalation')
        self.assertEqual(self._alerts().count(), 2)

    def test_a_sale_with_a_zero_threshold_raises_no_low_alert(self):
        self.variant.min_stock_threshold = Decimal('0')
        self.variant.save(update_fields=['min_stock_threshold'])

        self._sell('4')

        self.assertEqual(self._on_hand(), Decimal('4'))
        self.assertEqual(self._alerts().count(), 0)

    def test_a_refused_sale_raises_no_alert(self):
        with self.assertRaises(InsufficientStock):
            self._sell('100')

        self.assertEqual(self._on_hand(), Decimal('8'))
        self.assertEqual(self._alerts().count(), 0)

    def test_a_resolved_alert_does_not_suppress_the_next_one(self):
        self._sell('4')
        self.assertEqual(
            self._alerts(SystemAlert.AlertType.LOW_STOCK).count(), 1,
            'the first sale must raise the alert this test then resolves')
        alert = self._alerts(SystemAlert.AlertType.LOW_STOCK).get()
        alert.is_resolved = True
        alert.save(update_fields=['is_resolved'])

        self._sell('1')

        self.assertEqual(self._on_hand(), Decimal('3'))
        self.assertEqual(
            self._alerts(SystemAlert.AlertType.LOW_STOCK).count(), 2,
            'a resolved alert must not silence the next stock-out')
        self.assertEqual(
            self._alerts(SystemAlert.AlertType.LOW_STOCK)
            .filter(is_resolved=False).count(),
            1)

    def test_a_restock_does_not_resolve_an_open_alert(self):
        self._sell('4')
        self.assertEqual(
            self._alerts(SystemAlert.AlertType.LOW_STOCK).count(), 1,
            'the sale must raise the alert this test then restocks against')
        alert = self._alerts(SystemAlert.AlertType.LOW_STOCK).get()

        self._stock('10')

        self.assertEqual(self._on_hand(), Decimal('14'))
        alert.refresh_from_db()
        self.assertFalse(
            alert.is_resolved,
            'resolving is a named act (decision 06): a delivery must not clear it')
        self.assertIsNone(alert.resolved_by)
        self.assertEqual(self._alerts().count(), 1)


class ReleaseTriggersTheCheckTests(AlertTriggerTestBase):
    def test_a_release_below_the_threshold_raises_one_alert(self):
        self.assertEqual(self._alerts().count(), 0)

        self._release('4')

        self.assertEqual(self._on_hand(), Decimal('4'))
        alerts = self._alerts(SystemAlert.AlertType.LOW_STOCK)
        self.assertEqual(alerts.count(), 1, list(alerts.values_list('message', flat=True)))
        self.assertFalse(alerts.get().is_resolved)

    def test_a_release_to_zero_raises_an_out_of_stock_alert(self):
        self._release('8')

        self.assertEqual(self._on_hand(), Decimal('0'))
        self.assertEqual(self._alerts(SystemAlert.AlertType.OUT_OF_STOCK).count(), 1)
