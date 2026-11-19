# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
"""The checker's phone photos (2026-11-18): one per delivery line, and a profile picture.

A photo is the checker's proof that an item arrived (and of any damage), taken while
the delivery waits for checking. The server keeps only a real JPEG/PNG/WebP under a
name it chose, and never accepts one once the delivery's verdict is in.
"""

import io
import shutil
import tempfile

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from PIL import Image

from .models import BodegaDelivery
from .tests import BodegaTestBase, DeliveryCheckTests, _user

MEDIA = tempfile.mkdtemp(prefix="bodega-photo-tests-")


def _jpeg(name="item.jpg", colour=(200, 30, 30)):
    buffer = io.BytesIO()
    Image.new("RGB", (40, 30), colour).save(buffer, format="JPEG")
    return SimpleUploadedFile(name, buffer.getvalue(), content_type="image/jpeg")


@override_settings(MEDIA_ROOT=MEDIA)
class DeliveryLinePhotoTests(BodegaTestBase):
    _deliver = DeliveryCheckTests._deliver
    _confirm = DeliveryCheckTests._confirm

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(MEDIA, ignore_errors=True)
        super().tearDownClass()

    def setUp(self):
        super().setUp()
        self._deliver(10)
        self.delivery = BodegaDelivery.objects.get()
        self.line = self.delivery.lines.get()

    def _upload(self, photo, line=None, user=None, delivery=None):
        self.api.force_authenticate(user or self.checker)
        return self.api.post(
            f"/api/v1/bodega/deliveries/{(delivery or self.delivery).pk}/lines/"
            f"{(line or self.line).pk}/photo/",
            {"photo": photo},
            format="multipart",
        )

    def test_the_checker_attaches_a_photo_to_a_waiting_line(self):
        response = self._upload(_jpeg("../../evil.jpg"))

        self.assertEqual(response.status_code, 200, response.content)
        url = response.data["lines"][0]["photo_url"]
        self.assertTrue(url.startswith("http://testserver/media/bodega-deliveries/"))
        self.line.refresh_from_db()
        # The client's filename never becomes the storage key.
        self.assertNotIn("evil", self.line.photo.name)
        self.assertTrue(self.line.photo.name.endswith(".jpg"))

    def test_the_photo_shows_in_the_delivery_list(self):
        self._upload(_jpeg())
        listed = self.api.get("/api/v1/bodega/deliveries/?status=PENDING")

        self.assertTrue(listed.data["results"][0]["lines"][0]["photo_url"])

    def test_a_line_without_a_photo_says_so_with_an_empty_url(self):
        self.api.force_authenticate(self.checker)
        listed = self.api.get("/api/v1/bodega/deliveries/")

        self.assertEqual(listed.data["results"][0]["lines"][0]["photo_url"], "")

    def test_a_file_that_is_not_a_photo_is_refused_and_nothing_is_kept(self):
        response = self._upload(
            SimpleUploadedFile("item.jpg", b"not a picture", content_type="image/jpeg")
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["code"], "INVALID_PHOTO")
        self.line.refresh_from_db()
        self.assertFalse(self.line.photo)

    def test_no_file_is_refused(self):
        self.api.force_authenticate(self.checker)
        response = self.api.post(
            f"/api/v1/bodega/deliveries/{self.delivery.pk}/lines/{self.line.pk}/photo/",
            {},
            format="multipart",
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["code"], "INVALID_PHOTO")

    def test_a_second_photo_replaces_the_first(self):
        self._upload(_jpeg(colour=(1, 2, 3)))
        self.line.refresh_from_db()
        first = self.line.photo.name
        storage = self.line.photo.storage

        with self.captureOnCommitCallbacks(execute=True):
            self._upload(_jpeg(colour=(9, 9, 9)))

        self.line.refresh_from_db()
        self.assertNotEqual(self.line.photo.name, first)
        self.assertFalse(storage.exists(first), "the replaced file is deleted")

    def test_a_checked_delivery_takes_no_more_photos(self):
        self._confirm(self.delivery.pk, 10, 0)
        response = self._upload(_jpeg())

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["code"], "INVALID_BODEGA_DELIVERY")

    def test_the_photo_stays_with_the_line_after_the_check(self):
        self._upload(_jpeg())
        confirmed = self._confirm(self.delivery.pk, 8, 2)

        self.assertEqual(confirmed.status_code, 200, confirmed.content)
        self.assertTrue(confirmed.data["lines"][0]["photo_url"].startswith("http://"))

    def test_a_line_of_another_delivery_is_refused(self):
        self._deliver(5)
        other = BodegaDelivery.objects.exclude(pk=self.delivery.pk).get()
        response = self._upload(_jpeg(), delivery=other)

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["code"], "INVALID_BODEGA_DELIVERY")

    def test_a_cashier_cannot_attach_a_photo(self):
        response = self._upload(_jpeg(), user=_user("till3", "Cashier"))

        self.assertEqual(response.status_code, 403)


@override_settings(MEDIA_ROOT=MEDIA)
class AvatarTests(BodegaTestBase):
    def _set(self, photo):
        self.api.force_authenticate(self.checker)
        return self.api.post("/api/v1/auth/me/avatar/", {"photo": photo}, format="multipart")

    def test_the_checker_sets_a_profile_picture_and_me_shows_it(self):
        response = self._set(_jpeg())

        self.assertEqual(response.status_code, 200, response.content)
        self.assertTrue(response.data["avatar_url"].startswith("http://testserver/media/avatars/"))
        me = self.api.get("/api/v1/auth/me/")
        self.assertEqual(me.data["avatar_url"], response.data["avatar_url"])

    def test_no_picture_is_an_empty_url(self):
        self.api.force_authenticate(self.checker)

        self.assertEqual(self.api.get("/api/v1/auth/me/").data["avatar_url"], "")

    def test_delete_clears_the_picture(self):
        self._set(_jpeg())
        with self.captureOnCommitCallbacks(execute=True):
            cleared = self.api.delete("/api/v1/auth/me/avatar/")

        self.assertEqual(cleared.status_code, 200)
        self.assertEqual(cleared.data["avatar_url"], "")
        self.checker.refresh_from_db()
        self.assertFalse(self.checker.avatar)

    def test_a_file_that_is_not_a_photo_is_refused(self):
        response = self._set(
            SimpleUploadedFile("me.png", b"<html>", content_type="image/png")
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["code"], "INVALID_PHOTO")

    def test_signed_out_cannot_set_one(self):
        self.api.force_authenticate(None)
        response = self.api.post(
            "/api/v1/auth/me/avatar/", {"photo": _jpeg()}, format="multipart"
        )

        self.assertEqual(response.status_code, 401)
