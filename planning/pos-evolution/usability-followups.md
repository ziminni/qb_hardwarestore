# POS usability follow-ups

Status: In Progress on `feat/pos-usability-followups`, from merged master `6d47d15`. CPMS continues independently; no push/commit or development DB mutation authorized by this work request.

## Owner scope and confirmed choices

1. **Manager accepts/declines project requests; cashier still releases accepted materials using token.** Confirmed explicitly. Cashier's existing Release materials page is not a request-creation/approval page; clarify copy, do not remove release or widen permissions.
2. **Products show real images.** Existing URL display works but selected local file paths are incorrectly sent to server URLField. Fix durable upload/display, not device-only previews.
3. **Shifts explain variance.** Server formula stays `closing_count - expected_drawer`, where expected cash includes opening float and net cash receipts/refunds. Use Cash difference with clear counted-minus-expected explanation and shortage/extra/exact text; do not change accounting or wire keys.
4. **Location filter uses actual positive stock at selected location**, not product Stored at/home. Confirmed explicitly. Reuse complete server-owned stock-on-hand rows; no new backend query necessary. All locations retains products even if out of stock. Aggregate existing totals must not be mistaken for selected-location totals.

## Lanes and file ownership

- Cashier/shift copy: material_release_page, pos_shift_page, pos_z_reading_summary, pos_shift_close_dialog, their focused tests only.
- Stock-location filter: products_viewmodel, products_toolbar, products_page, their focused tests only. Never images/form/services.
- Images: backend inventory product model/serializer/view/tests + additive migration, media config/URL/ignore/dependency; Flutter image file picker/payload, product form/image widget, product write drafts/repository/service and focused image/write tests. Never products_page/toolbar/products_viewmodel or the location-filter lane's test files. Shared InventoryViewmodel change only if genuinely needed, coordinate first.

## Image lane brief (smallest durable path)

- Keep existing `image_url` wire key and legacy URL compatibility. Add optional owned image storage; serializer emits request-origin HTTP URL for owned image, never a local device path. Existing server URL-backed product rendering remains intact.
- Use multipart image on EXISTING product POST/PATCH, not a second post-create upload request that would add another duplicate-create retry trap. JSON create/edit without image remains unchanged. Add optional bytes/name DTO to client drafts; services use multipart only when a new image was selected, keeping existing method callers/fakes compatible.
- Picker must read actual file bytes (Windows/web portable) and show memory preview; no `C:\...`/blob/device path sent as image_url. Edit must persist replacement. No separate image-delete feature required in this slice; do not erase an existing image on unrelated edit.
- One image per Product (shared by variants), JPEG/PNG/WebP, max 5 MiB, genuine decoded image validation, finite image dimensions/pixel bound and generated storage name with matching detected format. Reject SVG, disguised or malformed files. Pillow is justified for trusted format validation; no client path in storage keys/audit.
- Preserve IsInventoryRole catalog write fences (inventory/sales/admin), cashier refusal and atomic existing audit behavior. New file cleanup on write/audit failure; previous file removed only after committed replacement; never delete old photo on rollback. Test concurrent replacement/no-op metadata safety where applicable. Generated unique file names prevent cache collisions/path traversal.
- Local product photographs are deliberately public catalogue media, not private receipt/proof uploads. Serve local media only through development configuration; describe production serving responsibility, no public deployment claim. Persist under backend media directory already inside Compose bind mount; gitignore media. No development migrations or image uploads during implementation.
- Confirm contract in ENDPOINTS/README after build (controller owns shared docs); revises earlier deferred-images decision without touching its historical evidence.

## Verification

RED first, focused tests each lane, serialize Flutter commands via `/tmp/qb-pos-flutter-tests.lock`. POS backend tests use disposable `buildpro_p1d_qa_backend` and its test database, serialize via `/tmp/qb-pos-backend-tests.lock`; never normal buildpro_backend/db or concurrent POS backend test runs. One read-only reviewer per project, no suites from reviewers. Controller verifies changes before full gates. Goldens inspected/updated only for intended UI changes after builders finish. One QA across both projects, only after builders and suites finish; no heavy concurrent QA.

No implementation completed is implied by this brief. CPMS payroll statutory/debt policies remain separate and must not be invented here.
