# ClaudeCostBar

A macOS menu-bar app that tracks your **Claude Code** spend. Collapsed, it shows today's
total cost next to a Claude mark. Click it for a 30-day history chart, per-day / per-model /
per-token breakdown, and configurable spend alerts.

It reads your local Claude Code transcripts directly — no network, no external dependencies.

## What it shows

- **Menu bar (collapsed):** `✳ $12.34` — today's total cost.
- **Popover (click):**
  - Today's total, 30-day total, current-month total.
  - 30-day daily cost bar chart (today highlighted).
  - Expandable per-day rows → per-model token counts and cost.
  - Alert settings (daily / monthly USD limits) and a link to edit pricing.

## How it works

1. Scans `~/.claude/projects/**/*.jsonl` for assistant messages with `message.usage`.
2. **Deduplicates by `message.id`** — Claude Code copies transcript lines into resumed and
   compacted sessions, so the same message appears many times (observed up to 27×). Counting
   raw lines overstates cost ~2.2×; dedup is essential for accuracy.
3. Buckets each message by **local calendar day** (timestamps are UTC).
4. Normalizes model IDs to a family (`opus` / `sonnet` / `haiku`), handling
   `bedrock/us.anthropic.…` and version suffixes. `<synthetic>` messages cost $0.
5. Computes cost from a **user-editable pricing table** (per-million tokens), including
   cache-read and 5-minute / 1-hour cache-write tiers.
6. Scanning is **incremental**: a per-file byte cursor means only newly appended bytes are
   read on each refresh (every 60s), so 1000+ transcripts aren't re-parsed each tick.

History is persisted, so it survives transcript pruning. State lives in
`~/Library/Application Support/ClaudeCostBar/`.

## Build & run

Requires the Swift toolchain (Command Line Tools or Xcode). No Xcode project needed.

```bash
# Dev run (shows a Dock icon while running from terminal):
swift run

# Build a proper menu-bar .app (no Dock icon):
./scripts/build_app.sh
open dist/ClaudeCostBar.app

# Install:
cp -R dist/ClaudeCostBar.app /Applications/
```

Quit from the popover's power button, or `pkill -f ClaudeCostBar`.

### Start at login (optional)

```bash
cp -R dist/ClaudeCostBar.app /Applications/
cp scripts/com.claudecostbar.app.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.claudecostbar.app.plist
```

## Pricing

Default list prices are seeded into
`~/Library/Application Support/ClaudeCostBar/pricing.json` on first run. They follow
Anthropic's standard ratios (cache read ≈ 0.1× input, 5m write ≈ 1.25× input, 1h write ≈ 2×
input) but **verify them against your own contract / Bedrock rates** — edit the file and click
**Reload pricing** in the popover. You can add exact model keys (e.g. `"claude-opus-4-8"`)
alongside the family keys for precise overrides.

```json
{
  "models": {
    "opus":   { "input": 15.0, "output": 75.0, "cacheRead": 1.50, "cacheWrite5m": 18.75, "cacheWrite1h": 30.0 },
    "sonnet": { "input": 3.0,  "output": 15.0, "cacheRead": 0.30, "cacheWrite5m": 3.75,  "cacheWrite1h": 6.0 },
    "haiku":  { "input": 1.0,  "output": 5.0,  "cacheRead": 0.10, "cacheWrite5m": 1.25,  "cacheWrite1h": 2.0 }
  },
  "fallback": { "input": 15.0, "output": 75.0, "cacheRead": 1.50, "cacheWrite5m": 18.75, "cacheWrite1h": 30.0 }
}
```

## Alerts

Set a daily and/or monthly USD limit in the popover (gear icon). When spend crosses a limit
you get a native notification — at most once per day (daily) or per month (monthly). Grant
notification permission when macOS prompts on first launch.

## Tests

```bash
swift test
```

Covers dedup, cost math across all token tiers, model normalization (incl. Bedrock),
aggregation, day bucketing, pruning, and alert threshold logic.

## Project layout

```
Sources/ClaudeCostBar/
  App.swift              MenuBarExtra entry, accessory-mode AppDelegate
  Models.swift           TokenUsage, UsageRecord, DailyAggregate, AlertSettings
  Pricing.swift          ModelPrice/PricingTable, cost math, model normalization
  ScanState.swift        Persisted cursors + seen-ids (dedup), pruning
  TranscriptScanner.swift Incremental JSONL reader + per-line parse/dedup
  DayBucket.swift        ISO-8601 → local-day bucketing
  Aggregator.swift       Pure fold of records → daily aggregates
  Persistence.swift      Application Support snapshot + pricing loading
  UsageStore.swift       ObservableObject: scan → aggregate → persist → alert
  AlertManager.swift     Pure threshold decision + notification dispatch
  Formatting.swift       USD / token / day-label helpers
  ClaudeMark.swift       Drawn Claude-style glyph (replace with official asset if desired)
  Views/                 PopoverView, DayRow, HistoryChart
Resources/pricing.json   Bundled default pricing
scripts/                 build_app.sh, LaunchAgent template
Tests/                   Unit tests
```

## Notes & limitations

- **Pricing is your responsibility to verify** — list prices drift and Bedrock/Vertex rates
  differ. The table is editable for exactly this reason.
- The Claude mark is a drawn stand-in, not the official logo. Swap in your own asset if you
  have the rights.
- First launch does a full scan of all transcripts (a few seconds for ~1000 files); subsequent
  refreshes are incremental and near-instant.
