# pyright: reportAttributeAccessIssue=false
"""Failed-login counter — the lockout's storage, and nothing else.

Why the cache and not a table: a failed sign-in is not a durable business event. The
count is *supposed* to evaporate, and the durable record of the attempt is the
``LOGIN_FAILED`` audit row written by the view. A table would need a cleanup job; the
cache expires the window on its own.

The window is fixed at the **first** failure of a burst, not slid forward by every
retry: a sliding window lets an attacker who keeps trying never serve the lockout, and
a fixed one means the wait a locked-out user is told is a real deadline. So the entry
stores both the count and the first failure's timestamp, and every rewrite recomputes
the timeout from that timestamp.

The default ``LocMem`` cache is per-process: two dev workers have two counters. That is
fine for dev, and the settings file says what production needs instead.
"""

import math

from django.core.cache import cache
from django.utils import timezone

# Five failures, then 15 minutes of not being allowed to try at all.
MAX_FAILURES = 5
WINDOW_SECONDS = 15 * 60


def attempt_key(identifier, address):
    """The counter's name: one bucket per (identifier, client address) pair.

    Case-folding the identifier is deliberate — ``Admin`` and ``admin`` are the same
    account, so they must be the same bucket, or the limit is multiplied by the number
    of spellings of the username.
    """
    return f'login-fail:{(identifier or "").strip().lower()}:{address or ""}'


def _remaining_seconds(entry):
    """Seconds left in ``entry``'s window (0 when the window is over)."""
    deadline = entry['first'] + WINDOW_SECONDS
    return max(0, int(math.ceil(deadline - timezone.now().timestamp())))


def failure_count(key):
    entry = cache.get(key)
    if entry is None or _remaining_seconds(entry) == 0:
        return 0
    return entry['count']


def is_locked(key):
    """True once the pair has used up its attempts inside the window."""
    return failure_count(key) >= MAX_FAILURES


def retry_after_seconds(key):
    """How long the caller must wait — 0 when it is not locked out."""
    entry = cache.get(key)
    if entry is None:
        return 0
    return _remaining_seconds(entry)


def record_failure(key):
    """Count one failure and return the new total.

    A read-modify-write, so two simultaneous failures can be counted as one. Acceptable:
    the limit is a brake on guessing, not a ledger, and the honest failure that this
    under-counts is the one attempt a real user does not retry. The audit row is written
    per attempt regardless.
    """
    now = timezone.now().timestamp()
    entry = cache.get(key)
    if entry is None or _remaining_seconds(entry) == 0:
        entry = {'count': 1, 'first': now}
    else:
        entry = {'count': entry['count'] + 1, 'first': entry['first']}
    cache.set(key, entry, timeout=max(1, _remaining_seconds(entry)))
    return entry['count']


def reset(key):
    """Forget the failures — called on a successful sign-in."""
    cache.delete(key)
