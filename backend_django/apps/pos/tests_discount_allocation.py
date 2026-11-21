from unittest import TestCase

from .discount_allocation import allocate_discounts


class DiscountAllocationTests(TestCase):
    def test_cart_discount_uses_eligible_balances_after_item_discounts(self):
        # Cement excluded from cart discount; tools have a separate item discount.
        self.assertEqual(
            allocate_discounts(
                [(60_000, 0, False), (30_000, 10_000, True), (10_000, 0, True)], 3_000
            ),
            [0, 2_000, 1_000],
        )

    def test_largest_remainders_get_leftover_centavos_with_stable_ties(self):
        self.assertEqual(allocate_discounts([(1, 0, True)] * 4, 2), [1, 1, 0, 0])
        self.assertEqual(allocate_discounts([(1, 0, True), (2, 0, True)], 1), [0, 1])

    def test_zero_eligible_balance_accepts_zero_cart_discount(self):
        self.assertEqual(allocate_discounts([(3, 3, True), (4, 0, False)], 0), [0, 0])

    def test_positive_cart_discount_rejected_when_no_eligible_balance(self):
        with self.assertRaisesRegex(ValueError, "eligible"):
            allocate_discounts([(3, 3, True), (4, 0, False)], 1)

    def test_item_discount_cannot_exceed_own_line_or_be_negative(self):
        for item_discount in (-1, 6):
            with (
                self.subTest(item_discount=item_discount),
                self.assertRaisesRegex(ValueError, "Item discount"),
            ):
                allocate_discounts([(5, item_discount, True), (9, 0, True)], 0)

    def test_cart_discount_cannot_exceed_eligible_balance_or_be_negative(self):
        for cart_discount in (-1, 6):
            with (
                self.subTest(cart_discount=cart_discount),
                self.assertRaisesRegex(ValueError, "Cart discount"),
            ):
                allocate_discounts([(5, 0, True), (9, 0, False)], cart_discount)

    def test_full_cart_discount_uses_every_eligible_centavo(self):
        self.assertEqual(
            allocate_discounts([(3, 1, True), (7, 2, True), (5, 0, False)], 7),
            [2, 5, 0],
        )
