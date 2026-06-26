# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Dev run (Dock icon visible — useful for iteration)
swift run

# Build distributable .app (no Dock icon, ad-hoc signed)
./scripts/build_app.sh
open dist/ClaudeCostBar.app

# Run tests
swift test

# Run a single test
swift test --filter ClaudeCostBarTests/testParseLineDedupsByMessageID
```

## Architecture

ClaudeCostBar is a macOS SwiftUI menu-bar app. The data flow is strictly one-way:

```
TranscriptScanner  →  Aggregator  →  UsageStore  →  SwiftUI Views
      (disk)          (pure fold)    (ObservableObject)
```

**`UsageStore`** (`UsageStore.swift`) is the single source of truth — an `@MainActor ObservableObject` that owns a `Persistence.Snapshot`. On a 60-second timer it triggers a scan off the main actor, then calls `apply()` which folds new records in, prunes old data, fires alerts, runs pattern tips, and persists to disk.

**`TranscriptScanner`** (`TranscriptScanner.swift`) reads `~/.claude/projects/**/*.jsonl` incrementally. Per-file byte cursors (`ScanState.cursors`) mean only newly appended bytes are parsed. Dedup is global: `message.id` is stored in `ScanState.seenIDs`; duplicate entries (produced when Claude Code resumes or compacts sessions) are silently dropped.

**`Aggregator`** (`Aggregator.swift`) is a pure function — no side effects — that folds `[UsageRecord]` into `[String: DailyAggregate]`. This makes it trivially testable without any app state.

**`Persistence`** (`Persistence.swift`) owns the `~/Library/Application Support/ClaudeCostBar/` directory. `state.json` holds the full snapshot (scan cursors, seen-IDs, aggregates, alert/tip state). `pricing.json` is user-editable and seeded from the bundled default on first run.

**Pricing lookup** (`Pricing.swift`): `PricingTable` checks for an exact raw-model key first (e.g. `"claude-opus-4-8"`), then the family key (`"opus"`), then the fallback. `rawModel` is stored in `ModelUsage` so `Aggregator.recost` can re-apply exact-key prices after a pricing reload.

**`PatternDetector`** (`PatternDetector.swift`) detects usage patterns (opus-heavy, low cache efficiency, spend spikes) and produces `PatternInsight` values. `AlertManager` (`AlertManager.swift`) evaluates daily/monthly budget thresholds and dispatches `UNUserNotification`s — once per day for daily alerts, once per month for monthly.

## Key invariants

- **Dedup is essential**: the same `message.id` appears in multiple JSONL files when sessions are resumed or compacted. Raw line counts overstate cost by 2× or more. Always go through `ScanState.seenIDs`.
- **`<synthetic>` messages cost $0**: `ModelNormalizer.syntheticFamily` is checked in `PricingTable.cost` before any arithmetic.
- **Byte cursors never skip past the last newline**: partial trailing lines are re-read on the next scan pass.
- **All aggregation is by local calendar day**, not UTC. `DayBucket.localDay(fromISO:)` converts the UTC timestamp in each JSONL line.

## Bundle resource loading

The `.app` built by `build_app.sh` places resources under `Contents/Resources/`. `Persistence.loadPricing()` uses `Bundle.main.url(forResource:subdirectory:)` with the SwiftPM sub-bundle name (`ClaudeCostBar_ClaudeCostBar.bundle`) rather than `Bundle.module`, because codesign requires resources inside `Contents/` and `Bundle.module` would look at the `.app` root.
