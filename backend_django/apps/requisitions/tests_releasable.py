"""Phase 1 Task 5: the per-line quantity rule for a short-stock release (decision 05)."""

from decimal import Decimal as D

from django.test import SimpleTestCase

from .services import releasable_qty


def rq(remaining, available_base, factor='1', unit='PC'):
    return releasable_qty(remaining=D(remaining), available_base=D(available_base),
                          conversion_factor=D(factor), unit_code=unit)


class ReleasableQtyTests(SimpleTestCase):
    def test_enough_stock_releases_the_whole_outstanding_amount(self):
        self.assertEqual(rq('5', '100'), D('5.00'))

    def test_never_more_than_is_outstanding(self):
        self.assertEqual(rq('2', '2'), D('2.00'))

    def test_short_whole_units_release_what_is_on_the_shelf(self):
        self.assertEqual(rq('10', '4'), D('4.00'))

    def test_boxes_round_down_to_whole_boxes(self):
        # 30 pieces on hand is 2.5 boxes of 12: only 2 full boxes can go.
        self.assertEqual(rq('3', '30', factor='12', unit='BOX'), D('2.00'))

    def test_less_than_one_box_on_hand_releases_nothing(self):
        self.assertEqual(rq('3', '11', factor='12', unit='BOX'), D('0.00'))

    def test_unit_code_is_matched_regardless_of_case_and_spaces(self):
        self.assertEqual(rq('3', '30', factor='12', unit=' box '), D('2.00'))

    def test_measured_units_release_fractions(self):
        self.assertEqual(rq('5', '2.75', unit='KG'), D('2.75'))

    def test_measured_units_round_down_to_two_places(self):
        # 10 base metres in 3-metre lengths is 3.333..: 3.33 goes, never 3.34.
        self.assertEqual(rq('5', '10', factor='3', unit='LENGTH'), D('3.33'))

    def test_no_stock_releases_nothing(self):
        self.assertEqual(rq('5', '0'), D('0.00'))
        self.assertEqual(rq('5', '0', unit='KG'), D('0.00'))

    def test_answers_with_two_decimal_places(self):
        self.assertEqual(rq('5', '100').as_tuple().exponent, -2)

    def test_negative_stock_releases_nothing(self):
        self.assertEqual(rq('5', '-3'), D('0.00'))
