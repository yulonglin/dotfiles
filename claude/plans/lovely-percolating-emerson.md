# Rename Calendar → Meet

## Context
The cal.com link is a meeting booking link, not a calendar view. "Calendar" is misleading — "Meet" is concise, action-oriented, and matches the `/meet` URL path. Footer stays text-only per design decision (icons in nav, typography in footer).

## Changes

### `src/config.ts`
- Change `name: 'Calendar'` → `name: 'Meet'` (line 27)

No other files need changes — Nav reads `link.name` for `aria-label` and Footer renders `link.name` as text. Both will pick up the rename automatically.

## Verification
- `bun dev` → check nav tooltip shows "Meet" on hover
- Check footer shows "Meet" instead of "Calendar"
