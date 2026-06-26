# Claude-o-Meter

A macOS menu-bar app that tracks your [Claude Code](https://claude.ai/code) spend in real time — locally, privately, no API keys required.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange)

---

## What it does

Claude Code writes detailed usage logs to `~/.claude/projects/**/*.jsonl`. Claude-o-Meter reads those files incrementally and shows you a live cost breakdown in your menu bar.

| | |
|---|---|
| **Menu bar** | Today's cost; turns red when you exceed your daily budget |
| **3-stat header** | TODAY / MONTH / 30 DAYS at a glance |
| **History chart** | 30-day daily spend by model, or cumulative view |
| **Spend trend badge** | % up/down vs your prior 7-day average |
| **Usage tips** | Flags Opus-heavy sessions, low cache hit rate, spend spikes |
| **Budget alerts** | macOS notifications when you cross a daily or monthly limit |
| **Editable pricing** | JSON file — supports enterprise/EDP discounts and custom rates |
| **100% local** | Nothing leaves your machine |

---

## Install

1. Download `ClaudeOMeter-<version>.zip` from [Releases](https://github.com/Deklin/claude-o-meter/releases)
2. Unzip and drag `ClaudeOMeter.app` to `/Applications`
3. Launch it — the `$` icon appears in your menu bar

### Gatekeeper — "app can't be opened"

The app is ad-hoc signed (not notarized). macOS may block first launch:

**Option A** — right-click the app → **Open** → confirm  
**Option B** — System Settings → Privacy & Security → **Open Anyway**  
**Option C** (terminal) — `xattr -d com.apple.quarantine /Applications/ClaudeOMeter.app`

---

## Build from source

Requires macOS 14+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/Deklin/claude-o-meter.git
cd claude-o-meter

# Build distributable .app (no Dock icon, ad-hoc signed)
./scripts/build_app.sh
open dist/ClaudeOMeter.app

# Dev run (Dock icon visible — useful for iteration)
swift run

# Run tests
swift test
```

---

## Pricing

Default rates are Anthropic API list prices (USD / 1M tokens). On first launch, Claude-o-Meter writes an editable copy to:

```
~/Library/Application Support/ClaudeOMeter/pricing.json
```

Edit that file and click **Settings → Reload pricing** to apply changes without restarting.

### Current defaults

| Family | Input | Output | Cache Read | Cache Write (5m) | Cache Write (1h) |
|--------|------:|------:|-----------:|-----------------:|-----------------:|
| fable  | $10   | $50   | $1.00      | $12.50           | $20.00           |
| opus   | $5    | $25   | $0.50      | $6.25            | $10.00           |
| sonnet | $3    | $15   | $0.30      | $3.75            | $6.00            |
| haiku  | $1    | $5    | $0.10      | $1.25            | $2.00            |

`claude-opus-4-1` (deprecated model) keeps its legacy $15/$75 rate via an exact-key override.

**Enterprise / EDP discount:** set `"discountPercent": 20` in `pricing.json` for 20% off all computed costs.

When a new build ships with corrected rates, the app auto-upgrades your local `pricing.json` on first launch while preserving your `discountPercent`.

**Verify rates against your own contract** — Bedrock and Vertex rates differ from API list prices.

---

## How it works

```
TranscriptScanner  →  Aggregator  →  UsageStore  →  SwiftUI Views
      (disk)          (pure fold)   (ObservableObject)
```

1. **Incremental scan** — per-file byte cursors mean only newly appended bytes are parsed on each 60s refresh. Thousands of transcript files don't get re-read on every tick.
2. **Dedup by `message.id`** — Claude Code copies transcript lines into resumed and compacted sessions. The same API response can appear in multiple files; each `message.id` is counted exactly once (last occurrence per scan batch wins, so streamed responses always use their final complete token count).
3. **Local day bucketing** — UTC timestamps are converted to local calendar day so spending aligns with your actual workday.
4. **Model normalisation** — raw model strings (`bedrock/us.anthropic.claude-sonnet-4-6`, etc.) are mapped to a family (`opus`/`sonnet`/`haiku`/`fable`). `<synthetic>` messages cost $0.
5. **State persistence** — scan cursors, seen IDs, aggregates, and settings live in `~/Library/Application Support/ClaudeOMeter/`. Upgrading from an older version migrates state automatically so history and alert settings are preserved.

---

## Alerts & tips

**Budget alerts** fire once per day (daily limit) or once per month (monthly limit) via macOS notifications. Configure limits in Settings → Budgets & Alerts.

**Usage tips** fire at most weekly or monthly and surface patterns like:
- Opus is a large share of recent spend → consider Sonnet for everyday tasks
- Cache hit rate is high → positive reinforcement
- Spend spike vs previous week → flag for review

Disable tips in Settings → Show usage tips.

---

## Project layout

```
Sources/ClaudeOMeter/
  App.swift                 MenuBarExtra entry point
  Models.swift              TokenUsage, UsageRecord, DailyAggregate, AlertSettings
  Pricing.swift             ModelPrice/PricingTable, cost math, model normalisation
  ScanState.swift           Byte cursors + seen-IDs, pruning
  TranscriptScanner.swift   Incremental JSONL reader
  DayBucket.swift           UTC → local-day bucketing
  Aggregator.swift          Pure fold of records → daily aggregates
  PatternDetector.swift     Usage pattern detection (opus-heavy, cache miss, spend spike)
  Persistence.swift         App Support snapshot + pricing loader + state migration
  UsageStore.swift          ObservableObject orchestrating scan → aggregate → alert → tips
  AlertManager.swift        Threshold evaluation + notification dispatch
  Formatting.swift          USD / token / day-label helpers
  Views/
    PopoverView.swift       Main panel + settings panel
    HistoryChart.swift      Daily stacked bar + cumulative area chart
    DayRow.swift            Per-day expandable row
  Resources/
    pricing.json            Bundled default pricing table
scripts/
  build_app.sh              Assembles, signs, and zips ClaudeOMeter.app
Tests/ClaudeOMeterTests/    Unit tests (swift test)
```

---

## Contributing

Feedback and PRs welcome. Open an issue or ping [@Deklin](https://github.com/Deklin).

---

## License

MIT
