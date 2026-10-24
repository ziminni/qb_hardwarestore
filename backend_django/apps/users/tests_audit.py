# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directive and reason as apps/pos/tests.py: the checker resolves its config from
# its working directory, so `Model.objects` and `**self.auth` (Django's test client
# forwards unknown kwargs into the WSGI environ, which is HOW you set a header) are
# false positives on code the test run proves correct.
"""Phase 2 Task 5 — append-only business audit (decision 07).

Two separate properties are pinned here, and confusing them is how an audit trail rots:

* **Every business event writes exactly ONE row, inside the event's own transaction.**
  A row is written by the same `atomic()` block that moves the stock/money, so a refused
  event (`INSUFFICIENT_STOCK`, `SELF_APPROVAL`, `LAST_ADMIN`, `ALERT_ALREADY_RESOLVED`)
  writes nothing and a rolled-back event leaves no claim that it happened. An idempotent
  checkout REPLAY (HTTP 200) is not a new event, so it writes no second row.
* **A written row can never change or disappear.** `save()` on an existing row, `delete()`,
  and the queryset's `update()`/`delete()` all raise; the Django admin may not add, change
  or delete; and the `user` FK is `PROTECT`, so an account that acted cannot be deleted
  out from under its history. `username_snapshot` keeps the actor's name readable even
  for a row whose account is later deactivated.

Descriptions carry the DOCUMENT NUMBER (`TRX-…`, `REQ-…`, cart/adjustment/alert pk) and
never a credential: the release audit must not contain the material token UUID, which is
a bearer credential that releases goods on credit.
"""

from datetime import date
from decimal import Decimal

from django.contrib.admin.sites import AdminSite
from django.contrib.auth.models import Group
from django.test import RequestFactory
from django.db.models.deletion import ProtectedError
from django.test import TestCase
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.collectibles.models import CollectibleLedger
from apps.inventory.models import SystemAlert
from apps.inventory.tests import InventoryTestBase
from apps.pos.models import Customer, SalesTransaction
from apps.pos.tests import POSTestBase
from apps.requisitions.services import submit_requisition
from apps.requisitions.tests import RequisitionTestBase

from .admin import AuditLogAdmin
from .exceptions import ImmutableAuditLog
from .models import AuditLog, User
from .services import log_audit

LOGIN_URL = '/api/v1/auth/login/'
LOGOUT_URL = '/api/v1/auth/logout/'
REGISTER_URL = '/api/v1/auth/register/'
USERS_URL = '/api/v1/users/'
AUDIT_URL = '/api/v1/audit-logs/'
TRANSACTIONS_URL = '/api/v1/transactions/'
HELD_CARTS_URL = '/api/v1/held-carts/'
SHIFTS_URL = '/api/v1/shifts/'
ADJUSTMENTS_URL = '/api/v1/adjustments/'
ALERTS_URL = '/api/v1/alerts/'
GOODS_RECEIPTS_URL = '/api/v1/goods-receipts/'
LEDGER_PAYMENTS_URL = '/api/v1/ledger-payments/'
TOKENS_RELEASE_URL = '/api/v1/tokens/release/'

# Django's test client maps the WSGI environ key `HTTP_IDEMPOTENCY_KEY` onto the
# `Idempotency-Key` header; passing the header name itself would be ignored and the
# replay test would silently ring a second sale.


class AuditAssertions:
    """Read-side helpers. `AuditLog.objects.filter` stays usable — only update/delete raise."""

    def rows(self, action_type):
        return AuditLog.objects.filter(action_type=action_type)

    def assert_one_row(self, action_type, *, actor=None, contains=()):
        rows = self.rows(action_type)
        self.assertEqual(
            rows.count(), 1,
            f'expected exactly one {action_type} row, got '
            f'{list(rows.values_list("action_type", "description"))}')
        row = rows.get()
        if actor is not None:
            self.assertEqual(row.user_id, actor.pk)
            self.assertEqual(row.username_snapshot, actor.username)
        for fragment in contains:
            self.assertIn(fragment, row.description)
        return row

    def assert_one_row_for(self, action_type, actor, contains=()):
        """Same, scoped to ONE actor: several users log in during a test."""
        rows = self.rows(action_type).filter(user_id=actor.pk)
        self.assertEqual(
            rows.count(), 1,
            f'expected exactly one {action_type} row for {actor.username}, got '
            f'{list(rows.values_list("action_type", "description"))}')
        row = rows.get()
        self.assertEqual(getattr(row, 'username_snapshot', ''), actor.username)
        for fragment in contains:
            self.assertIn(fragment, row.description)
        return row

    def assert_no_rows(self, action_type):
        self.assertEqual(
            self.rows(action_type).count(), 0,
            f'no {action_type} row may be written by a refused event')


