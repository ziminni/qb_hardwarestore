# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directive and reason as apps/pos/tests.py: the checker resolves its config from
# its WORKING DIRECTORY, so every `self.client.post(..., **self.auth)` is a false
# positive on valid Django. The test run is the authority.
"""Browser CORS preflight for the two idempotent checkout endpoints.

A browser will not send `POST /api/v1/transactions/` until a preflight
(`OPTIONS` + `Access-Control-Request-Headers`) says every header the client sets is
allowed. `django-cors-headers` answers with `CORS_ALLOW_HEADERS`, whose DEFAULT set
covers `authorization` and `content-type` but knows nothing about `Idempotency-Key`.

Live QA on the web build ("Cannot connect to the BuildPro server"): the preflight was
answered without `idempotency-key`, the browser blocked the POST, and the cashier could
not ring a sale — on web only, because a desktop/mobile Dio client is not subject to
CORS and never asks.

These tests are the only place that can see this: every other checkout test talks to
the view directly, below the CORS layer.
"""

from django.test import TestCase

# What the Flutter web client actually asks for, in the order Dio sends it.
BROWSER_ORIGIN = 'http://localhost:8090'
IDEMPOTENCY_HEADERS = 'authorization,content-type,idempotency-key'


class IdempotencyKeyPreflightTests(TestCase):
    """`Idempotency-Key` must survive the browser's preflight."""

    def _preflight(self, path):
        return self.client.options(
            path,
            HTTP_ORIGIN=BROWSER_ORIGIN,
            HTTP_ACCESS_CONTROL_REQUEST_METHOD='POST',
            HTTP_ACCESS_CONTROL_REQUEST_HEADERS=IDEMPOTENCY_HEADERS,
        )

    def _allowed_headers(self, response):
        return response.headers.get('access-control-allow-headers', '').lower()

    def test_checkout_preflight_allows_idempotency_key(self):
        """POST /transactions/ — the sale itself."""
        response = self._preflight('/api/v1/transactions/')

        self.assertEqual(response.status_code, 200)
        allowed = self._allowed_headers(response)
        self.assertIn(
            'idempotency-key',
            allowed,
            msg=(
                'the browser will block the checkout POST when its preflight '
                f'does not allow the header; got {allowed!r}'
            ),
        )
        # The defaults must not be lost while adding ours.
        self.assertIn('authorization', allowed)
        self.assertIn('content-type', allowed)

    def test_held_cart_complete_preflight_allows_idempotency_key(self):
        """POST /held-carts/{id}/complete/ — the same contract, same header."""
        response = self._preflight('/api/v1/held-carts/1/complete/')

        self.assertEqual(response.status_code, 200)
        allowed = self._allowed_headers(response)
        self.assertIn('idempotency-key', allowed, msg=f'got {allowed!r}')

    def test_preflight_also_answers_the_web_origin(self):
        """The origin the web dev server runs on is echoed back, not just headers."""
        response = self._preflight('/api/v1/transactions/')

        self.assertIn(
            response.headers.get('access-control-allow-origin'),
            (BROWSER_ORIGIN, '*'),
        )
