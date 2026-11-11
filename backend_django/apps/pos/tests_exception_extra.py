# pyright: reportMissingImports=false
#
# Same directive and reason as apps/pos/tests_cheque.py: the checker runs from a working
# directory outside the repo, so it resolves no config and `django.test` reads as missing.
# The test run in the container remains the authority.

"""The `extra` figures a refusal carries must not be shared between refusals.

Both `DiscountError` and `ChequeError` default `extra` at class level. A mutable `{}`
there is one dict shared by every subclass and every instance, so one refusal's figures
would show up in the next one's HTTP body. These tests pin the default as immutable and
check that the per-instance overrides are correct and isolated. No database: exception
payloads are plain in-memory objects.
"""

from collections.abc import Mapping
from types import MappingProxyType

from django.test import SimpleTestCase

from apps.pos.exceptions import (
    ChequeDetailsRequired,
    ChequeError,
    ChequeReasonRequired,
    DiscountError,
    DiscountOverCap,
    DiscountReasonRequired,
    InvalidDiscount,
)


class ExtraDefaultIsImmutableTests(SimpleTestCase):
    def test_bases_default_to_an_immutable_empty_mapping(self):
        for base in (DiscountError, ChequeError):
            with self.subTest(base=base.__name__):
                self.assertIsInstance(base.extra, Mapping)
                self.assertEqual(dict(base.extra), {})
                # `MappingProxyType` IS the immutability guarantee: a proxy view cannot
                # be written through, so no refusal can inherit another's figures.
                self.assertIsInstance(base.extra, MappingProxyType)

    def test_subclasses_do_not_leak_figures_into_each_other(self):
        capped = DiscountOverCap(cap_percent=10, requested_percent=25)

        self.assertEqual(
            dict(capped.extra),
            {'cap_percent': '10.00', 'requested_percent': '25.00'},
        )
        # The base default and a sibling are untouched by the instance's dict.
        self.assertEqual(dict(InvalidDiscount.extra), {})
        self.assertEqual(dict(DiscountReasonRequired.extra), {})


class ChequeExtraTests(SimpleTestCase):
    def test_missing_details_are_carried_in_extra(self):
        exc = ChequeDetailsRequired(['number', 'bank'])

        self.assertEqual(exc.extra['missing'], ['number', 'bank'])
        self.assertEqual(
            str(exc), 'A cheque needs its number and bank. Fill it in and try again.')

    def test_a_reasonless_bounce_carries_no_figures(self):
        self.assertEqual(dict(ChequeReasonRequired().extra), {})


class HandlerPublishesExtraTests(SimpleTestCase):
    """The handler must still merge `extra` into the `{code, detail}` body."""

    def test_over_cap_refusal_publishes_its_figures(self):
        from apps.pos.exceptions import handler

        exc = DiscountOverCap(cap_percent=10, requested_percent=25)
        response = handler(exc, {'request': None})

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['code'], 'DISCOUNT_OVER_CAP')
        self.assertEqual(response.data['cap_percent'], '10.00')
        self.assertEqual(response.data['requested_percent'], '25.00')

    def test_cheque_refusal_keeps_its_own_status_and_figures(self):
        from apps.pos.exceptions import handler

        exc = ChequeDetailsRequired(['number'])
        response = handler(exc, {'request': None})

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['code'], 'CHEQUE_DETAILS_REQUIRED')
        self.assertEqual(response.data['missing'], ['number'])
