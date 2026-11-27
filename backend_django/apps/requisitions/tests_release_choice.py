# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false
"""The cashier chooses how much each line gives (2026-11-27 design).

`POST /tokens/release/` takes an optional `quantities` list. A listed line gives
exactly that amount (0 up to what can go out now); a line left out gives its full
releasable, so an old till that sends no list behaves as before. Whatever is not
given stays open on the same token.
"""

from decimal import Decimal

from apps.inventory.models import UnitOfMeasure, VariantUOM
from apps.pos.models import SalesTransaction

from .models import Requisition, RequisitionItem
from .services import verify_token
from .tests_partial_release import PartialReleaseBase

RELEASE_URL = "/api/v1/tokens/release/"


class ReleaseChoiceBase(PartialReleaseBase):
    def _give(self, token, *pairs):
        return self.client.post(
            RELEASE_URL,
            {
                "token": str(token.token),
                "quantities": [{"item": item.pk, "qty": qty} for item, qty in pairs],
            },
            format="json",
            HTTP_AUTHORIZATION=self.bearer,
        )


class GiveLessTests(ReleaseChoiceBase):
    def test_giving_less_than_the_shelf_leaves_the_rest_open(self):
        token = self._mint_token()

        response = self._give(token, (self.req_item, "4"))

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["status"], "PARTIAL")
        line = response.data["items"][0]
        self.assertEqual((line["released_now"], line["outstanding"]), ("4.00", "6.00"))
        self.assertEqual(Decimal(response.data["grand_total"]), Decimal(40))
        self.assertEqual(self._stock(), Decimal(96))
        token.refresh_from_db()
        self.assertFalse(token.is_used)

    def test_a_second_visit_with_the_rest_finishes_it(self):
        token = self._mint_token()
        self._give(token, (self.req_item, "4"))

        response = self._release(token)

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["status"], "RELEASED")
        token.refresh_from_db()
        self.assertTrue(token.is_used)


class RefusalTests(ReleaseChoiceBase):
    def test_more_than_releasable_is_refused_and_writes_nothing(self):
        self._leave_on_shelf(4)
        token = self._mint_token()

        response = self._give(token, (self.req_item, "5"))

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "RELEASE_QTY_TOO_HIGH")
        self.assertIn("4", response.data["detail"])
        self.assertEqual(SalesTransaction.objects.count(), 0)
        self.assertEqual(self._stock(), Decimal(4))

    def test_zero_everywhere_is_nothing_to_release(self):
        token = self._mint_token()

        response = self._give(token, (self.req_item, "0"))

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "NOTHING_TO_RELEASE")
        self.assertTrue(response.data["detail"].startswith("Nothing was chosen to release"))
        self.assertEqual(SalesTransaction.objects.count(), 0)

    def test_fraction_on_a_bag_is_refused(self):
        token = self._mint_token()

        response = self._give(token, (self.req_item, "1.5"))

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "WHOLE_UNIT_QUANTITY")
        self.assertEqual(SalesTransaction.objects.count(), 0)

    def test_unknown_or_repeated_line_is_refused(self):
        other_req = Requisition.objects.create(
            project=self.project, req_number="REQ-TEST-0002",
            status=Requisition.Status.ACCEPTED, requester_name="R", approver_name="A",
        )
        foreign = RequisitionItem.objects.create(
            requisition=other_req, variant_uom=self.vuom, quantity=Decimal(1)
        )
        token = self._mint_token()

        foreign_answer = self._give(token, (foreign, "1"))
        twice = self._give(token, (self.req_item, "1"), (self.req_item, "2"))

        self.assertEqual(foreign_answer.status_code, 400, foreign_answer.data)
        self.assertEqual(foreign_answer.data["code"], "UNKNOWN_RELEASE_LINE")
        self.assertEqual(twice.status_code, 400, twice.data)
        self.assertEqual(twice.data["code"], "UNKNOWN_RELEASE_LINE")
        self.assertEqual(SalesTransaction.objects.count(), 0)


class SharedShelfChoiceTests(ReleaseChoiceBase):
    def setUp(self):
        super().setUp()
        self._leave_on_shelf(12)
        self.second_item = RequisitionItem.objects.create(
            requisition=self.requisition, variant_uom=self.vuom, quantity=Decimal(5)
        )

    def test_lowering_the_first_shared_line_frees_stock_for_the_second(self):
        token = self._mint_token()

        response = self._give(token, (self.req_item, "7"))

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(
            [(l["released_now"], l["outstanding"]) for l in response.data["items"]],
            [("7.00", "3.00"), ("5.00", "0.00")],
        )
        self.assertEqual(response.data["status"], "PARTIAL")
        self.assertEqual(self._stock(), Decimal(0))


class MeasuredLineChoiceTests(ReleaseChoiceBase):
    def setUp(self):
        super().setUp()
        kg, _ = UnitOfMeasure.objects.get_or_create(
            code="KG", defaults={"name": "Kilogram", "is_whole": False}
        )
        self.kilo = VariantUOM.objects.create(
            variant=self.variant, uom=kg, conversion_factor=Decimal("0.025"),
            measure_per_base=Decimal("40"), default_selling_price=Decimal("7.50"),
        )
        self.req_item.delete()
        self.kilo_item = RequisitionItem.objects.create(
            requisition=self.requisition, variant_uom=self.kilo, quantity=Decimal("12.5")
        )

    def test_measured_line_partial_by_choice(self):
        token = self._mint_token()
        before = self._stock()

        response = self._give(token, (self.kilo_item, "2.5"))

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["status"], "PARTIAL")
        self.assertEqual(response.data["items"][0]["outstanding"], "10.00")
        self.assertEqual(before - self._stock(), Decimal("0.0625"))

    def test_three_decimals_refused(self):
        token = self._mint_token()

        response = self._give(token, (self.kilo_item, "0.125"))

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "QTY_TOO_PRECISE")


class VerifyFieldsTests(ReleaseChoiceBase):
    def test_verify_names_the_unit_price_and_status(self):
        token = self._mint_token()
        self._give(token, (self.req_item, "4"))

        answer = verify_token(token_value=str(token.token))

        self.assertEqual(answer["requisition"]["status"], "PARTIAL")
        item = answer["items"][0]
        self.assertEqual(item["unit"], "BAG")
        self.assertIs(item["is_whole"], True)
        self.assertEqual(item["unit_price"], "10.00")
        self.assertEqual(item["remaining"], "6.00")