class _RoleUsersMixin:
    """Real JWT logins with a random per-run password (no `force_authenticate`)."""

    password = ''

    def _init_password(self):
        self.password = get_random_string(20)

    def _role_user(self, username, *group_names, is_staff=False):
        user = User.objects.create_user(
            username=username,
            email=f'{username}@audit.example.com',
            password=self.password,
            full_name=username,
            is_staff=is_staff,
        )
        for name in group_names:
            user.groups.add(Group.objects.get_or_create(name=name)[0])
        return user

    def _reset_password(self, user):
        user.set_password(self.password)
        user.save(update_fields=['password'])

    def _auth(self, user):
        login = APIClient().post(
            LOGIN_URL,
            {'username': user.username, 'password': self.password},
            format='json',
        )
        self.assertEqual(login.status_code, 200, login.data)
        return {'HTTP_AUTHORIZATION': f"Bearer {login.data['access']}"}


# ---------------------------------------------------------------------------
# POS: sale, return, held cart, shift
# ---------------------------------------------------------------------------

class SaleAuditTests(AuditAssertions, _RoleUsersMixin, POSTestBase):
    """POST /transactions/ — a sale and a return each write ONE row, in the sale's atomic."""

    def setUp(self):
        super().setUp()
        self._init_password()
        self._reset_password(self.cashier)
        self.cashier.groups.add(Group.objects.get_or_create(name='Cashier')[0])
        self.client = APIClient()
        self.auth = self._auth(self.cashier)

    def _payload(self, qty=2, source='WALK_IN'):
        return {
            'customer': self.customer.id,
            'source': source,
            'items': [{'variant_id': self.vuom.id, 'qty': qty,
                       'unit_price': '10.00'}],
            'payments': [{'method': 'CASH', 'amount_tendered': '100.00'}],
        }

    def _sell(self, qty=2, key=None, **extra):
        headers = dict(self.auth)
        if key:
            headers['HTTP_IDEMPOTENCY_KEY'] = key
        headers.update(extra)
        return self.client.post(
            TRANSACTIONS_URL, self._payload(qty), format='json', **headers)

    def test_sale_writes_exactly_one_row_with_actor_snapshot_and_document_number(self):
        response = self._sell()
        self.assertEqual(response.status_code, 201, response.data)
        transaction_no = response.data['transaction_no']

        row = self.assert_one_row(
            'SALE', actor=self.cashier, contains=[transaction_no])
        self.assertIsNotNone(row.ip_address)

    def test_refused_sale_writes_no_row(self):
        response = self._sell(qty=99999)
        self.assertEqual(response.status_code, 400, response.data)
        self.assert_no_rows('SALE')

    def test_idempotent_replay_writes_no_second_row(self):
        key = get_random_string(24)
        first = self._sell(key=key)
        self.assertEqual(first.status_code, 201, first.data)
        replay = self._sell(key=key)
        self.assertEqual(replay.status_code, 200, replay.data)

        self.assert_one_row(
            'SALE', contains=[first.data['transaction_no']])

    def test_ip_comes_from_remote_addr_only(self):
        response = self._sell(REMOTE_ADDR='10.9.9.9',
                              HTTP_X_FORWARDED_FOR='203.0.113.7')
        self.assertEqual(response.status_code, 201, response.data)
        rows = self.rows('SALE')
        self.assertEqual(rows.count(), 1)
        self.assertEqual(rows.get().ip_address, '10.9.9.9')

    def test_return_writes_one_return_row(self):
        response = self.client.post(
            TRANSACTIONS_URL,
            {
                'customer': self.customer.id,
                'source': 'RETURN',
                'items': [{'variant_id': self.vuom.id, 'qty': '2',
                           'unit_price': '10.00'}],
            },
            format='json', **self.auth,
        )
        self.assertEqual(response.status_code, 201, response.data)
        self.assert_one_row(
            'RETURN', actor=self.cashier,
            contains=[response.data['transaction_no']])
        self.assert_no_rows('SALE')


