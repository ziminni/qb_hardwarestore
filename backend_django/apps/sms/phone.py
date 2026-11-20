"""Phone numbers as one shape: `+639XXXXXXXXX`.

The checker types his number any way he likes (`0917 123 4567`, `+63 917-123-4567`,
`639171234567`); everything stored and compared goes through `normalize_phone`, so a
contact registered one way still matches the caller ID the modem reports another way.
"""

import re

#: Philippine mobile numbers are 10 national digits and all start with 9.
_PHONE_PATTERN = re.compile(r"^9\d{9}$")


class InvalidPhoneNumber(ValueError):
    """A number that is not a Philippine mobile number."""

    def __init__(self, raw):
        super().__init__(
            f"{raw!r} is not a mobile number. Send 11 digits starting 09 "
            "(09171234567) or the +63 form (+639171234567)."
        )


def normalize_phone(raw):
    """`09171234567`, `9171234567`, `+63 917 123 4567`, `63-917-123-4567` -> `+639171234567`."""
    digits = re.sub(r"\D", "", raw or "")
    if digits.startswith("63"):
        digits = digits[2:]
    elif digits.startswith("0"):
        digits = digits[1:]
    if not _PHONE_PATTERN.match(digits):
        raise InvalidPhoneNumber(raw)
    return f"+63{digits}"
