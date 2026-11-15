# pyright: reportAttributeAccessIssue=false
# Workspace stubs miss Django managers and type DRF APIClient responses as WSGIRequest.
"""Cashier lookup is restricted to accepted/open requests; release keeps token guards."""

from django.contrib.auth.models import Group

from .models import Requisition
from .tests_release_shift import ReleaseShiftBase

QUEUE = "/api/v1/requisitions/release-queue/"


class ReleaseLookupTests(ReleaseShiftBase):
    def setUp(self):
        super().setUp()
        self.token = self._mint_token()

    def get(self, path):
        return self.client.get(path, HTTP_AUTHORIZATION=self.bearer)

    def verify_request(self):
        return self.client.post(
            f"/api/v1/requisitions/{self.requisition.pk}/verify-release/",
            {},
            format="json",
            HTTP_AUTHORIZATION=self.bearer,
        )

    def test_cashier_queue_lists_only_accepted_and_partial_without_tokens(self):
        for value in Requisition.Status.values:
            if value == Requisition.Status.ACCEPTED:
                continue
            Requisition.objects.create(
                project=self.project, req_number=f"LOOKUP-{value}", status=value
            )
        response = self.get(QUEUE)
        self.assertEqual(response.status_code, 200)
        rows = response.data["results"]
        self.assertEqual({r["status"] for r in rows}, {"ACCEPTED", "PARTIAL"})
        self.assertTrue(all(row["token"] is None for row in rows))

    def test_selection_verifies_without_releasing_then_existing_release_works(self):
        before = self._stock()
        response = self.verify_request()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["token"], str(self.token.token))
        self.assertEqual(response.data["requisition"]["id"], self.requisition.pk)
        self.assertEqual(self._stock(), before)
        release = self._release(self.token)
        self.assertEqual(release.status_code, 201, release.data)
        receipt = self.get(f"/api/v1/transactions/{release.data['transaction_id']}/")
        self.assertEqual(receipt.status_code, 200, receipt.data)
        self.assertTrue(receipt.data["receipt"]["or_number"])
        self.assertEqual(len(receipt.data["items"]), 1)
        self.assertEqual(receipt.data["items"][0]["product_name"], "Portland Cement")
        self.assertEqual(receipt.data["items"][0]["variant_name"], "40kg")
        self.assertNotEqual(self._release(self.token).status_code, 201)
        self.assertNotEqual(self.verify_request().status_code, 200)

    def test_stale_selection_rechecks_manager_decision(self):
        self.requisition.status = Requisition.Status.WAITING
        self.requisition.save(update_fields=["status"])
        response = self.verify_request()
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["code"], "REQUISITION_WAITING")

    def test_missing_token_is_clear_refusal(self):
        self.token.delete()
        response = self.verify_request()
        self.assertEqual(response.status_code, 400)

    def test_cashier_still_cannot_browse_manager_queue_or_approve(self):
        self.assertEqual(self.get("/api/v1/requisitions/").status_code, 403)
        response = self.client.post(
            f"/api/v1/requisitions/{self.requisition.pk}/accept/",
            {},
            format="json",
            HTTP_AUTHORIZATION=self.bearer,
        )
        self.assertEqual(response.status_code, 403)

    def test_stock_manager_cannot_lookup_or_verify_requests(self):
        self.cashier.groups.clear()
        self.cashier.groups.add(Group.objects.get_or_create(name="Stock Manager")[0])
        self.assertEqual(self.get(QUEUE).status_code, 403)
        self.assertEqual(self.verify_request().status_code, 403)