class HeldCartAuditTests(AuditAssertions, _RoleUsersMixin, POSTestBase):
    """POST /held-carts/{id}/complete/ is a SALE; DELETE /held-carts/{id}/ is a CART_VOID."""

    def setUp(self):
        super().setUp()
        self._init_password()
        self._reset_password(self.cashier)
        self.cashier.groups.add(Group.objects.get_or_create(name='Cashier')[0])
        self.client = APIClient()
        self.auth = self._auth(self.cashier)

    def _hold(self, qty='2'):
        response = self.client.post(
            HELD_CARTS_URL,
            {
                'customer': self.customer.id,
                'items': [{'variant_uom': self.vuom.id, 'qty': qty,
                           'unit_price': '10.00'}],
            },
            format='json', **self.auth,
        )
        self.assertEqual(response.status_code, 201, response.data)
        return response.data['id']

    def _complete(self, cart_id, key=None):
        headers = dict(self.auth)
        if key:
            headers['HTTP_IDEMPOTENCY_KEY'] = key
        return self.client.post(
            f'{HELD_CARTS_URL}{cart_id}/complete/',
            {'payments': [{'method': 'CASH', 'amount_tendered': '20.00'}]},
            format='json', **headers,
        )

    def test_completing_a_cart_writes_one_sale_row(self):
        cart_id = self._hold()
        response = self._complete(cart_id)
        self.assertEqual(response.status_code, 201, response.data)
        self.assert_one_row(
            'SALE', actor=self.cashier,
            contains=[response.data['transaction_no']])

    def test_completing_a_cart_twice_with_one_key_writes_one_row(self):
        cart_id = self._hold()
        key = get_random_string(24)
        first = self._complete(cart_id, key=key)
        self.assertEqual(first.status_code, 201, first.data)
        replay = self._complete(cart_id, key=key)
        self.assertEqual(replay.status_code, 200, replay.data)

        self.assert_one_row(
            'SALE', contains=[first.data['transaction_no']])

    def test_refused_completion_writes_no_row(self):
        cart_id = self._hold(qty='99999')
        response = self._complete(cart_id)
        self.assertEqual(response.status_code, 400, response.data)
        self.assert_no_rows('SALE')

    def test_voiding_a_cart_writes_one_cart_void_row(self):
        cart_id = self._hold()
        response = self.client.delete(f'{HELD_CARTS_URL}{cart_id}/', **self.auth)
        self.assertEqual(response.status_code, 204, response.data)
        self.assert_one_row(
            'CART_VOID', actor=self.cashier,
            contains=[f'#{cart_id}'])


class ShiftAuditTests(AuditAssertions, _RoleUsersMixin, POSTestBase):
    """POST /shifts/open/ and /shifts/{id}/close/ are money-handling events."""

    def setUp(self):
        super().setUp()
        self._init_password()
        self._reset_password(self.cashier)
        self.cashier.groups.add(Group.objects.get_or_create(name='Cashier')[0])
        self.client = APIClient()
        self.auth = self._auth(self.cashier)

    def _close_inherited_shift(self):
        self.shift.status = self.shift.Status.CLOSED
        self.shift.closing_count = self.shift.opening_float
        self.shift.save(update_fields=['status', 'closing_count'])

    def test_opening_a_shift_writes_one_shift_open_row(self):
        self._close_inherited_shift()
        response = self.client.post(
            f'{SHIFTS_URL}open/', {'opening_float': '3000.00'},
            format='json', **self.auth)
        self.assertEqual(response.status_code, 201, response.data)
        self.assert_one_row(
            'SHIFT_OPEN', actor=self.cashier,
            contains=[f'#{response.data["id"]}'])

    def test_a_second_open_writes_no_second_row(self):
        response = self.client.post(
            f'{SHIFTS_URL}open/', {'opening_float': '3000.00'},
            format='json', **self.auth)
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['code'], 'SHIFT_ALREADY_OPEN')
        self.assert_no_rows('SHIFT_OPEN')

    def test_closing_a_shift_writes_one_shift_close_row(self):
        response = self.client.post(
            f'{SHIFTS_URL}{self.shift.pk}/close/', {'closing_count': '5000.00'},
            format='json', **self.auth)
        self.assertEqual(response.status_code, 200, response.data)
        row = self.assert_one_row(
            'SHIFT_CLOSE', actor=self.cashier,
            contains=[f'#{self.shift.pk}'])
        self.assertIsNotNone(row.ip_address)


