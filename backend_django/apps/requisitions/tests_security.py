# pyright: reportAttributeAccessIssue=false
"""Requisitions — token secrecy, separation of duties, lock after submit (Phase 2 task 3).

The material token is a BEARER credential: whoever holds the UUID releases the goods and
posts the receivable. Before this task `GET /api/v1/requisitions/` (RequisitionSerializer.token)
and `GET /api/v1/tokens/` answered any authenticated user, so a cashier could release
material that was never handed to them. These tests pin the new answers over HTTP because
the contract that matters is the status code and the body the client sees.

Also pinned: a manager may not approve a requisition they requested (separation of
duties), and a requisition + its lines are frozen once it leaves DRAFT — otherwise items
could be edited after approval and the token would release what nobody approved.
"""

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.users.models import AuditLog

from .models import MaterialToken, Requisition, RequisitionItem
from .serializers import RequisitionSerializer
from .services import approve_requisition, submit_requisition
from .tests import RequisitionTestBase

User = get_user_model()

LIST_URL = '/api/v1/requisitions/'
TOKENS_URL = '/api/v1/tokens/'
ITEMS_URL = '/api/v1/req-items/'
VERIFY_URL = '/api/v1/tokens/verify/'


class _SecurityBase(RequisitionTestBase):
    """Adds the role groups the API checks to `RequisitionTestBase`'s users.

    The Phase 1 fixture creates its users WITHOUT groups because it exercises the
    services directly. Role denial is the subject here, so every account gets the group
    a real deployment seeds.
    """

    def setUp(self):
        super().setUp()
        self.password = get_random_string(12)
        for user in (self.manager, self.foreman, self.cashier):
            user.set_password(self.password)
            user.save(update_fields=['password'])

        self.stocker = self._make_user('stocker1', 'Stock Manager')
        self.other_foreman = self._make_user('foreman2', 'Site Foreman')
        self._add_group(self.manager, 'Store Manager')
        self._add_group(self.foreman, 'Site Foreman')
        self._add_group(self.cashier, 'Cashier')
        self.client = APIClient()

    def _add_group(self, user, name):
        group, _ = Group.objects.get_or_create(name=name)
        user.groups.add(group)

    def _make_user(self, username, group_name):
        user = User.objects.create_user(
            username=username, email=f'{username}@x.com', password=self.password)
        self._add_group(user, group_name)
        return user

    def _login(self, username):
        """Point the client at `username`; returns the authenticated client."""
        response = self.client.post('/api/v1/auth/login/', {
            'username': username, 'password': self.password}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        token = response.data.get('access') or response.data.get('token')
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')
        return self.client

    def _approved_token(self, requisition=None):
        requisition = requisition or self.requisition
        submit_requisition(requisition=requisition)
        return approve_requisition(requisition=requisition, approver=self.manager)

    def _other_foreman_requisition(self):
        return Requisition.objects.create(
            project=self.project, requested_by=self.other_foreman,
            req_number='REQ-OTHER-0001')

    def _approve_other_foreman_requisition(self):
        """A SECOND foreman's requisition, submitted and approved by the manager."""
        other = self._other_foreman_requisition()
        submit_requisition(requisition=other)
        approve_requisition(requisition=other, approver=self.manager)
        return other


class RequisitionReadScopeTests(_SecurityBase):
    """Only a manager/admin reads every requisition; a Site Foreman reads their own."""

    def test_cashier_cannot_list_requisitions(self):
        self._login('cashier1')
        response = self.client.get(LIST_URL)
        self.assertEqual(response.status_code, 403, response.data)

    def test_stocker_cannot_list_requisitions(self):
        self._login('stocker1')
        response = self.client.get(LIST_URL)
        self.assertEqual(response.status_code, 403, response.data)

    def test_groupless_user_cannot_list_requisitions(self):
        groupless = User.objects.create_user(
            username='norole1', email='n@x.com', password=self.password)
        self.assertFalse(groupless.groups.exists())
        self._login('norole1')
        response = self.client.get(LIST_URL)
        self.assertEqual(response.status_code, 403, response.data)

    def test_cashier_cannot_list_tokens(self):
        self._approved_token()
        self._login('cashier1')
        response = self.client.get(TOKENS_URL)
        self.assertEqual(response.status_code, 403, response.data)

    def test_stocker_cannot_list_tokens(self):
        self._approved_token()
        self._login('stocker1')
        response = self.client.get(TOKENS_URL)
        self.assertEqual(response.status_code, 403, response.data)

    def test_manager_can_list_tokens(self):
        token = self._approved_token()
        self._login('manager1')
        response = self.client.get(TOKENS_URL)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            [row['token'] for row in response.data['results']],
            [str(token.token)])

    def test_cashier_cannot_read_requisition_detail(self):
        self._login('cashier1')
        response = self.client.get(f'{LIST_URL}{self.requisition.pk}/')
        self.assertEqual(response.status_code, 403, response.data)

    def test_foreman_sees_only_own_requisition_and_its_token(self):
        token = self._approved_token()
        # A token for the OTHER foreman's requisition must not leak in the same list.
        self._approve_other_foreman_requisition()
        self._login('foreman1')
        response = self.client.get(LIST_URL)
        self.assertEqual(response.status_code, 200, response.data)
        rows = response.data['results']
        self.assertEqual([row['id'] for row in rows], [self.requisition.pk])
        self.assertEqual(rows[0]['token'], str(token.token))

    def test_foreman_cannot_read_another_foremans_requisition(self):
        other = self._other_foreman_requisition()
        self._login('foreman1')
        response = self.client.get(f'{LIST_URL}{other.pk}/')
        self.assertEqual(response.status_code, 404, response.data)

    def test_manager_sees_every_requisition_with_its_token(self):
        token = self._approved_token()
        other = self._approve_other_foreman_requisition()
        other_token = MaterialToken.objects.get(requisition=other)
        self._login('manager1')
        response = self.client.get(LIST_URL)
        self.assertEqual(response.status_code, 200, response.data)
        by_id = {row['id']: row for row in response.data['results']}
        self.assertEqual(set(by_id), {self.requisition.pk, other.pk})
        self.assertEqual(by_id[self.requisition.pk]['token'], str(token.token))
        self.assertEqual(by_id[other.pk]['token'], str(other_token.token))

    def test_serializer_token_is_null_without_a_request(self):
        """The key must stay PRESENT: the Flutter Requisition model reads a nullable 'token'."""
        self._approved_token()
        self.requisition.refresh_from_db()
        data = dict(RequisitionSerializer(self.requisition).data)
        self.assertIn('token', data)
        self.assertIsNone(data['token'])


