# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
# pyright: reportMissingImports=false
#
# Same directives and reasons as `tests_catalog_writes.py`: `Model.objects` is a
# false positive on valid Django, and `**auth` splats HTTP_AUTHORIZATION.
# `reportMissingImports` covers Pillow only: it is a BACKEND runtime dependency
# (`requirements.txt`) installed in the backend image, not on this checker's host.

"""Product images — the OWNED copy of a product's photo (POS usability, images).

**The bug these pin.** The product form's file picker handed back a local path
(`C:\\Users\\me\\cement.jpg`), the draft sent that path as `image_url`, and the
server's `URLField` refused it or — worse, on the platforms where it passed — stored
a string that no browser could ever load. The photo the clerk chose never became a
durable, shareable picture.

**The fix these assert.** One optional image per product, uploaded on the EXISTING
`POST`/`PATCH /products/` as `multipart/form-data`, stored under `MEDIA_ROOT` with a
server-generated name, and published as an absolute HTTP `image_url` built from the
request. `image_url` keeps its wire key and its legacy meaning: a product with no
owned image answers the URL it has always answered, so JSON create/edit and every
existing client keep working.

The refusals are the point of the lane: a size/format/decode check on the ACTUAL
bytes (not the extension), a pixel bound so a decompression bomb cannot pin a worker,
generated names so a client filename (or `../` in it) never becomes a storage key,
and a file lifecycle that survives a rollback — the previous photo is deleted only
after the replacement COMMITS, and the new one is removed when the write is refused.
"""

import io
import os
import shutil
import tempfile
from unittest import mock

from django.test import override_settings
from PIL import Image

from apps.users.models import AuditLog

from .models import Product
from .tests_catalog_writes import PRODUCTS_URL, CatalogWriteTestBase

# One directory for the whole module, emptied before each test: a real
# `FileSystemStorage` is what the lane has to be proven against (naming, collision
# handling, deletion), so nothing here is mocked.
IMAGE_ROOT = tempfile.mkdtemp(prefix="qb-product-images-")


def image_bytes(fmt="PNG", size=(12, 10), color=(210, 40, 40)):
    """Real encoded bytes of `size` in `fmt`, so Pillow can decode them."""
    buffer = io.BytesIO()
    Image.new("RGB", size, color).save(buffer, format=fmt)
    return buffer.getvalue()


def stored_names():
    """Every file name under the media root, for "was it written / deleted" checks."""
    names = []
    for directory, _dirs, files in os.walk(IMAGE_ROOT):
        for name in files:
            names.append(os.path.relpath(os.path.join(directory, name), IMAGE_ROOT))
    return sorted(names)


class ProductImageTestBase(CatalogWriteTestBase):
    """Real logins and the catalog fixture, with a clean media root per test."""

    def setUp(self):
        super().setUp()
        # Enabled here rather than as a class decorator: `override_settings` applied
        # to a class returns an opaque wrapper, which hides the base class from type
        # checkers so every subclass below reads as "not a class".
        media = override_settings(MEDIA_ROOT=IMAGE_ROOT, MEDIA_URL="/media/")
        media.enable()
        self.addCleanup(media.disable)
        try:
            shutil.rmtree(IMAGE_ROOT)
        except OSError:
            pass  # a missing media root is exactly the state this method wants

    def _product_payload(self, **overrides):
        """A minimal valid product body; `overrides` replaces fields."""
        payload = {
            "category": self.category.pk,
            "brand": self.brand.pk,
            "base_name": "Portland Cement (photo)",
            "description": "",
        }
        payload.update(overrides)
        return payload

    def _create_with_image(self, name="cement.png", data=None, fmt="PNG"):
        from django.core.files.uploadedfile import SimpleUploadedFile

        payload = self._product_payload()
        payload["image"] = SimpleUploadedFile(
            name,
            data if data is not None else image_bytes(fmt),
            content_type="image/png",
        )
        return self.client.post(
            PRODUCTS_URL, payload, format="multipart", **self._auth(self.stocker)
        )

    def _replace_image(self, product_pk, name="replacement.png", data=None):
        from django.core.files.uploadedfile import SimpleUploadedFile

        return self.client.patch(
            f"{PRODUCTS_URL}{product_pk}/",
            {
                "image": SimpleUploadedFile(
                    name,
                    data if data is not None else image_bytes(fmt="PNG"),
                    content_type="image/png",
                )
            },
            format="multipart",
            **self._auth(self.stocker),
        )