# ---------------------------------------------------------------------------
# Requisitions: approve, reject, release
# ---------------------------------------------------------------------------

class RequisitionAuditTests(AuditAssertions, _RoleUsersMixin, RequisitionTestBase):
    """Approval, rejection and release are the credit-bearing events of a requisition."""

    def setUp(self):
        super().setUp()
        self._init_password()
        for user in (self.manager, self.foreman, self.cashier):
            self._reset_password(user)
        self.manager.groups.add(Group.objects.get_or_create(name='Store Manager')[0])
        self.foreman.groups.add(Group.objects.get_or_create(name='Site Foreman')[0])
        self.cashier.groups.add(Group.objects.get_or_create(name='Cashier')[0])
        self.requisition.req_number = 'REQ-AUDIT-0001'
        self.requisition.save(update_fields=['req_number'])
        self.client = APIClient()

    def test_approve_writes_one_row_with_the_req_number(self):
        submit_requisition(requisition=self.requisition)
        response = self.client.post(
            f'/api/v1/requisitions/{self.requisition.pk}/approve/',
            format='json', **self._auth(self.manager))
        self.assertEqual(response.status_code, 200, response.data)
        self.assert_one_row(
            'REQ_APPROVE', actor=self.manager,
            contains=['REQ-AUDIT-0001'])
        # The token UUID is a bearer credential: it may not reach the audit text.
        self.assertNotIn(response.data['token'], self.rows(
            'REQ_APPROVE').get().description)

    def test_reject_writes_one_row_with_the_req_number(self):
        submit_requisition(requisition=self.requisition)
        response = self.client.post(
            f'/api/v1/requisitions/{self.requisition.pk}/reject/',
            format='json', **self._auth(self.manager))
        self.assertEqual(response.status_code, 200, response.data)
        self.assert_one_row(
            'REQ_REJECT', actor=self.manager,
            contains=['REQ-AUDIT-0001'])

    def test_self_approval_writes_no_row(self):
        self.requisition.requested_by = self.manager
        self.requisition.save(update_fields=['requested_by'])
        submit_requisition(requisition=self.requisition)

        response = self.client.post(
            f'/api/v1/requisitions/{self.requisition.pk}/approve/',
            format='json', **self._auth(self.manager))
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['code'], 'SELF_APPROVAL')
        self.assert_no_rows('REQ_APPROVE')

    def test_release_writes_one_row_without_the_token_uuid(self):
        submit_requisition(requisition=self.requisition)
        approve = self.client.post(
            f'/api/v1/requisitions/{self.requisition.pk}/approve/',
            format='json', **self._auth(self.manager))
        self.assertEqual(approve.status_code, 200, approve.data)
        token = approve.data['token']

        response = self.client.post(
            TOKENS_RELEASE_URL, {'token': token},
            format='json', **self._auth(self.manager))
        self.assertEqual(response.status_code, 201, response.data)

        row = self.assert_one_row(
            'RELEASE', actor=self.manager,
            contains=['REQ-AUDIT-0001', response.data['transaction_no']])
        self.assertNotIn(token, row.description)


# ---------------------------------------------------------------------------
# Inventory: goods receipt, adjustment, alert resolve
# ---------------------------------------------------------------------------