class RequisitionItemScopeTests(_SecurityBase):
    """Line items follow the read rule of their parent requisition."""

    def test_cashier_cannot_list_requisition_items(self):
        self._login('cashier1')
        response = self.client.get(ITEMS_URL)
        self.assertEqual(response.status_code, 403, response.data)

    def test_foreman_lists_only_items_of_own_requisitions(self):
        other = self._other_foreman_requisition()
        RequisitionItem.objects.create(
            requisition=other, variant=self.variant, quantity=1)
        self._login('foreman1')
        response = self.client.get(ITEMS_URL)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            [row['id'] for row in response.data['results']], [self.req_item.pk])

    def test_manager_lists_items_of_every_requisition(self):
        other = self._other_foreman_requisition()
        other_item = RequisitionItem.objects.create(
            requisition=other, variant=self.variant, quantity=1)
        self._login('manager1')
        response = self.client.get(ITEMS_URL)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            {row['id'] for row in response.data['results']},
            {self.req_item.pk, other_item.pk})


class TokenVerifyPermissionTests(_SecurityBase):
    """Verifying a handed-over token is POS work; it must not be open to everyone."""

    def test_cashier_can_verify_a_valid_token(self):
        token = self._approved_token()
        self._login('cashier1')
        response = self.client.post(
            VERIFY_URL, {'token': str(token.token)}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            response.data['requisition']['req_number'],
            self.requisition.req_number)

    def test_stocker_cannot_verify_a_token(self):
        token = self._approved_token()
        self._login('stocker1')
        response = self.client.post(
            VERIFY_URL, {'token': str(token.token)}, format='json')
        self.assertEqual(response.status_code, 403, response.data)


