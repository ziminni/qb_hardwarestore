"""JWT authentication with the CPMS fence (Phase 1, Task 2, decision 02).

The CPMS service account exists for ONE namespace: `/api/v1/integration/cpms/`.
Putting the refusal in a permission class on every POS view would mean re-declaring it
wherever a view is added, and the day someone forgets is the day a contractor list, a
sales report or a till endpoint answers a machine account. So the fence lives in the
authentication class the whole project already uses: a route is fenced by existing.
"""

from rest_framework.exceptions import PermissionDenied
from rest_framework_simplejwt.authentication import JWTAuthentication

from .permissions import is_cpms_service_account

CPMS_NAMESPACE = '/api/v1/integration/cpms/'
CPMS_SCOPE_CODE = 'CPMS_SCOPE'

# Signing in and refreshing are credential endpoints, not POS data, and refusing them
# would lock the account out of its own credentials: a client that keeps its token on
# every request (the Flutter client's interceptor does exactly that) sends the OLD token
# along with its login. Neither path can read a POS record - login is credential-gated,
# refresh needs a valid refresh token - so the fence lets them through.
CREDENTIAL_PATHS = ('/api/v1/auth/login/', '/api/v1/auth/refresh/')


def scope_refusal(path):
    """403 CPMS_SCOPE in the project's `{code, detail}` shape.

    A dict detail, because DRF's own handler puts a dict detail in the body verbatim;
    the alternative is a branch in `apps.pos.exceptions.handler`, and this is not a
    POS business rule. `code` is the stable part the client branches on.
    """
    return PermissionDenied({
        'code': CPMS_SCOPE_CODE,
        'detail': (f'The CPMS service account may only call {CPMS_NAMESPACE} '
                   f'endpoints; {path} is outside its scope.'),
    })


class CpmsFencedJWTAuthentication(JWTAuthentication):
    """The project's JWT authentication, plus the one fence around the CPMS account.

    A member of `CPMS Service` is refused (403) everywhere outside the integration
    namespace; every other account is untouched, because this subclass only adds that
    one branch.

    Deactivation needs no branch here: SimpleJWT already answers 401 for an inactive
    account (`user_inactive`) before this check runs, and login refuses it in
    `LoginSerializer`. Anonymous callers never reach the check either, so
    `/auth/login/` and `/auth/refresh/` keep working for the account (refresh has no
    authentication classes at all).
    """

    def authenticate(self, request):
        result = super().authenticate(request)
        if (result is not None
                and is_cpms_service_account(result[0])
                and not request.path.startswith(CPMS_NAMESPACE)
                and request.path not in CREDENTIAL_PATHS):
            raise scope_refusal(request.path)
        return result