class InventoryAuditTests(AuditAssertions, _RoleUsersMixin, InventoryTestBase):
    """The stock ledger's writes: receiving, adjusting, clearing an alert."""

    def setUp(self):
        super().setUp()
        self._init_password()
        self._reset_password(self.user)
        self.user.groups.add(Group.objects.get_or_create(name='Stock Manager')[0])
        self.client = APIClient()
        self.auth = self._auth(self.user)

    def test_processing_a_goods_receipt_writes_one_row(self):
        _po, _item, receipt = self._receive('10')
        response = self.client.post(
            f'{GOODS_RECEIPTS_URL}{receipt.pk}/process/', format='json', **self.auth)
        self.assertEqual(response.status_code, 200, response.data)
        self.assert_one_row(
            'RECEIPT', actor=self.user,
            contains=[f'#{receipt.pk}'])

    def test_stock_adjustment_writes_one_row(self):
        _po, _item, receipt = self._receive('10')
        self.client.post(
            f'{GOODS_RECEIPTS_URL}{receipt.pk}/process/', format='json', **self.auth)
        response = self.client.post(
            ADJUSTMENTS_URL,
            {'variant': self.variant.id, 'adjustment_type': 'SHRINKAGE',
             'qty_adjusted': '-2'},
            format='json', **self.auth)
        self.assertEqual(response.status_code, 201, response.data)
        self.assert_one_row(
            'STOCK_ADJUST', actor=self.user,
            contains=[f'#{response.data["id"]}', 'Portland Cement'])

    def test_resolving_an_alert_writes_one_row(self):
        alert = SystemAlert.objects.create(
            alert_type=SystemAlert.AlertType.LOW_STOCK,
            variant=self.variant,
            message='Portland Cement 40kg is low.',
        )
        response = self.client.post(
            f'{ALERTS_URL}{alert.pk}/resolve/', format='json', **self.auth)
        self.assertEqual(response.status_code, 200, response.data)
        self.assert_one_row(
            'ALERT_RESOLVE', actor=self.user,
            contains=[f'#{alert.pk}'])

    def test_a_second_resolve_writes_no_second_row(self):
        alert = SystemAlert.objects.create(
            alert_type=SystemAlert.AlertType.LOW_STOCK,
            variant=self.variant,
            message='Portland Cement 40kg is low.',
        )
        first = self.client.post(
            f'{ALERTS_URL}{alert.pk}/resolve/', format='json', **self.auth)
        self.assertEqual(first.status_code, 200, first.data)
        second = self.client.post(
            f'{ALERTS_URL}{alert.pk}/resolve/', format='json', **self.auth)
        self.assertEqual(second.status_code, 400, second.data)
        self.assertEqual(second.data['code'], 'ALERT_ALREADY_RESOLVED')
        self.assert_one_row('ALERT_RESOLVE')


# ---------------------------------------------------------------------------
# Collectibles: ledger payment
# ---------------------------------------------------------------------------

class PaymentAuditTests(AuditAssertions, _RoleUsersMixin, TestCase):
    """POST /ledger-payments/ moves money against a receivable."""

    def setUp(self):
        self._init_password()
        self.cashier = self._role_user('audit_cashier', 'Cashier')
        self.customer = Customer.objects.create(name='Utang Corp')
        self.txn = SalesTransaction.objects.create(
            customer=self.customer, cashier=self.cashier,
            transaction_no='TRX-AUDIT-0100',
            vatable_sales=Decimal('500'), grand_total=Decimal('500'))
        self.ledger = CollectibleLedger.objects.create(
            customer=self.customer, transaction=self.txn,
            original_amount=Decimal('500'), balance_due=Decimal('500'),
            due_date=date.today(), status=CollectibleLedger.Status.OPEN)
        self.client = APIClient()
        self.auth = self._auth(self.cashier)

    def test_payment_writes_one_row_with_the_transaction_number(self):
        response = self.client.post(
            LEDGER_PAYMENTS_URL,
            {'collectible': self.ledger.pk, 'amount_paid': '100.00',
             'payment_method': 'CASH'},
            format='json', **self.auth)
        self.assertEqual(response.status_code, 201, response.data)
        self.assert_one_row(
            'PAYMENT', actor=self.cashier,
            contains=['TRX-AUDIT-0100'])


