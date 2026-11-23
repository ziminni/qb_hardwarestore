# Dead-stock & fast/slow mover thresholds

**Locked (by: me, 2026-11-23):**
- **Dead stock** = zero completed sales quantity in the trailing window (default 90 days, user-adjustable) AND on-hand quantity > 0. Items never stocked are excluded: nothing is tied up.
- **Fast movers** = top 20% of SKUs by completed sales quantity over the chosen report range.
- **Slow movers** = sold at least once in the range but in the bottom 20% by completed sales quantity.
- Quantity measured in base units across all selling units; value at landed cost for the money-tied-up column.

## Report behavior
- Dead stock uses its own trailing window control (default 90 days), independent of the report's from/to range.
- Fast/slow split uses the report's chosen from/to range and applies per the percentile above.
- Dead & slow lists show days-since-last-sale, current on-hand, and landed-cost value so the manager sees the peso amount sitting idle.
