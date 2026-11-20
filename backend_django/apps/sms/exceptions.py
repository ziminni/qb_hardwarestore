# pyright: reportMissingImports=false
"""SMS refusals, published in the project's `{code, detail}` shape.

`APIException` subclasses rather than the till's `ValueError` family: none of these
travel through `apps.pos.exceptions.handler` (they are raised on the gateway and staff
endpoints, outside the till), and DRF renders a dict `detail` verbatim, so the body is
exactly `{"code", "detail"}` without adding a branch to that handler.
"""

from rest_framework import status
from rest_framework.exceptions import APIException


class SmsError(APIException):
    status_code = status.HTTP_400_BAD_REQUEST
    code = "SMS_REFUSED"

    def __init__(self, detail, code=None):
        super().__init__({"code": code or self.code, "detail": detail})


class SmsGatewayRefused(APIException):
    """The bridge's key is missing, wrong, or the server has none configured.

    Refused with the key never echoed back, and `SMS_GATEWAY_KEY` empty or shorter than
    24 characters refuses EVERY call: a guessable key on a machine that can send paid SMS
    is worse than a bridge that does not run.
    """

    status_code = status.HTTP_403_FORBIDDEN
    code = "SMS_GATEWAY_REFUSED"

    def __init__(self, detail="The SMS gateway key is missing or not configured."):
        super().__init__({"code": self.code, "detail": detail})


class SmsGatewayUnauthorized(APIException):
    """No `X-SMS-Gateway-Key` header at all (401, not 403): nothing was presented."""

    status_code = status.HTTP_401_UNAUTHORIZED
    code = "SMS_GATEWAY_UNAUTHORIZED"

    def __init__(self, detail="Send the X-SMS-Gateway-Key header."):
        super().__init__({"code": self.code, "detail": detail})


class SmsDisabled(APIException):
    """`SMS_ENABLED` is off: refuse the message and let the bridge keep it.

    A 503 (not a 200 with a silent `PROCESSED`) is what makes the bridge leave the SMS on
    the SIM - it only deletes after a 2xx. Raising BEFORE any write also protects the
    dedupe key, so the retry after the shop switches the link on is processed for real.
    """

    status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    code = "SMS_DISABLED"

    def __init__(self, detail="The SMS link is switched off (SMS_ENABLED=false)."):
        super().__init__({"code": self.code, "detail": detail})


class SmsMessageNotFound(SmsError):
    status_code = status.HTTP_404_NOT_FOUND
    code = "SMS_MESSAGE_NOT_FOUND"


class SmsRetryRefused(SmsError):
    """Only a FAILED outbound message can be retried; anything else is already moving."""

    code = "SMS_RETRY_REFUSED"


class SmsContactInvalid(SmsError):
    """A contact whose number will not normalize, or whose account is no Bodega account."""

    code = "SMS_CONTACT_INVALID"
