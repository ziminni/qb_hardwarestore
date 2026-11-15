# pyright: reportAttributeAccessIssue=false
from datetime import date, timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.test import TestCase
from rest_framework.test import APIClient

from apps.collectibles.models import CollectibleLedger, CollectiblePayment, ProjectPaymentReceipt
from apps.pos.models import Customer, SalesTransaction
from apps.requisitions.models import Project
from apps.users.models import AuditLog

User = get_user_model()
CPMS_SERVICE_GROUP = 'CPMS Service'


class ProjectPaymentReceiptTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        cpms_group, _ = Group.objects.get_or_create(name=CPMS_SERVICE_GROUP)
        mgr_group, _ = Group.objects.get_or_create(name='Store Manager')
        self.cpms_user = User.objects.create_user(
            username='cpms_svc_test',
            email='cpms_svc@test.local',
            password='pw',
            full_name='CPMS Service',
        )
        self.cpms_user.groups.add(cpms_group)

        self.manager = User.objects.create_user(
            username='mgr_test',
            email='mgr@test.local',
            password='pw',
            full_name='Store Manager',
        )
        self.manager.groups.add(mgr_group)

        self.customer = Customer.objects.create(
            name='Reyes Construction',
            customer_type='CONTRACTOR',
        )
        self.project = Project.objects.create(
            cpms_project_id='PRJ-101',
            name='Tower A',
            customer=self.customer,
        )

        self.txn1 = SalesTransaction.objects.create(
            customer=self.customer,
            cashier=self.manager,
            transaction_no='TXN-PRJ-001',
            source=SalesTransaction.Source.REQUISITION,
            vatable_sales=Decimal('1000.00'),
            vat_amount=Decimal('0.00'),
            discount_amount=Decimal('0.00'),
            grand_total=Decimal('1000.00'),
        )
        self.txn2 = SalesTransaction.objects.create(
            customer=self.customer,
            cashier=self.manager,
            transaction_no='TXN-PRJ-002',
            source=SalesTransaction.Source.REQUISITION,
            vatable_sales=Decimal('1500.00'),
            vat_amount=Decimal('0.00'),
            discount_amount=Decimal('0.00'),
            grand_total=Decimal('1500.00'),
        )

        self.ledger1 = CollectibleLedger.objects.create(
            customer=self.customer,
            transaction=self.txn1,
            project=self.project,
            original_amount=Decimal('1000.00'),
            balance_due=Decimal('1000.00'),
            due_date=date.today() + timedelta(days=10),
            status=CollectibleLedger.Status.OPEN,
        )
        self.ledger2 = CollectibleLedger.objects.create(
            customer=self.customer,
            transaction=self.txn2,
            project=self.project,
            original_amount=Decimal('1500.00'),
            balance_due=Decimal('1500.00'),
            due_date=date.today() + timedelta(days=20),
            status=CollectibleLedger.Status.OPEN,
        )

    def test_cpms_submits_receipt_and_staff_approves_partial_oldest_first(self):
        self.client.force_authenticate(user=self.cpms_user)
        url = '/api/v1/integration/cpms/projects/PRJ-101/payment-receipts/'
        payload = {
            'cpms_payment_id': 'PAY-0001',
            'amount': '1800.00',
            'payment_method': 'BANK_TRANSFER',
            'reference_no': 'BDO-998877',
            'notes': 'Online transfer for Tower A',
            'submitted_by_name': 'Liza Accountant',
        }
        res = self.client.post(url, payload, format='json')
        self.assertEqual(res.status_code, 201, res.data)
        self.assertEqual(res.data['status'], 'WAITING')
        self.assertIsNone(res.data['approved_amount'])
        receipt_id = res.data['id']

        # Idempotent retry returns 200 without duplicating
        retry = self.client.post(url, payload, format='json')
        self.assertEqual(retry.status_code, 200, retry.data)
        self.assertEqual(ProjectPaymentReceipt.objects.count(), 1)

        # Waiting receipt does not reduce balance yet
        payables = self.client.get('/api/v1/integration/cpms/projects/PRJ-101/payables/')
        self.assertEqual(payables.data['balance'], '2500.00')

        # Staff approves 1600.00 (partial approval across ledger1=1000 and ledger2=600)
        self.client.force_authenticate(user=self.manager)
        approve_res = self.client.post(
            f'/api/v1/payment-receipts/{receipt_id}/approve/',
            {'approved_amount': '1600.00'},
            format='json',
        )
        self.assertEqual(approve_res.status_code, 200, approve_res.data)
        self.assertEqual(approve_res.data['status'], 'APPROVED')
        self.assertEqual(approve_res.data['approved_amount'], '1600.00')

        self.ledger1.refresh_from_db()
        self.ledger2.refresh_from_db()
        self.assertEqual(self.ledger1.balance_due, Decimal('0.00'))
        self.assertEqual(self.ledger1.status, CollectibleLedger.Status.PAID)
        self.assertEqual(self.ledger2.balance_due, Decimal('900.00'))
        self.assertEqual(self.ledger2.status, CollectibleLedger.Status.PARTIAL)
        self.assertEqual(CollectiblePayment.objects.count(), 2)
        self.assertTrue(
            AuditLog.objects.filter(
                action_type=AuditLog.ActionType.PAYMENT,
                description__icontains='BDO-998877',
            ).exists()
        )

        # CPMS reads back updated payables and approved receipt
        self.client.force_authenticate(user=self.cpms_user)
        payables_after = self.client.get(
            '/api/v1/integration/cpms/projects/PRJ-101/payables/'
        )
        self.assertEqual(payables_after.data['paid'], '1600.00')
        self.assertEqual(payables_after.data['balance'], '900.00')

        listed = self.client.get(url)
        self.assertEqual(listed.status_code, 200)
        self.assertEqual(listed.data['results'][0]['status'], 'APPROVED')
        self.assertEqual(listed.data['results'][0]['approved_amount'], '1600.00')

    def test_staff_declines_receipt_with_reason_and_leaves_ledgers_untouched(self):
        self.client.force_authenticate(user=self.cpms_user)
        url = '/api/v1/integration/cpms/projects/PRJ-101/payment-receipts/'
        res = self.client.post(
            url,
            {
                'cpms_payment_id': 'PAY-0002',
                'amount': '500.00',
                'payment_method': 'GCASH',
                'reference_no': 'GC-112233',
            },
            format='json',
        )
        receipt_id = res.data['id']

        self.client.force_authenticate(user=self.manager)
        missing_reason = self.client.post(
            f'/api/v1/payment-receipts/{receipt_id}/decline/',
            {'reason': '   '},
            format='json',
        )
        self.assertEqual(missing_reason.status_code, 400)

        declined = self.client.post(
            f'/api/v1/payment-receipts/{receipt_id}/decline/',
            {'reason': 'Reference number not found in GCash statement'},
            format='json',
        )
        self.assertEqual(declined.status_code, 200, declined.data)
        self.assertEqual(declined.data['status'], 'DECLINED')
        self.assertEqual(
            declined.data['decline_reason'],
            'Reference number not found in GCash statement',
        )
        self.ledger1.refresh_from_db()
        self.assertEqual(self.ledger1.balance_due, Decimal('1000.00'))

    def test_cashier_can_read_but_not_decide_a_receipt(self):
        """Approving moves debt, so it is a manager decision like clearing a cheque."""
        self.client.force_authenticate(user=self.cpms_user)
        res = self.client.post(
            '/api/v1/integration/cpms/projects/PRJ-101/payment-receipts/',
            {'cpms_payment_id': 'PAY-0009', 'amount': '100.00',
             'payment_method': 'GCASH', 'reference_no': 'GC-1'},
            format='json',
        )
        receipt_id = res.data['id']
        cashier = User.objects.create_user(
            username='cashier_test', email='cashier@test.local', password='pw',
            full_name='Cashier',
        )
        cashier.groups.add(Group.objects.get_or_create(name='Cashier')[0])
        self.client.force_authenticate(user=cashier)

        for verb, body in (('approve', {}), ('decline', {'reason': 'no'})):
            res = self.client.post(
                f'/api/v1/payment-receipts/{receipt_id}/{verb}/', body, format='json')
            self.assertEqual(res.status_code, 403, (verb, res.data))
        receipt = ProjectPaymentReceipt.objects.get(pk=receipt_id)
        self.assertEqual(receipt.status, 'WAITING')
        self.ledger1.refresh_from_db()
        self.assertEqual(self.ledger1.balance_due, Decimal('1000.00'))

        # Cashier can read payment history and receipts log, read-only.
        self.assertEqual(
            self.client.get('/api/v1/payment-receipts/').status_code, 200
        )
        self.assertEqual(
            self.client.get('/api/v1/ledger-payments/').status_code, 200
        )

    def test_approved_cpms_receipt_links_payments_and_sets_paid_at(self):
        self.client.force_authenticate(user=self.cpms_user)
        submit_res = self.client.post(
            '/api/v1/integration/cpms/projects/PRJ-101/payment-receipts/',
            {
                'cpms_payment_id': 'PAY-0010',
                'amount': '1600.00',
                'payment_method': 'BANK_TRANSFER',
                'reference_no': 'BDO-CPMS-10',
            },
            format='json',
        )
        self.assertEqual(submit_res.status_code, 201, submit_res.data)
        receipt_id = submit_res.data['id']

        self.client.force_authenticate(user=self.manager)
        approve_res = self.client.post(
            f'/api/v1/payment-receipts/{receipt_id}/approve/',
            {},
            format='json',
        )
        self.assertEqual(approve_res.status_code, 200, approve_res.data)
        self.assertEqual(approve_res.data['decided_by_name'], 'Store Manager')
        self.assertIsNotNone(approve_res.data['decided_at'])

        payments_res = self.client.get('/api/v1/ledger-payments/')
        self.assertEqual(payments_res.status_code, 200, payments_res.data)
        rows = payments_res.data['results']
        self.assertEqual(len(rows), 2)
        # Newest first (-payment_date, -id): ledger2 payment was created second
        self.assertEqual(rows[0]['transaction_no'], 'TXN-PRJ-002')
        self.assertEqual(rows[1]['transaction_no'], 'TXN-PRJ-001')
        for row in rows:
            self.assertEqual(row['customer_name'], 'Reyes Construction')
            self.assertEqual(row['project_name'], 'Tower A')
            self.assertEqual(row['processed_by_name'], 'Store Manager')
            self.assertEqual(row['payment_receipt'], receipt_id)
            self.assertEqual(row['cpms_receipt_ref'], 'BDO-CPMS-10')
            self.assertEqual(row['official_receipt_no'], 'BDO-CPMS-10')

        ledgers_res = self.client.get('/api/v1/ledgers/')
        self.assertEqual(ledgers_res.status_code, 200)
        by_id = {row['id']: row for row in ledgers_res.data['results']}
        self.assertIsNotNone(by_id[self.ledger1.id]['paid_at'])
        self.assertIsNone(by_id[self.ledger2.id]['paid_at'])