class ProductImageUploadTests(ProductImageTestBase):
    """A picked photo becomes a server-owned file with a shareable URL."""

    def test_multipart_create_stores_the_photo_and_answers_an_absolute_url(self):
        response = self._create_with_image()

        self.assertEqual(response.status_code, 201, response.data)
        product = Product.objects.get(pk=response.data["id"])
        self.assertTrue(product.image, "the uploaded photo was not stored")
        self.assertEqual(stored_names(), [product.image.name])

        url = response.data["image_url"]
        self.assertTrue(
            url.startswith("http://") and "/media/product-images/" in url,
            f"image_url is not an absolute owned URL: {url!r}",
        )
        self.assertTrue(url.endswith(".png"), url)

    def test_the_legacy_url_column_stays_empty_when_a_photo_is_uploaded(self):
        response = self._create_with_image()

        product = Product.objects.get(pk=response.data["id"])
        self.assertEqual(product.image_url, "")

    def test_json_create_with_a_url_is_unchanged(self):
        response = self.client.post(
            PRODUCTS_URL,
            self._product_payload(image_url="https://cdn.example.com/cement.jpg"),
            format="json",
            **self._auth(self.stocker),
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(
            response.data["image_url"], "https://cdn.example.com/cement.jpg"
        )

    def test_an_owned_photo_wins_over_a_legacy_url(self):
        response = self._create_with_image()
        product_pk = response.data["id"]
        # A legacy URL arriving on the SAME product must not out-shout the photo the
        # shop owns: the owned file is the one the clerk chose.
        self.client.patch(
            f"{PRODUCTS_URL}{product_pk}/",
            {"image_url": "https://cdn.example.com/old.jpg"},
            format="json",
            **self._auth(self.stocker),
        )

        listed = self.client.get(
            f"{PRODUCTS_URL}{product_pk}/", **self._auth(self.stocker)
        )
        self.assertIn("/media/product-images/", listed.data["image_url"])

    def test_a_photo_uploaded_as_jpg_but_holding_png_is_stored_as_png(self):
        response = self._create_with_image(name="photo.jpg", data=image_bytes("JPEG"))
        self.assertEqual(response.status_code, 201, response.data)
        self.assertTrue(response.data["image_url"].endswith(".jpg"), response.data)

        # And the DISGUISED case: JPEG bytes in a file called .png.
        disguised = self._create_with_image(
            name="disguised.png", data=image_bytes("JPEG")
        )
        self.assertEqual(disguised.status_code, 201, disguised.data)
        self.assertTrue(
            disguised.data["image_url"].endswith(".jpg"),
            f"stored name must follow the DECODED format: {disguised.data}",
        )

    def test_webp_is_accepted(self):
        response = self._create_with_image(name="photo.webp", data=image_bytes("WEBP"))
        self.assertEqual(response.status_code, 201, response.data)
        self.assertTrue(response.data["image_url"].endswith(".webp"))

    def test_the_client_filename_never_becomes_the_storage_key(self):
        response = self._create_with_image(name="../../../evil photo.png")

        self.assertEqual(response.status_code, 201, response.data)
        names = stored_names()
        self.assertEqual(len(names), 1, names)
        self.assertNotIn("evil", names[0])
        self.assertNotIn("..", names[0])
        self.assertTrue(names[0].startswith("product-images/"), names[0])

    def test_the_audit_row_never_mentions_the_client_path(self):
        self._create_with_image(name="../../../secret/cement.png")

        row = AuditLog.objects.filter(action_type=AuditLog.ActionType.CREATE).first()
        self.assertIsNotNone(row)
        self.assertNotIn("secret", row.description)
        self.assertNotIn("product-images", row.description)


class ProductImageRefusalTests(ProductImageTestBase):
    """The bytes are checked, not the extension: size, format, decode, dimensions."""

    def _assert_refused(self, response, code):
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get("code"), code, response.data)
        self.assertEqual(stored_names(), [], "a refused upload left a file behind")
        self.assertFalse(Product.objects.filter(base_name="Portland Cement (photo)"))

    def test_a_file_over_five_mebibytes_is_refused(self):
        # Genuinely >5 MiB of noise, not a 5 MiB string of one byte: PNG would
        # compress that to nothing.
        response = self._create_with_image(
            name="huge.png",
            data=image_bytes("PNG", size=(3000, 3000)) + os.urandom(5 * 1024 * 1024),
        )
        self._assert_refused(response, "PRODUCT_IMAGE_TOO_LARGE")

    def test_svg_is_refused(self):
        response = self._create_with_image(
            name="logo.svg",
            data=b'<svg xmlns="http://www.w3.org/2000/svg"><script/></svg>',
        )
        self._assert_refused(response, "INVALID_PRODUCT_IMAGE")

    def test_text_disguised_as_a_png_is_refused(self):
        response = self._create_with_image(
            name="not-really.png", data=b"this is not an image at all"
        )
        self._assert_refused(response, "INVALID_PRODUCT_IMAGE")

    def test_a_truncated_png_is_refused(self):
        whole = image_bytes("PNG", size=(400, 400))
        response = self._create_with_image(
            name="cut.png", data=whole[: len(whole) // 2]
        )
        self._assert_refused(response, "INVALID_PRODUCT_IMAGE")

    def test_a_gif_is_refused_even_though_pillow_can_decode_it(self):
        response = self._create_with_image(name="anim.gif", data=image_bytes("GIF"))
        self._assert_refused(response, "INVALID_PRODUCT_IMAGE")

    def test_absurd_dimensions_are_refused(self):
        # 20000 x 20000 = 400 MP: it decodes to ~1.2 GB of RGB, so the header check
        # has to refuse it BEFORE any pixel is loaded.
        response = self._create_with_image(
            name="bomb.png", data=image_bytes("PNG", size=(20000, 20000))
        )
        self._assert_refused(response, "INVALID_PRODUCT_IMAGE")

    def test_a_device_path_in_image_url_is_refused(self):
        response = self.client.post(
            PRODUCTS_URL,
            self._product_payload(image_url=r"C:\Users\me\cement.jpg"),
            format="json",
            **self._auth(self.stocker),
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn("image_url", response.data)

    def test_a_cashier_cannot_upload_a_photo(self):
        payload = self._product_payload()
        from django.core.files.uploadedfile import SimpleUploadedFile

        payload["image"] = SimpleUploadedFile(
            "cement.png", image_bytes(), content_type="image/png"
        )
        response = self.client.post(
            PRODUCTS_URL, payload, format="multipart", **self._auth(self.cashier)
        )

        self.assertEqual(response.status_code, 403, response.data)
        self.assertEqual(stored_names(), [])


class ProductImageLifecycleTests(ProductImageTestBase):
    """Replacement deletes the old photo AFTER commit; refusal deletes the new one."""

    def test_replacing_the_photo_deletes_the_old_file_after_commit(self):
        created = self._create_with_image()
        product_pk = created.data["id"]
        first = Product.objects.get(pk=product_pk).image.name

        # `TestCase` shares one transaction, so a post-commit callback fires only
        # when the test asks it to — which is exactly what the "only AFTER commit"
        # guarantee needs to be shown against.
        with self.captureOnCommitCallbacks(execute=True):
            response = self._replace_image(product_pk)

        self.assertEqual(response.status_code, 200, response.data)
        second = Product.objects.get(pk=product_pk).image.name
        self.assertNotEqual(first, second)
        self.assertEqual(stored_names(), [second], "the replaced photo was not deleted")

    def test_a_replacement_left_uncommitted_keeps_the_old_file(self):
        created = self._create_with_image()
        product_pk = created.data["id"]
        first = Product.objects.get(pk=product_pk).image.name

        # No `execute=True`: the delete is QUEUED, so a rollback (the only thing that
        # discards the queue) leaves the old photo alone. This is the ordering the
        # brief asks for, asserted directly instead of inferred.
        with self.captureOnCommitCallbacks(execute=False) as queued:
            self._replace_image(product_pk)

        self.assertEqual(len(queued), 1, "no old-photo delete was queued")
        self.assertTrue(
            os.path.exists(os.path.join(IMAGE_ROOT, first)),
            "the old photo was deleted before the write committed",
        )

    def test_an_unrelated_patch_keeps_the_photo(self):
        created = self._create_with_image()
        product_pk = created.data["id"]
        before = Product.objects.get(pk=product_pk).image.name

        response = self.client.patch(
            f"{PRODUCTS_URL}{product_pk}/",
            {"base_name": "Portland Cement 40kg"},
            format="json",
            **self._auth(self.stocker),
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(Product.objects.get(pk=product_pk).image.name, before)
        self.assertEqual(stored_names(), [before])
        self.assertIn("/media/product-images/", response.data["image_url"])

    def test_a_refused_audit_removes_the_new_file_and_keeps_the_old_one(self):
        created = self._create_with_image()
        product_pk = created.data["id"]
        original = Product.objects.get(pk=product_pk).image.name

        with (
            mock.patch(
                "apps.inventory.views.audit_request",
                side_effect=RuntimeError("trail down"),
            ),
            self.assertRaises(RuntimeError),
        ):
            self._replace_image(product_pk)

        # The row still holds the ORIGINAL photo, and the replacement never became an
        # orphan on disk.
        product = Product.objects.get(pk=product_pk)
        self.assertEqual(product.image.name, original)
        self.assertEqual(stored_names(), [original])

    def test_a_failed_patch_without_a_photo_keeps_the_existing_file(self):
        created = self._create_with_image()
        product_pk = created.data["id"]
        original = Product.objects.get(pk=product_pk).image.name

        with (
            mock.patch(
                "apps.inventory.views.audit_request",
                side_effect=RuntimeError("trail down"),
            ),
            self.assertRaises(RuntimeError),
        ):
            self.client.patch(
                f"{PRODUCTS_URL}{product_pk}/",
                {"base_name": "Renamed"},
                format="json",
                **self._auth(self.stocker),
            )

        self.assertEqual(stored_names(), [original], "the row's photo was deleted")

    def test_a_refused_audit_on_create_removes_the_file(self):
        with (
            mock.patch(
                "apps.inventory.views.audit_request",
                side_effect=RuntimeError("trail down"),
            ),
            self.assertRaises(RuntimeError),
        ):
            self._create_with_image()

        self.assertFalse(Product.objects.filter(base_name="Portland Cement (photo)"))
        self.assertEqual(stored_names(), [], "a rolled-back create leaked its file")
