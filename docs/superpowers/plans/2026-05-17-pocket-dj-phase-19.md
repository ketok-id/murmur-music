# Pocket DJ Phase 19 — Quota Tracker

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Track YouTube API quota usage client-side and surface it in the settings sheet, so the user can see how close they are to the 10,000-unit/day free-tier limit. The tracker records each API call's cost (100 for search, 1 for everything else), persists across launches via `UserDefaults`, and auto-resets at Pacific midnight when Google resets.

**Caveat:** This is a client-side estimate, not Google's authoritative count. If the user makes API calls from outside Murmur with the same key, the count will diverge. Close enough for Murmur-only usage.

**Architecture:** `QuotaTracker` is a singleton `ObservableObject` mirroring the other store patterns. Records via `record(cost:)`. Rollover happens lazily on every `record` and on `load()` by comparing the stored "day" string (`yyyy-MM-dd` in America/Los_Angeles) to the current one. Each `YouTubeSearchAPI` method calls `QuotaTracker.shared.record(cost: …)` after a successful HTTP response. `APIKeySetupSheet` gains a quota readout below the API key field.

**Tech Stack:** Same — `UserDefaults`, `DateFormatter`, SwiftUI. No new dependencies.

**Testing:** `swift build -c release` + manual smoke in Task 4.

**Prerequisites:** Phase 18 merged into `main`.

---

## File Structure

**New files:**

```
Sources/Murmur/Ambient/
  QuotaTracker.swift      Singleton ObservableObject with record + rollover
```

**Modified files:**

- `Sources/Murmur/Ambient/YouTubeSearchAPI.swift` — call `QuotaTracker.shared.record(cost:)` after each successful API call.
- `Sources/Murmur/Booth/APIKeySetupSheet.swift` — display "Used today: N / 10,000" with progress bar.

---

### Task 1: QuotaTracker

**Files:**
- Create: `Sources/Murmur/Ambient/QuotaTracker.swift`

- [ ] **Step 1: Implement**

```swift
import Combine
import Foundation

/// Client-side estimate of YouTube Data API v3 quota usage.
///
/// - Records cost per call via `record(cost:)`.
/// - Persists across launches in `UserDefaults`.
/// - Resets when the calendar day changes in America/Los_Angeles (where
///   Google's quota resets at midnight).
///
/// Caveat: this only sees calls Murmur makes. Other apps using the same
/// API key will cause divergence from Google's authoritative count.
final class QuotaTracker: ObservableObject {
    static let shared = QuotaTracker()

    /// YouTube Data API v3 free-tier daily limit.
    static let dailyLimit = 10_000

    @Published private(set) var usedToday: Int = 0

    private let usedKey = "youtube-audio-widget.quota-used.v1"
    private let dayKey  = "youtube-audio-widget.quota-day.v1"

    private init() { load() }

    /// Units remaining before the daily limit. 0 if over.
    var remainingToday: Int { max(0, Self.dailyLimit - usedToday) }

    /// Fraction of daily limit consumed, 0…1.
    var fractionUsed: Double {
        min(1, Double(usedToday) / Double(Self.dailyLimit))
    }

    /// Record an API call's quota cost.
    func record(cost: Int) {
        rolloverIfNeeded()
        usedToday += cost
        save()
    }

    /// Manual reset (debug / test).
    func resetToday() {
        usedToday = 0
        save()
    }

    private func load() {
        rolloverIfNeeded()
        usedToday = UserDefaults.standard.integer(forKey: usedKey)
    }

    private func save() {
        UserDefaults.standard.set(usedToday, forKey: usedKey)
    }

    private func rolloverIfNeeded() {
        let today = currentPacificDay()
        let lastDay = UserDefaults.standard.string(forKey: dayKey) ?? ""
        if today != lastDay {
            usedToday = 0
            UserDefaults.standard.set(today, forKey: dayKey)
            UserDefaults.standard.set(0, forKey: usedKey)
        }
    }

    private func currentPacificDay() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return formatter.string(from: Date())
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
cd /Users/mm/Documents/youtube-audio-widget
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Ambient/QuotaTracker.swift
git commit -m "feat(ambient): add QuotaTracker for client-side YouTube quota usage"
```

---

### Task 2: Record costs in YouTubeSearchAPI methods

**Files:**
- Modify: `Sources/Murmur/Ambient/YouTubeSearchAPI.swift`

Add a `QuotaTracker.shared.record(cost:)` call after `try checkHTTPStatus(response: response, data: data)` in each public API method. Costs:

| Method | Cost |
|---|---|
| `search(...)` | 100 |
| `searchChannels(...)` | 100 |
| `fetchChannelDetails(...)` | 1 |
| `fetchChannelByHandle(...)` | 1 |
| `listChannelUploads(...)` | 1 |
| `fetchVideoDetails(...)` | 1 |

- [ ] **Step 1: Add record calls**

For each of the six methods above, find the line:

```swift
        try checkHTTPStatus(response: response, data: data)
```

Immediately after it, insert the cost-specific record line. Specifically:

In `search(...)`:
```swift
        try checkHTTPStatus(response: response, data: data)
        QuotaTracker.shared.record(cost: 100)
```

In `searchChannels(...)`:
```swift
        try checkHTTPStatus(response: response, data: data)
        QuotaTracker.shared.record(cost: 100)
```

In `fetchChannelDetails(...)`:
```swift
        try checkHTTPStatus(response: response, data: data)
        QuotaTracker.shared.record(cost: 1)
```

In `fetchChannelByHandle(...)`:
```swift
        try checkHTTPStatus(response: response, data: data)
        QuotaTracker.shared.record(cost: 1)
```

