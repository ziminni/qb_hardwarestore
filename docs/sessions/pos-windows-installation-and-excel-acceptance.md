# Windows installation and Excel acceptance

## Delivery

Feature commit `32167b3` is included in freshly fetched `origin/master` through merge `7ddc999` (PR #23). This follow-up changes documentation only, on `docs/windows-installation-and-qa-close` based on that master. The owner selected another PR, not a direct push to master.

## Owner-reported Windows result

The owner ran the Windows-side installation/run instructions and reported:

- Exported catalogue to `.xlsx`, edited Faucet price from **225 to 1,000** in Excel, and imported successfully.
- Exported the updated catalogue and imported it again successfully.
- Confirmed stock quantity **did not change**.

This closes the previously unverified native Windows/Excel round-trip smoke-test gap. It is a user-reported result, not an independently observed controller run. No screenshot, Excel version, build hash or Windows command transcript was supplied; do not invent those details. Separate cancel-dialog behavior and exhaustive multi-role Windows testing were not reported.

The earlier [feature handoff](2026-11-14-pos-excel-and-merged-sidebar-handoff.md) remains historical evidence; its Windows picker/Excel verification gap is superseded by this result. Existing browser acceptance, populated-stock hash check, automated tests and independent reviews remain recorded there and in the phase plans.

## Installation documentation

`README.md` now owns a Windows-first setup/update guide checked against the current Compose file, Django settings, seed command and Flutter API configuration. It covers toolchain requirements, stopping the backend before pulling bind-mounted code, backing up the existing database before automatic migrations, Docker startup/health checks, fresh-demo seeding and credentials, native Flutter launch, Excel smoke testing, safe shutdown and troubleshooting. Backups are kept outside the repository; no flush or volume deletion is part of normal updates.

The supplied Compose stack is development/demo infrastructure, not a hardened production deployment. Current backend defaults include debug mode, known credentials and permissive hosts; the README warns against internet exposure.

## Remaining limits

- LibreOffice edit/resave was not separately tested; the owner tested Microsoft Excel on Windows instead.
- The 2,000-row writer/parser measurement was in Flutter test VM, not Windows/browser/backend end-to-end timing.
- Physical printing/scanning, all desktop workflows and production hardening are not certified by this smoke test.
- Phase 1c CPMS payment-receipt approval remains on hold.
- Formal phase-owner closure remains distinct from this specific QA result; this docs pass does not fabricate broader sign-off.

No source behavior, schema, credentials or database content changed in this documentation follow-up. No application/test suite or Windows installation was rerun by the controller for these documentation edits.