class SelfApprovalTests(_SecurityBase):
    """Decision 04 / NFR: the approver must not be the requester. Superuser included."""

    def setUp(self):
        super().setUp()
        self.dual_role = self._make_user('dual1', 'Site Foreman')
        self._add_group(self.dual_role, 'Store Manager')
        self.requisition.requested_by = self.dual_role
        self.requisition.save(update_fields=['requested_by'])
        submit_requisition(requisition=self.requisition)

    def test_multi_role_requester_cannot_approve_own_requisition(self):
        self._login('dual1')
        response = self.client.post(f'{LIST_URL}{self.requisition.pk}/approve/')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['code'], 'SELF_APPROVAL')
        self.assertIn('detail', response.data)
        # Refused before any write: still SUBMITTED, no token, nobody named approver.
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.status, Requisition.Status.SUBMITTED)
        self.assertIsNone(self.requisition.approved_by)
        self.assertFalse(
            MaterialToken.objects.filter(requisition=self.requisition).exists())

    def test_superuser_requester_cannot_approve_own_requisition(self):
        superuser = User.objects.create_superuser(
            username='root1', email='root@x.com', password=self.password)
        self.requisition.requested_by = superuser
        self.requisition.save(update_fields=['requested_by'])
        self._login('root1')
        response = self.client.post(f'{LIST_URL}{self.requisition.pk}/approve/')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['code'], 'SELF_APPROVAL')
        self.assertFalse(
            MaterialToken.objects.filter(requisition=self.requisition).exists())

    def test_requester_may_still_reject_own_requisition(self):
        """P2 Ruling: only APPROVE is separation of duties; reject stays allowed."""
        self._login('dual1')
        response = self.client.post(f'{LIST_URL}{self.requisition.pk}/reject/')

        self.assertEqual(response.status_code, 200, response.data)
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.status, Requisition.Status.REJECTED)

    def test_manager_approves_someone_elses_requisition(self):
        self.requisition.requested_by = self.foreman
        self.requisition.save(update_fields=['requested_by'])
        self._login('manager1')
        response = self.client.post(f'{LIST_URL}{self.requisition.pk}/approve/')

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            response.data['token'],
            str(MaterialToken.objects.get(requisition=self.requisition).token))


class RequisitionLockAfterSubmitTests(_SecurityBase):
    """P2 Ruling (R): a requisition and its lines are immutable once out of DRAFT."""

    def setUp(self):
        super().setUp()
        submit_requisition(requisition=self.requisition)

    def test_cannot_patch_a_submitted_requisition(self):
        self.requisition.notes = 'original'
        self.requisition.save(update_fields=['notes'])
        self._login('manager1')
        response = self.client.patch(
            f'{LIST_URL}{self.requisition.pk}/', {'notes': 'edited'}, format='json')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['code'], 'REQUISITION_LOCKED')
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.notes, 'original')

    def test_cannot_delete_a_submitted_requisition(self):
        self._login('manager1')
        response = self.client.delete(f'{LIST_URL}{self.requisition.pk}/')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['code'], 'REQUISITION_LOCKED')
        self.assertTrue(Requisition.objects.filter(pk=self.requisition.pk).exists())

    def test_cannot_add_a_line_to_a_submitted_requisition(self):
        self._login('foreman1')
        response = self.client.post(ITEMS_URL, {
            'requisition': self.requisition.pk,
            'variant': self.variant.pk,
            'quantity': '5.00',
        }, format='json')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['code'], 'REQUISITION_LOCKED')
        self.assertEqual(self.requisition.items.count(), 1)
        self.req_item.refresh_from_db()
        self.assertEqual(self.req_item.quantity, 10)

    def test_cannot_patch_a_line_of_an_approved_requisition(self):
        approve_requisition(requisition=self.requisition, approver=self.manager)
        self._login('foreman1')
        response = self.client.patch(
            f'{ITEMS_URL}{self.req_item.pk}/', {'quantity': '99.00'}, format='json')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['code'], 'REQUISITION_LOCKED')
        self.req_item.refresh_from_db()
        self.assertEqual(self.req_item.quantity, 10)

    def test_cannot_delete_a_line_of_an_approved_requisition(self):
        approve_requisition(requisition=self.requisition, approver=self.manager)
        self._login('foreman1')
        response = self.client.delete(f'{ITEMS_URL}{self.req_item.pk}/')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['code'], 'REQUISITION_LOCKED')
        self.assertTrue(RequisitionItem.objects.filter(pk=self.req_item.pk).exists())

    def test_draft_requisition_and_lines_stay_editable(self):
        draft = Requisition.objects.create(
            project=self.project, requested_by=self.foreman,
            req_number='REQ-DRAFT-0001')
        item = RequisitionItem.objects.create(
            requisition=draft, variant=self.variant, quantity=2)
        self._login('foreman1')

        patched = self.client.patch(
            f'{LIST_URL}{draft.pk}/', {'notes': 'draft note'}, format='json')
        self.assertEqual(patched.status_code, 200, patched.data)

        item_patched = self.client.patch(
            f'{ITEMS_URL}{item.pk}/', {'quantity': '4.00'}, format='json')
        self.assertEqual(item_patched.status_code, 200, item_patched.data)
        item.refresh_from_db()
        self.assertEqual(item.quantity, 4)

        deleted = self.client.delete(f'{ITEMS_URL}{item.pk}/')
        self.assertEqual(deleted.status_code, 204, getattr(deleted, 'data', None))

    def test_foreman_can_still_create_a_requisition(self):
        self._login('foreman1')
        response = self.client.post(LIST_URL, {
            'project': self.project.pk,
            'notes': 'new request',
        }, format='json')

        self.assertEqual(response.status_code, 201, response.data)
        created = Requisition.objects.get(pk=response.data['id'])
        self.assertEqual(created.status, Requisition.Status.DRAFT)
        self.assertEqual(created.requested_by, self.foreman)