In `listChannelUploads(...)`:
```swift
        try checkHTTPStatus(response: response, data: data)
        QuotaTracker.shared.record(cost: 1)
```

In `fetchVideoDetails(...)`:
```swift
        try checkHTTPStatus(response: response, data: data)
        QuotaTracker.shared.record(cost: 1)
```

NOTE: `search(...)` is the original method from Phase 12 with inline HTTP error handling (not using `checkHTTPStatus`). Find its `if let http = response as? HTTPURLResponse { ... }` block. Immediately AFTER the closing `}` of that switch block (i.e., when we know the call succeeded), add:

```swift
        QuotaTracker.shared.record(cost: 100)
```

(That ensures `search()` records correctly even though it uses inline HTTP handling instead of the shared helper.)

- [ ] **Step 2: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Ambient/YouTubeSearchAPI.swift
git commit -m "feat(ambient): record per-call quota cost in YouTubeSearchAPI"
```

---

### Task 3: Display quota in APIKeySetupSheet

**Files:**
- Modify: `Sources/Murmur/Booth/APIKeySetupSheet.swift`

- [ ] **Step 1: Add quota readout**

Find the existing `APIKeySetupSheet` body. Below the API key SecureField + above the bottom row of buttons (Cancel / Save / Clear), add a `quotaSection`.

First, add an `@ObservedObject` for the tracker right after the existing `@ObservedObject var store: APIKeyStore`:

```swift
    @ObservedObject private var quota = QuotaTracker.shared
```

Then add the new computed property near the bottom of the struct (alongside the existing helpers):

```swift
    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("QUOTA TODAY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Text("\(quota.usedToday) / \(QuotaTracker.dailyLimit)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(quota.fractionUsed >= 0.9 ? .red.opacity(0.85) : .white.opacity(0.7))
            }

            // Thin progress bar.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                    Rectangle()
                        .fill(quota.fractionUsed >= 0.9 ? Color.red.opacity(0.8) :
                              quota.fractionUsed >= 0.7 ? Color.orange.opacity(0.8) :
                              Color.cyan.opacity(0.7))
                        .frame(width: geo.size.width * CGFloat(quota.fractionUsed))
                }
            }
            .frame(height: 4)
            .cornerRadius(2)

            Text("Resets at midnight Pacific. Murmur estimates client-side — actual quota may differ if you use the same key elsewhere.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
```

Find the existing `body` `VStack`. Between the `Divider().background(Color.white.opacity(0.1))` (which sits below the description text) and the `VStack(alignment: .leading, spacing: 4) { /* paste field */ }` block, insert the new section. Actually, the cleanest location is BELOW the SecureField group and ABOVE the bottom button row. The body order should be:

1. Header
2. Description text + Link
3. Divider
4. Paste API key SecureField group
5. **NEW**: another Divider + quotaSection
6. Bottom button row

To make that work, find the existing button HStack `HStack(spacing: 8) { ... if store.hasYouTubeKey { ... } }` near the end. Just BEFORE it, insert:

```swift

            Divider().background(Color.white.opacity(0.1))
            quotaSection
```

- [ ] **Step 2: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Booth/APIKeySetupSheet.swift
git commit -m "feat(booth): show quota usage with progress bar in APIKeySetupSheet"
```

---

### Task 4: Build bundle + smoke + tag + merge

- [ ] **Step 1: Build**

```bash
./build-app.sh --sign 2>&1 | tail -10
```

- [ ] **Step 2: Manual smoke**

Quit running Murmur. `open dist/Murmur.app`.

1. Open popover → gear icon → settings sheet appears.
2. Below the API key field and above the bottom buttons, a **QUOTA TODAY** section shows "0 / 10000" with an empty cyan progress bar (or whatever's left from prior usage if you've been testing today).
3. Close the sheet. Open the search sheet, do a video search ("lofi study"). 
4. Reopen settings → quota should show ~**101 / 10000** (100 for the search + 1 for the videos.list backfill).
5. Run a couple more searches → counter climbs.
6. Switch to Channels mode and search a name → another 100 units.
7. Paste a channel URL `@lofigirl` in Channels mode → only 1 unit (URL fast path uses channels.list?forHandle).
8. Browse a channel → 1 unit (or 2 if uploadsPlaylistId wasn't cached yet).
9. As `usedToday` approaches the limit, the progress bar transitions cyan → orange (≥70%) → red (≥90%).
10. Quit + relaunch → count persists.
11. Wait until midnight Pacific (or change your system date to next day) and relaunch → count resets to 0.

- [ ] **Step 3: Tag + merge**

```bash
git tag -a phase-19-quota-tracker -m "Pocket DJ Phase 19: client-side quota tracker"
git checkout main
git merge --no-ff pocket-dj-phase-19 -m "Merge phase 19: quota tracker"
./build-app.sh --sign 2>&1 | tail -5
```

---

## Out of scope for Phase 19

- Surfacing remaining quota in the popover header (could show a small "98% used" warning if approaching limit).
- "Quota exceeded" UX improvements (already handled by `SearchError.quotaExceeded` message).
- Showing per-call breakdown (which calls cost how much).
- Configurable daily limit (in case the user has elevated quota from Google).

---

## Self-Review

- **Client-side estimate** with clear disclaimer in UI ✅
- **Pacific midnight rollover** matches Google's reset behavior ✅
- **Cost per call** mapped accurately: search=100, everything else=1 ✅
- **Color-coded progress bar** at 70% / 90% thresholds ✅
- **Persists across launches** via UserDefaults ✅
- **No new dependencies** ✅
