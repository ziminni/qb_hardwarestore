"""Bodega refusals (decision 25).

Subclasses of `CatalogWriteRefused`, so `apps.pos.exceptions.handler` publishes them as
the project's `{code, detail}` **400** without a new branch. Every one is raised BEFORE
the first write, so a 400 here also means "nothing changed".
"""

from apps.inventory.exceptions import CatalogWriteRefused


class BodegaRefused(CatalogWriteRefused):
    code = "BODEGA_REFUSED"


class NoBodegaClaim(BodegaRefused):
    """The receipt names no sale, or a sale that took nothing from a Bodega shelf."""

    code = "NO_BODEGA_CLAIM"


class ReleaseExceedsClaim(BodegaRefused):
    """More would leave the Bodega than the customer paid for and has not collected."""

    code = "RELEASE_EXCEEDS_CLAIM"


class InvalidBodegaRelease(BodegaRefused):
    code = "INVALID_BODEGA_RELEASE"


class InvalidBodegaDelivery(BodegaRefused):
    code = "INVALID_BODEGA_DELIVERY"
