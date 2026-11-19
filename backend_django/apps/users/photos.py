"""Phone photos the server keeps: a Bodega delivery line's proof, a profile picture.

The same checks as the product photo (`apps.inventory.serializers.validate_image`),
on the BYTES: the format comes from decoding the file, never from its name, the pixel
bound is read from the header before the pixels are decoded, and the stored name is
generated, so a client filename never becomes a storage key.
"""

from uuid import uuid4

from PIL import Image, UnidentifiedImageError

from apps.inventory.exceptions import CatalogWriteRefused

PHOTO_MAX_BYTES = 5 * 1024 * 1024
PHOTO_MAX_PIXELS = 24_000_000
PHOTO_FORMATS = {"JPEG": "jpg", "PNG": "png", "WEBP": "webp"}


class InvalidPhoto(CatalogWriteRefused):
    """A photo the server cannot keep: published as the project's `{code, detail}` 400."""

    code = "INVALID_PHOTO"


def checked_photo(upload):
    """`upload`, verified as a real JPEG/PNG/WebP and renamed; or `InvalidPhoto`."""
    if upload is None:
        raise InvalidPhoto("Attach a photo.")
    if upload.size > PHOTO_MAX_BYTES:
        raise InvalidPhoto("That photo is larger than 5 MB. Take a smaller one.")
    try:
        with Image.open(upload) as probe:
            detected = probe.format
            width, height = probe.size
            if detected not in PHOTO_FORMATS:
                raise InvalidPhoto("That file is not a JPEG, PNG or WebP photo.")
            if width < 1 or height < 1:
                raise InvalidPhoto("That photo has no visible pixels.")
            if width * height > PHOTO_MAX_PIXELS:
                raise InvalidPhoto(
                    f"That photo is too large in pixels: use one under "
                    f"{PHOTO_MAX_PIXELS:,} pixels."
                )
            probe.load()
    except (UnidentifiedImageError, Image.DecompressionBombError, OSError, SyntaxError):
        raise InvalidPhoto(
            "That file could not be read as a photo. It may be damaged."
        ) from None
    upload.seek(0)
    upload.name = f"{uuid4().hex}.{PHOTO_FORMATS[detected]}"
    return upload


def photo_url(request, field):
    """The photo's absolute URL, built from the request so a phone can load it."""
    if not field:
        return ""
    url = field.url
    return request.build_absolute_uri(url) if request else url