class RequisitionStatusIsActionOnlyTests(_SecurityBase):
    """`status` moves only through submit/approve/reject (review F2).

    `RequisitionSerializer.read_only_fields` listed `approved_by` but not `status`, so a
    plain `PATCH /requisitions/{id}/ {"status": "APPROVED"}` walked a DRAFT straight to
    APPROVED/RELEASED around the approval action: no separation-of-duties check, no
    `MaterialToken` minted, no `REQ_APPROVE` audit row, and an approval that can never
    happen afterwards (there is nothing left in SUBMITTED to approve). The field is now
    read-only, so the value in the payload is ignored rather than trusted: the response
    and the database both still say DRAFT.
    """

    def _assert_untouched_draft(self, requisition, response):
        self.assertEqual(response.data['status'], Requisition.Status.DRAFT, response.data)
        requisition.refresh_from_db()
        self.assertEqual(requisition.status, Requisition.Status.DRAFT)
        self.assertFalse(
            MaterialToken.objects.filter(requisition=requisition).exists(),
            'a PATCH must not mint the material token an approval would mint')
        self.assertFalse(
            AuditLog.objects.filter(
                action_type=AuditLog.ActionType.REQ_APPROVE).exists(),
            'a PATCH must not write the approval audit row')

    def test_a_foreman_cannot_walk_their_own_draft_to_approved(self):
        self._login('foreman1')

        response = self.client.patch(
            f'{LIST_URL}{self.requisition.pk}/', {'status': 'APPROVED'},
            format='json')

        self.assertIn(response.status_code, (200, 400), response.data)
        self._assert_untouched_draft(self.requisition, response)

    def test_a_manager_cannot_walk_a_draft_to_released_by_patching_status(self):
        self._login('manager1')

        response = self.client.patch(
            f'{LIST_URL}{self.requisition.pk}/', {'status': 'RELEASED'},
            format='json')

        self.assertIn(response.status_code, (200, 400), response.data)
        self._assert_untouched_draft(self.requisition, response)


class RequisitionItemParentOwnershipTests(_SecurityBase):
    """`/req-items/` writes resolve the TARGET parent through the read scope (F5).

    `RequisitionItemViewSet.create` resolved the parent with an unscoped
    `Requisition.objects.filter(pk=...)`, so a Site Foreman could file a line onto
    another foreman's requisition — a write into a row they cannot even read (the read
    side answers 404). The move branch of `update` had the same hole. The parent is now
    looked up through the same scope `RequisitionViewSet.get_queryset` uses, so the
    answer is 404 and nothing is written.
    """

    def _own_requisition_with_item(self, requester):
        requisition = Requisition.objects.create(
            project=self.project, requested_by=requester,
            req_number=f'REQ-OWN-{requester.pk}')
        item = RequisitionItem.objects.create(
            requisition=requisition, variant=self.variant, quantity=2)
        return requisition, item

    def test_a_foreman_cannot_add_a_line_to_another_foremans_draft(self):
        lines = self.requisition.items.count()
        self._login('foreman2')

        response = self.client.post(ITEMS_URL, {
            'requisition': self.requisition.pk,
            'variant': self.variant.pk,
            'quantity': '5.00',
        }, format='json')

        self.assertEqual(response.status_code, 404, response.data)
        self.assertEqual(self.requisition.items.count(), lines)

    def test_a_foreman_cannot_move_own_line_into_another_foremans_draft(self):
        own_requisition, own_item = self._own_requisition_with_item(self.other_foreman)
        self._login('foreman2')

        response = self.client.patch(
            f'{ITEMS_URL}{own_item.pk}/', {'requisition': self.requisition.pk},
            format='json')

        self.assertEqual(response.status_code, 404, response.data)
        own_item.refresh_from_db()
        self.assertEqual(own_item.requisition_id, own_requisition.pk)
        self.assertEqual(self.requisition.items.count(), 1)

    def test_a_foreman_can_still_add_a_line_to_their_own_draft(self):
        self._login('foreman1')

        response = self.client.post(ITEMS_URL, {
            'requisition': self.requisition.pk,
            'variant': self.variant.pk,
            'quantity': '5.00',
        }, format='json')

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(self.requisition.items.count(), 2)
