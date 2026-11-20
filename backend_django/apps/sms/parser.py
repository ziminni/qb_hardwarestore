# pyright: reportAttributeAccessIssue=false
"""The checker's reply, read by a person's own SMS app, so read tolerantly.

Everything this module does is guess what a human typed with a phone keyboard: quotes,
colons, dashes, lowercase, an "OK" in place of "DONE", the receiver's name tacked on the
end. It is a pure function with no database access, which is why the shapes below are
unit-tested one by one.
"""

import re
from dataclasses import dataclass

#: Accepted words for "I handed the goods over".
DONE_KEYWORDS = {"DONE", "OK", "ACCOMPLISHED", "RELEASED", "COMPLETE", "COMPLETED"}
HELP_KEYWORDS = {"HELP", "?"}
CODE_PATTERN = re.compile(r"^\d{4}$")
#: Everything that is punctuation between fields rather than part of one. Dashes are
#: NOT here: a transaction number (`TRX-20261120-0001`) is one token.
_SEPARATORS = re.compile(r"[:;,\"'()\[\]]+")
#: What a receipt reference may look like after cleaning. Anything else is not a number.
_REFERENCE_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9\-_/]*$")

KIND_DONE = "done"
KIND_HELP = "help"
KIND_INVALID = "invalid"

MAX_REFERENCE_LENGTH = 50
MAX_NAME_LENGTH = 150


@dataclass(frozen=True)
class Command:
    """What one inbound SMS asked for. `kind` is one of KIND_* above."""

    kind: str
    reference: str = ""
    code: str = ""
    name: str = ""


def parse_inbound(body):
    """Read one reply. Never raises: an unreadable message is `KIND_INVALID`.

    `DONE 000123 4821`, `done 000123 4821 Juan Cruz`, `'000123':'accomplished' 4821`,
    `000123:accomplished:4821`, `OK 000123 4821`, `RELEASED 000123 4821` and `HELP` all
    read as expected; so does a receipt number with dashes (`DONE TRX-20261120-0001 4821`).
    """
    tokens = _tokens(body)
    if not tokens:
        return Command(kind=KIND_INVALID)
    if len(tokens) == 1 and tokens[0].upper() in HELP_KEYWORDS:
        return Command(kind=KIND_HELP)

    reference_index = None
    for index, token in enumerate(tokens):
        if token.upper() in DONE_KEYWORDS:
            continue
        reference_index = index
        break
    if reference_index is None:
        # A keyword and nothing else ("DONE") is not a release: there is no receipt.
        return Command(kind=KIND_INVALID)
    reference = tokens[reference_index]
    if not _REFERENCE_PATTERN.match(reference) or len(reference) > MAX_REFERENCE_LENGTH:
        return Command(kind=KIND_INVALID)

    code = ""
    name_start = len(tokens)
    for index in range(reference_index + 1, len(tokens)):
        if CODE_PATTERN.match(tokens[index]):
            code = tokens[index]
            name_start = index + 1
            break
    if not code:
        return Command(kind=KIND_INVALID)

    name = " ".join(
        token for token in tokens[name_start:] if token.upper() not in DONE_KEYWORDS
    )
    return Command(
        kind=KIND_DONE,
        reference=reference,
        code=code,
        name=name[:MAX_NAME_LENGTH],
    )


def _tokens(body):
    """Whitespace-separated words, with quotes/colons/commas turned into gaps."""
    text = _SEPARATORS.sub(" ", (body or "").strip())
    return [token for token in text.split() if token]
