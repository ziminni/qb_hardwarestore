"""Phase 1 Task 5 + Phase 1d Task 2: the per-line quantity rule for a short-stock release.

Decision 16 moved the whole-vs-fractional answer onto the unit row itself, so this module
takes the FLAG the `VariantUOM` carries (`is_whole`) instead of matching a code against a
hard-coded list. The release still rounds DOWN: a whole unit never sells a fraction, and a
measured unit gives 2 decimal places.
"""

from decimal import Decimal as D

from django.test import SimpleTestCase

from .services import releasable_qty


def rq(remaining, available_base, factor='1', whole=True):
    return releasable_qty(remaining=D(remaining), available_base=D(available_base),
                          conversion_factor=D(factor), is_whole=whole)


class ReleasableQtyTests(SimpleTestCase):
    def test_enough_stock_releases_the_whole_outstanding_amount(self):
        self.assertEqual(rq('5', '100'), D('5.00'))

    def test_never_more_than_is_outstanding(self):
        self.assertEqual(rq('2', '2'), D('2.00'))

    def test_short_whole_units_release_what_is_on_the_shelf(self):
        self.assertEqual(rq('10', '4'), D('4.00'))

    def test_whole_units_round_down_to_whole_counts(self):
        # 30 base units is 2.5 of a 12-unit box: only 2 full boxes can go.
        self.assertEqual(rq('3', '30', factor='12'), D('2.00'))

    def test_less_than_one_whole_unit_on_hand_releases_nothing(self):
        # 11 base units is 0.91 of a 12-unit box: no whole box can go.
        self.assertEqual(rq('3', '11', factor='12'), D('0.00'))

    def test_the_flag_decides_not_the_unit_code(self):
        # Decision 16: the same numbers, one answer each way. A flag is what the server
        # reads now - the client's code list is gone - so this pins the branch itself.
        self.assertEqual(rq('5', '2.75', whole=True), D('2.00'))
        self.assertEqual(rq('5', '2.75', whole=False), D('2.75'))

    def test_measured_units_round_down_to_two_places(self):
        # 10 base units in 3-unit lengths is 3.333..: 3.33 goes, never 3.34.
        self.assertEqual(rq('5', '10', factor='3', whole=False), D('3.33'))

    def test_no_stock_releases_nothing(self):
        self.assertEqual(rq('5', '0'), D('0.00'))
        self.assertEqual(rq('5', '0', whole=False), D('0.00'))

    def test_answers_with_two_decimal_places(self):
        self.assertEqual(rq('5', '100').as_tuple().exponent, -2)

    def test_negative_stock_releases_nothing(self):
        self.assertEqual(rq('5', '-3'), D('0.00'))