# ---------------------------------------------------------------------------
# Users: create, update, deactivate, role change
# ---------------------------------------------------------------------------

class UserEventAuditTests(AuditAssertions, _RoleUsersMixin, TestCase):
    """Admin authority events, and the login/logout rows that already existed."""

    def setUp(self):
        self._init_password()
        self.admin = self._role_user('audit_admin', 'Admin')
        self.admin2 = self._role_user('audit_admin2', 'Admin')
        self.cashier = self._role_user('audit_target', 'Cashier')
        # `assign_role` resolves the group by name; role groups are not auto-created.
        Group.objects.get_or_create(name='Store Manager')
        self.client = APIClient()
        self.auth = self._auth(self.admin)

    def test_register_writes_one_create_row(self):
        response = self.client.post(
            REGISTER_URL,
            {'username': 'audit_new', 'email': 'audit_new@audit.example.com',
             'full_name': 'New Person', 'password': get_random_string(16),
             'group_name': 'Cashier'},
            format='json', **self.auth)
        self.assertEqual(response.status_code, 201, response.data)
        self.assert_one_row(
            'CREATE', actor=self.admin, contains=['audit_new'])

    def test_patch_writes_one_update_row(self):
        response = self.client.patch(
            f'{USERS_URL}{self.cashier.pk}/',
            {'full_name': 'Renamed Person'}, format='json', **self.auth)
        self.assertEqual(response.status_code, 200, response.data)
        self.assert_one_row(
            'UPDATE', actor=self.admin,
            contains=['audit_target'])

    def test_deactivating_a_user_writes_a_deactivate_row(self):
        response = self.client.patch(
            f'{USERS_URL}{self.cashier.pk}/',
            {'is_active': False}, format='json', **self.auth)
        self.assertEqual(response.status_code, 200, response.data)
        self.assert_one_row(
            'USER_DEACTIVATE', actor=self.admin,
            contains=['audit_target'])
        self.assert_no_rows('UPDATE')

    def test_the_last_admin_refusal_writes_no_row(self):
        User.objects.filter(pk=self.admin2.pk).update(is_active=False)
        response = self.client.patch(
            f'{USERS_URL}{self.admin.pk}/',
            {'is_active': False}, format='json', **self.auth)
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['code'], 'LAST_ADMIN')
        self.assert_no_rows('USER_DEACTIVATE')
        self.assert_no_rows('UPDATE')

    def test_assign_role_writes_one_role_change_row(self):
        response = self.client.post(
            f'{USERS_URL}{self.cashier.pk}/assign_role/',
            {'group_name': 'Store Manager'}, format='json', **self.auth)
        self.assertEqual(response.status_code, 200, response.data)
        self.assert_one_row(
            'ROLE_CHANGE', actor=self.admin,
            contains=['audit_target', 'Store Manager'])

    def test_remove_role_writes_one_role_change_row(self):
        response = self.client.post(
            f'{USERS_URL}{self.cashier.pk}/remove_role/',
            {'group_name': 'Cashier'}, format='json', **self.auth)
        self.assertEqual(response.status_code, 200, response.data)
        self.assert_one_row(
            'ROLE_CHANGE', actor=self.admin,
            contains=['audit_target', 'Cashier'])

    def test_login_and_logout_are_still_logged(self):
        auth = self._auth(self.cashier)
        self.assert_one_row_for('LOGIN', self.cashier)

        logout = self.client.post(LOGOUT_URL, format='json', **auth)
        self.assertEqual(logout.status_code, 204, logout.data)
        self.assert_one_row_for('LOGOUT', self.cashier)


# ---------------------------------------------------------------------------
# Append-only guarantees
# ---------------------------------------------------------------------------

