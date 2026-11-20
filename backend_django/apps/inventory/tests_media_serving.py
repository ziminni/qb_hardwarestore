"""Uploaded photos stay reachable with DEBUG off (production), and nothing else in
MEDIA_ROOT does. Django's test runner already runs with DEBUG=False."""

import tempfile
from pathlib import Path
from typing import cast

from django.http import FileResponse
from django.test import SimpleTestCase, override_settings


class ProductionMediaTests(SimpleTestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        for folder in ("product-images", "avatars", "bodega-deliveries", "stray"):
            (root / folder).mkdir()
            (root / folder / "a.png").write_bytes(b"\x89PNG fake")
        override = override_settings(MEDIA_ROOT=root)
        override.enable()
        self.addCleanup(override.disable)

    def _get(self, url) -> FileResponse:
        # The stubs type the test client's return as a request; it is a response.
        return cast(FileResponse, self.client.get(url))

    def test_the_three_photo_folders_are_served(self):
        for folder in ("product-images", "avatars", "bodega-deliveries"):
            response = self._get(f"/media/{folder}/a.png")
            self.assertEqual(response.status_code, 200, folder)
            self.assertEqual(response.getvalue(), b"\x89PNG fake")

    def test_anything_else_under_media_is_not(self):
        self.assertEqual(self._get("/media/stray/a.png").status_code, 404)
        self.assertEqual(self._get("/media/backups/manifest.json").status_code, 404)
        self.assertEqual(
            self._get("/media/product-images/../stray/a.png").status_code, 404
        )
