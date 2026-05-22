---
description: Insert a new CatalogItem into the Discover catalog in ContentView.swift.
argument-hint: <category> | <name> | <videoID-or-YouTube-URL>
---

Add a new live-music entry to the in-app Discover catalog. Arguments are pipe-separated: `$ARGUMENTS` = `<category> | <name> | <videoID-or-URL>`.

## Parse and validate

1. Split `$ARGUMENTS` on `|`, trim whitespace from each part. Expect exactly 3 parts. If not, stop and ask the user for the right format.
2. **Normalize the videoID:**
   - If the third part is an 11-character YouTube ID (matches `^[A-Za-z0-9_-]{11}$`), use as-is.
   - If it's a YouTube URL (`youtube.com/watch?v=…`, `youtu.be/…`, `youtube.com/embed/…`), extract the `v=` query param or the path segment.
   - Otherwise stop and report.
3. **Reject** the special placeholder `kDefaultVideoID` — that's reserved for the "Featured → Claude FM" entry and should stay tied to `PlayerController.kDefaultVideoID`. Tell the user to bump `kDefaultVideoID` in `Sources/Murmur/PlayerController.swift` instead.

## Locate and edit

The catalog lives in `Sources/Murmur/ContentView.swift` as `private static let catalog: [CatalogGroup]` (around line 327). Structure:

```swift
CatalogGroup(category: "<category>", items: [
    CatalogItem(name: "<name>", videoID: "<id>"),
    ...
])
```

1. **If the category already exists:** append a new `CatalogItem(name: "<name>", videoID: "<id>")` line to that group's `items: [...]`. Match the indentation of the surrounding lines exactly (4-space indent inside the array, then 12-space indent for items).
2. **If the category is new:** append a fresh `CatalogGroup(...)` block before the closing `]` of `catalog`.

## Verify

After the edit, run `swift build -c release` and confirm it succeeds. Then report:
- File + line number of the inserted item
- The literal line added
- Reminder: stream IDs go stale when channels restart — that's expected behavior per CLAUDE.md, not a bug.

## Do not

- Don't reformat unrelated lines in the catalog. Minimal-diff edit only.
- Don't add comments around the new entry. The catalog is a flat data table; comments aren't the pattern.
- Don't re-sort categories or items.
