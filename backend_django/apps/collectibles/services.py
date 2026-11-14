"""Business logic for the collectibles (accounts receivable) module.

Posting a payment must MOVE THE LEDGER. Until 2026-10-17 it did not: the viewset
saved the `CollectiblePayment` and left `balance_due` and `status` untouched, so
every consumer of a receivable - the aging report, the till's utang panel, the
sales receivables screen - reported a balance that ignored every payment ever
made. A customer who had paid in full still read as owing the full amount.

The two tests that appeared to cover this did the arithmetic THEMSELVES
(`tests.py`, old `test_payment_records_against_ledger` and
`test_full_payment_pays_ledger` each assigned `balance_due` by hand after
creating the payment). They therefore passed against the broken code and could
not have caught it: they asserted that the test could subtract.
"""

from decimal import Decimal

from .models import CollectibleLedger


class Overpayment(Exception):
    """A payment larger than the balance still owed.

    Refused rather than accepted-and-clamped: silently keeping the difference
    would either invent a credit the books do not hold or swallow money the
    customer handed over, and neither is recoverable after the fact.
    """

    code = 'PAYMENT_EXCEEDS_BALANCE'

    def __init__(self, balance_due, amount):
        self.balance_due = balance_due
        self.amount = amount
        super().__init__(
            f'That payment of {amount:.2f} is more than the {balance_due:.2f} '
            f'still owed on this account.'
        )


def apply_payment_to_ledger(ledger, amount_paid):
    """Move one ledger by one payment, and return it.

    The CALLER owns the transaction: this must not be wrapped here, or a payment
    could be committed without the balance moving (or the reverse). It also must
    not be called without the ledger locked, which is why the viewset takes
    `select_for_update` before calling it - two terminals paying the last few
    pesos at the same moment would otherwise both see the old balance and one
    payment would vanish.
    """
    amount = Decimal(amount_paid)
    if amount > ledger.balance_due:
        raise Overpayment(ledger.balance_due, amount)

    ledger.balance_due = ledger.balance_due - amount
    ledger.status = (
        CollectibleLedger.Status.PAID
        if ledger.balance_due == 0
        else CollectibleLedger.Status.PARTIAL
    )
    ledger.save(update_fields=['balance_due', 'status', 'updated_at'])
    return ledger
