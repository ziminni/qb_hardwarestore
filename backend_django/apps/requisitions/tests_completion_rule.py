"""Phase 1b Task 3 — when is a request RELEASED? (decisions 10 and 13)

`every_available_line_done` decides whether a release spends the token. It only reads the
plan `_release_plan` builds, so these tests hand it plain lines: no database, no stock.
"""

from decimal import Decimal
from types import SimpleNamespace

from django.test import SimpleTestCase

from .services import every_available_line_done


def line(*, available, remaining, releasable):
    """One planned line, in the shape `_release_plan` returns."""
    return {
        'item': SimpleNamespace(available=available),
        'remaining': Decimal(remaining),
        'releasable': Decimal(releasable),
        'archived': False,
    }


class EveryAvailableLineDoneTests(SimpleTestCase):
    def test_every_available_line_finishing_now_is_done(self):
        plan = [line(available=True, remaining='8', releasable='8'),
                line(available=True, remaining='2.5', releasable='2.5')]

        self.assertTrue(every_available_line_done(plan))

    def test_a_short_available_line_keeps_the_request_open(self):
        plan = [line(available=True, remaining='8', releasable='8'),
                line(available=True, remaining='10', releasable='4')]

        self.assertFalse(every_available_line_done(plan))

    def test_a_not_available_line_does_not_hold_the_token_open(self):
        # The store said it cannot serve the rebar: its 5 stay outstanding for ever,
        # and the cement finishing today must still make the request RELEASED.
        plan = [line(available=True, remaining='8', releasable='8'),
                line(available=False, remaining='5', releasable='0')]

        self.assertTrue(every_available_line_done(plan))

    def test_a_line_finished_on_an_earlier_visit_counts_as_done(self):
        plan = [line(available=True, remaining='0', releasable='0'),
                line(available=True, remaining='3', releasable='3')]

        self.assertTrue(every_available_line_done(plan))

    def test_nothing_leaving_an_owed_available_line_is_not_done(self):
        plan = [line(available=True, remaining='3', releasable='0'),
                line(available=False, remaining='5', releasable='0')]

        self.assertFalse(every_available_line_done(plan))

    def test_an_unanswered_line_is_still_owed(self):
        # Fail-safe: a line nobody answered must never let the token die with goods out.
        plan = [line(available=True, remaining='8', releasable='8'),
                line(available=None, remaining='4', releasable='0')]

        self.assertFalse(every_available_line_done(plan))
