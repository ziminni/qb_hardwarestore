# QA Profile — <project name>

Copy to `docs/testing/QA-PROFILE.md` in each project and fill it in. qa-tester reads this first.

## How to run
- Backend: `<command>` → `<url:port>`
- Frontend: `<command>` → `<url / device>`
- Test DB / settings: `<how to point at a test database, never the dev DB>`

## Test accounts (seeded, non-production)
| Role | Username | How it's seeded |
| :--- | :--- | :--- |
| <admin> | <...> | `<seed command>` |

## API conventions
- Auth: <token/header>
- Pagination envelope: <e.g. {count, next, previous, results}>
- Error shape: <...>

## Domain rules worth probing
- <e.g. stock deducts FIFO by batch; cannot go negative>
- <e.g. collectible balance = sum(charges) − sum(payments)>

## Out of bounds
- <things QA must never do, e.g. call the real payment provider>
