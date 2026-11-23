# Large-range pagination vs export limits

**Locked (by: me, 2026-11-23):**
- **On screen:** DRF pagination, 50 rows per page (`PAGE_SIZE`), with total count. Same pattern as existing list endpoints (`paginate_queryset` / `get_paginated_response`).
- **PDF export:** full filtered result up to 5,000 rows; when exceeded, print first 5,000 and show "Showing first 5,000 of N — narrow the date range."
- **Excel export:** full filtered result up to 10,000 rows in one response; when exceeded, export first 10,000 with a `Notice` sheet explaining the cap.
- Existing `requisition-history` 200-row silent cap is replaced by this rule when it joins the catalogue.

## Why
A busy month can exceed thousands of bills; unbounded responses risk timeouts on the store PC, while a 200-row cap silently drops data. Paging + stated caps keeps both honest without a background-job queue.