class AuditImmutabilityTests(AuditAssertions, _RoleUsersMixin, TestCase):
    """A written row is evidence: it can be added, never changed and never removed."""

    def setUp(self):
        self._init_password()
        self.author = self._role_user('audit_author', 'Cashier')
        self.row = log_audit(
            user=self.author,
            action_type='SALE',
            description='Sale TRX-AUDIT-0200 rung.',
            ip_address='10.0.0.1',
        )

    def test_username_snapshot_is_filled_from_the_user(self):
        # `getattr` so a missing field is an assertion failure, not an AttributeError:
        # the RED for this test is "the snapshot is blank", not "the code cannot run".
        self.assertEqual(getattr(self.row, 'username_snapshot', ''), 'audit_author')

    def test_username_kwarg_overrides_the_snapshot(self):
        row = log_audit(
            user=None,
            action_type='LOGIN_FAILED',
            description='Failed login for ghost.',
            username='ghost',
        )
        self.assertEqual(getattr(row, 'username_snapshot', ''), 'ghost')
        self.assertIsNone(row.user_id)

    def test_saving_an_existing_row_raises(self):
        self.row.description = 'rewritten history'
        with self.assertRaises(ImmutableAuditLog):
            self.row.save()

    def test_deleting_a_row_raises(self):
        with self.assertRaises(ImmutableAuditLog):
            self.row.delete()

    def test_queryset_update_raises(self):
        with self.assertRaises(ImmutableAuditLog):
            AuditLog.objects.filter(pk=self.row.pk).update(description='nope')

    def test_queryset_delete_raises(self):
        with self.assertRaises(ImmutableAuditLog):
            AuditLog.objects.all().delete()

    def test_the_row_still_has_its_original_text(self):
        self.row.refresh_from_db()
        self.assertEqual(self.row.description, 'Sale TRX-AUDIT-0200 rung.')

    def test_admin_may_not_add_change_or_delete(self):
        # A real request with a SUPERUSER on it: before the override every one of these
        # answers True, which is what makes the assertion below a real RED.
        request = RequestFactory().get('/admin/users/auditlog/')
        request.user = User.objects.create_superuser(
            username='audit_desk_admin', email='audit_desk@audit.example.com',
            password=get_random_string(20))
        model_admin = AuditLogAdmin(AuditLog, AdminSite())
        self.assertFalse(model_admin.has_add_permission(request))
        self.assertFalse(model_admin.has_change_permission(request))
        self.assertFalse(model_admin.has_delete_permission(request))

    def test_deleting_a_user_with_audit_rows_raises_protected_error(self):
        with self.assertRaises(ProtectedError):
            self.author.delete()
        self.assertTrue(User.objects.filter(pk=self.author.pk).exists())
        self.assertTrue(AuditLog.objects.filter(pk=self.row.pk).exists())

    def test_api_exposes_the_username_snapshot_read_only(self):
        admin = self._role_user('audit_reader', 'Admin')
        response = self.client.get(AUDIT_URL, **self._auth(admin))
        self.assertEqual(response.status_code, 200, response.data)
        # `results[0]` is the newest row and the logins in this test are newer, so the
        # row is found by id: the claim under test is about THIS row's snapshot.
        row = next(
            r for r in response.data['results'] if r['id'] == self.row.pk)
        self.assertEqual(row.get('username_snapshot'), 'audit_author')
        self.assertEqual(row.get('user_email'), 'audit_author@audit.example.com')

        # ... and a client cannot write it back: the viewset is read-only.
        patch = self.client.patch(
            f'{AUDIT_URL}{self.row.pk}/',
            {'username_snapshot': 'forged'}, format='json', **self._auth(admin))
        self.assertEqual(patch.status_code, 405, patch.data)


class AuditModelShapeTests(AuditAssertions, TestCase):
    """Action vocabulary: the codes are what clients filter the trail by."""

    def test_new_action_types_exist_and_fit_the_column(self):
        expected = [
            'LOGIN_FAILED', 'RETURN', 'RELEASE', 'REQ_APPROVE', 'REQ_REJECT',
            'ALERT_RESOLVE', 'SHIFT_OPEN', 'SHIFT_CLOSE', 'CART_VOID',
            'ROLE_CHANGE', 'USER_DEACTIVATE',
        ]
        for code in expected:
            with self.subTest(code=code):
                self.assertIn(code, AuditLog.ActionType.values)
                self.assertLessEqual(len(code), 20)

    def test_user_fk_is_protect(self):
        field = AuditLog._meta.get_field('user')
        self.assertEqual(field.remote_field.on_delete.__name__, 'PROTECT')
