# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportMissingImports=false
#
# Same directive and reason as apps/pos/tests.py: the checker runs with a working directory
# outside the repo, so no pyrightconfig is found and every `Model.objects` access reads as a
# type error on valid Django. The test run is the authority.

"""Reports tests — the requisition history knows every status CPMS can leave behind.

Task 10 (decisions 06 and 08). Two things this report used to get wrong by omission:

  * `CLOSED` did not exist when the counts were written. A closed remainder is still a
    requisition a manager needs to see, and a status missing from the count reads as "it
    never happened".
  * the two names are CPMS's TEXT now, not FKs. The listing keeps its old wire keys
    (`requested_by`, `approved_by`) so the screen does not change, and `approved_by` is
    `null` when nobody approved instead of an empty string.
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.test import TestCase

from apps.pos.models import Customer, SalesTransaction
from apps.requisitions.models import Project, Requisition

User = get_user_model()

HISTORY_URL = '/api/v1/reports/requisition-history/'
SALES_SUMMARY_URL = '/api/v1/reports/sales-summary/'
LOGIN_URL = '/api/v1/auth/login/'
PASSWORD = 'reports-pass-12345'  # noqa: S105 # nosemgrep: python.lang.security.audit.hardcoded-password
# A throwaway login for a per-run test database: nothing outside the test run can use it.


class RequisitionHistoryTests(TestCase):
    def setUp(self):
        # nosemgrep: a throwaway per-run database; nothing outside the test run can log in.
        self.manager = User.objects.create_user(
            username='reportsmanager', email='rm@x.com', password=PASSWORD,
            full_name='Maria Santos')
        self.manager.groups.add(Group.objects.get_or_create(name='Store Manager')[0])
        self.customer = Customer.objects.create(
            name='Dela Cruz Construction',
            customer_type=Customer.Type.CONTRACTOR)
        self.project = Project.objects.create(
            name='2-Storey House Mandaue', customer=self.customer)

        login = self.client.post(
            LOGIN_URL,
            {'username': 'reportsmanager', 'password': PASSWORD},
            content_type='application/json')
        self.assertEqual(login.status_code, 200, 'the manager must be able to log in')
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {login.json()["access"]}'}

    def _requisition(self, req_number, status, *, requester='Ben Cruz',
                     approver='Maria Santos'):
        return Requisition.objects.create(
            project=self.project,
            req_number=req_number,
            status=status,
            requester_name=requester,
            approver_name=approver,
        )

    def _history(self, query=''):
        """The default 30-day window, deliberately NOT `from=today&to=today`.

        A hand-built single-day range flakes at midnight: `Requisition.created_at` comes
        from `auto_now_add`, so a row created at 23:59:59 sits on the previous day and
        falls outside a range computed a moment later on the next one. The endpoint's
        default window (last 30 days) cannot straddle the boundary this way.
        """
        response = self.client.get(
            f'{HISTORY_URL}?{query}',
            **self.auth)  # pyright: ignore[reportArgumentType]
        self.assertEqual(response.status_code, 200, response.content)
        return response.json()

    def test_the_counts_include_closed_and_partial(self):
        self._requisition('REQ-C-1', Requisition.Status.CLOSED)
        self._requisition('REQ-P-1', Requisition.Status.PARTIAL)
        self._requisition('REQ-R-1', Requisition.Status.RELEASED)

        body = self._history()

        counts = {row['status']: row['count'] for row in body['count_by_status']}
        self.assertEqual(
            counts.get('CLOSED'), 1,
            'a closed remainder still happened and has to be countable')
        self.assertEqual(
            counts.get('PARTIAL'), 1,
            'a partly released request is the one a manager chases')
        self.assertEqual(counts.get('RELEASED'), 1)

    def test_the_listing_names_the_requester_and_the_approver_as_text(self):
        self._requisition(
            'REQ-T-1', Requisition.Status.ACCEPTED,
            requester='Ben Cruz', approver='Ana Lopez')

        rows = self._history()['requisitions']

        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['requested_by'], 'Ben Cruz')
        self.assertEqual(rows[0]['approved_by'], 'Ana Lopez')
        self.assertEqual(rows[0]['status'], 'ACCEPTED')

    def test_an_approved_by_nobody_is_null_not_an_empty_string(self):
        self._requisition('REQ-T-2', Requisition.Status.CANCELLED, approver='')

        rows = self._history()['requisitions']

        self.assertEqual(len(rows), 1)
        self.assertIsNone(
            rows[0]['approved_by'],
            'an empty string would render as a blank column instead of "nobody"')

    def test_the_status_filter_accepts_closed(self):
        self._requisition('REQ-C-2', Requisition.Status.CLOSED)
        self._requisition('REQ-A-1', Requisition.Status.ACCEPTED)

        body = self._history('&status=CLOSED')

        self.assertEqual(body['status_filter'], 'CLOSED')
        self.assertEqual(
            [row['req_number'] for row in body['requisitions']], ['REQ-C-2'])

    def test_the_counts_include_the_three_active_review_states(self):
        # Phase 1b (decision 13): the statuses the Requests-from-projects screen lives on.
        # A word missing from the counts reads as "it never happened".
        self._requisition('REQ-W-1', Requisition.Status.WAITING)
        self._requisition('REQ-A-2', Requisition.Status.ACCEPTED)
        self._requisition('REQ-D-1', Requisition.Status.DECLINED)

        counts = {row['status']: row['count'] for row in self._history()['count_by_status']}

        self.assertEqual(counts.get('WAITING'), 1)
        self.assertEqual(counts.get('ACCEPTED'), 1)
        self.assertEqual(counts.get('DECLINED'), 1)

    def test_the_store_decision_does_not_replace_the_cpms_approver(self):
        # Decision 08/09: CPMS approved the request and reports its own approver; the POS
        # store answer changes the STATUS and the lines, never that name. The two people
        # stay distinct on the report.
        self._requisition('REQ-W-2', Requisition.Status.WAITING,
                          requester='Rey Quester', approver='Ana Lopez')
        self._requisition('REQ-D-2', Requisition.Status.DECLINED,
                          requester='Ben Cruz', approver='Jose Ramos')

        rows = {row['req_number']: row for row in self._history()['requisitions']}

        self.assertEqual(rows['REQ-W-2']['approved_by'], 'Ana Lopez')
        self.assertEqual(rows['REQ-D-2']['approved_by'], 'Jose Ramos')
        for row in rows.values():
            self.assertNotEqual(row['approved_by'], row['requested_by'],
                                'the approver is never the requester')

    def test_the_status_filter_accepts_waiting(self):
        self._requisition('REQ-W-3', Requisition.Status.WAITING)
        self._requisition('REQ-D-3', Requisition.Status.DECLINED)

        body = self._history('&status=WAITING')

        self.assertEqual(body['status_filter'], 'WAITING')
        self.assertEqual(
            [row['req_number'] for row in body['requisitions']], ['REQ-W-3'])


class SalesSummaryDiscountTests(TestCase):
    """Phase 4 task B1 (decision 18): discounts come BACK to the sales report.

    D12 had removed the Discounts row; decision 18 supersedes it, because a discount is
    money the shop chose not to take and a report that hides it makes the day's takings
    look like a pricing error. The totals also carry the VAT the sale charged, so the
    report agrees with the receipt.
    """

    def setUp(self):
        self.manager = User.objects.create_user(
            username='summarymanager', email='sm@x.com', password=PASSWORD,
            full_name='Maria Santos')
        self.manager.groups.add(Group.objects.get_or_create(name='Store Manager')[0])
        self.cashier = User.objects.create_user(
            username='summarycashier', email='sc@x.com', password=PASSWORD,
            full_name='Cashy Ir')
        self.customer = Customer.objects.create(name='Juan Dela Cruz')
        login = self.client.post(
            LOGIN_URL,
            {'username': 'summarymanager', 'password': PASSWORD},
            content_type='application/json')
        self.assertEqual(login.status_code, 200)
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {login.json()["access"]}'}

    def _sale(self, *, grand_total, discount, vatable, vat):
        return SalesTransaction.objects.create(
            customer=self.customer, cashier=self.cashier,
            transaction_no=f'TRX-TEST-{grand_total}-{discount}',
            grand_total=Decimal(grand_total), discount_amount=Decimal(discount),
            vatable_sales=Decimal(vatable), vat_amount=Decimal(vat),
        )

    def test_the_totals_carry_discounts_vatable_sales_and_vat(self):
        self._sale(grand_total='18.00', discount='2.00', vatable='16.07', vat='1.93')
        self._sale(grand_total='20.00', discount='0.00', vatable='17.86', vat='2.14')

        response = self.client.get(
            SALES_SUMMARY_URL, **self.auth)  # pyright: ignore[reportArgumentType]

        self.assertEqual(response.status_code, 200, response.content)
        totals = response.json()['totals']
        self.assertEqual(Decimal(str(totals['discounts'])), Decimal('2.00'))
        self.assertEqual(Decimal(str(totals['vatable_sales'])), Decimal('33.93'))
        self.assertEqual(Decimal(str(totals['vat'])), Decimal('4.07'))
        self.assertEqual(Decimal(str(totals['gross_sales'])), Decimal('38.00'))
        by_day = response.json()['by_day']
        self.assertEqual(Decimal(str(by_day[0]['discounts'])), Decimal('2.00'))
