# Pocket DJ Phase 5 — Track Polish (Metadata + Album Art + Drag-and-Drop)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every loaded track show its real artist/title (from `AVAsset` metadata, not the filename), display embedded album art as a thumbnail in each deck, and let the user drag-and-drop audio files from Finder directly onto a deck panel instead of using the file picker.

**Architecture:** A new `MetadataExtractor` reads `AVAsset.commonMetadata` for title/artist/album and extracts the first artwork item, writing the artwork to `~/Library/Application Support/Murmur/artwork/<hash>.png`. `TrackMetadata` gains `title`, `artist`, `album`, `artworkPath` fields, populated by `AnalysisService`. `DeckState` exposes these to the UI. `DeckView` shows artwork + title + artist in place of the bare filename. A SwiftUI `.onDrop(of:isTargeted:perform:)` modifier on each deck consumes `public.file-url` payloads from Finder.

**Tech Stack:** Same as before — `AVFoundation` for metadata, `AppKit`/`SwiftUI` for UI. No new SwiftPM dependencies.

**Testing:** `swift build -c release` + manual smoke in Task 8. No Co-Authored-By trailer in subagent commits.

**Prerequisites:** Phase 4 merged into `main`. The booth shows BPM/key, waveform, sync/hot cues/loops, FX, ambient layer, mood dial, scenes.

---

## File Structure

**New files:**

```
Sources/Murmur/Analysis/
  MetadataExtractor.swift    Reads AVAsset.commonMetadata + artwork to disk
Sources/Murmur/Booth/
  AlbumArtView.swift         NSImage from disk path with rounded corners + placeholder
```

**Modified files:**

- `Sources/Murmur/Analysis/TrackMetadata.swift` — add `title`, `artist`, `album`, `artworkPath`.
- `Sources/Murmur/Analysis/AnalysisService.swift` — call `MetadataExtractor` and pass results to `TrackMetadata`.
- `Sources/Murmur/Analysis/LibraryIndex.swift` — add `artworkDirectory` (Application Support/Murmur/artwork/).
- `Sources/Murmur/Decks/DeckState.swift` — add `title`, `artist`, `album`, `artworkPath`.
- `Sources/Murmur/Decks/DeckController.swift` — restore metadata in analysis callback; reset on load.
- `Sources/Murmur/Booth/DeckView.swift` — replace `displayName` row with `AlbumArtView` + title + artist; add `.onDrop` modifier on the deck panel.

---

### Task 1: MetadataExtractor

**Files:**
- Create: `Sources/Murmur/Analysis/MetadataExtractor.swift`

- [ ] **Step 1: Implement**

```swift
import AVFoundation
import AppKit

/// Extracts title/artist/album/artwork from an audio file via AVAsset metadata.
///
/// Artwork is persisted as a PNG sidecar in `LibraryIndex.artworkDirectory`,
/// keyed by a hash of the source path so re-loading the same file is a cache
/// hit. The returned `artworkPath` is a filename (not full path) — callers
/// resolve it against the artwork directory.
enum MetadataExtractor {
    struct Result {
        let title: String
        let artist: String
        let album: String
        /// Filename of the PNG sidecar in the artwork directory, or empty if no art was found.
        let artworkPath: String
    }

    /// Synchronously extract metadata. Call from a background queue.
    static func extract(from url: URL) async -> Result {
        let asset = AVURLAsset(url: url)
        var title = ""
        var artist = ""
        var album = ""
        var artworkPath = ""

        do {
            let items = try await asset.load(.commonMetadata)
            for item in items {
                guard let commonKey = item.commonKey else { continue }
                switch commonKey {
                case .commonKeyTitle:
                    if let v = try? await item.load(.stringValue), !v.isEmpty { title = v }
                case .commonKeyArtist:
                    if let v = try? await item.load(.stringValue), !v.isEmpty { artist = v }
                case .commonKeyAlbumName:
                    if let v = try? await item.load(.stringValue), !v.isEmpty { album = v }
                case .commonKeyArtwork:
                    if let data = try? await item.load(.dataValue),
                       let image = NSImage(data: data) {
                        artworkPath = saveArtwork(image, sourcePath: url.path)
                    }
                default:
                    break
                }
            }
        } catch {
            NSLog("[Metadata] failed for \(url.lastPathComponent): \(error)")
        }

        // Fallback: use filename if no title was found.
        if title.isEmpty {
            title = url.deletingPathExtension().lastPathComponent
        }
        return Result(title: title, artist: artist, album: album, artworkPath: artworkPath)
    }

    /// Save NSImage to artwork directory as PNG. Returns the filename.
    private static func saveArtwork(_ image: NSImage, sourcePath: String) -> String {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return ""
        }
        let filename = "art-" + String(sourcePath.hashValue, radix: 16) + ".png"
        let url = LibraryIndex.artworkDirectory.appendingPathComponent(filename)
        do {
            try png.write(to: url, options: .atomic)
            return filename
        } catch {
            NSLog("[Metadata] artwork save failed: \(error)")
            return ""
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/mm/Documents/youtube-audio-widget
swift build -c release 2>&1 | tail -5
```

The build will FAIL because `LibraryIndex.artworkDirectory` doesn't exist yet — that's Task 2. Skip the verify-build for this task and commit anyway:

```bash
git add Sources/Murmur/Analysis/MetadataExtractor.swift
git commit -m "feat(analysis): add MetadataExtractor for title/artist/album/artwork"
```

(Build will be clean after Task 2.)

---

### Task 2: TrackMetadata + LibraryIndex extensions

**Files:**
- Modify: `Sources/Murmur/Analysis/TrackMetadata.swift`
- Modify: `Sources/Murmur/Analysis/LibraryIndex.swift`

- [ ] **Step 1: Extend `TrackMetadata`**

Find:
```swift
struct TrackMetadata: Codable, Equatable {
    let bpm: Double
    let duration: Double
    var firstBeat: Double
    let peaksPath: String
    var hotCues: [HotCue] = []
    var keyName: String = ""
    var camelot: String = ""
}
```

Replace with:
```swift
struct TrackMetadata: Codable, Equatable {
    let bpm: Double
    let duration: Double
    var firstBeat: Double
    let peaksPath: String
    var hotCues: [HotCue] = []
    var keyName: String = ""
    var camelot: String = ""
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var artworkPath: String = ""
}
```

- [ ] **Step 2: Add artworkDirectory to LibraryIndex**

Open `Sources/Murmur/Analysis/LibraryIndex.swift`. Find:

```swift
    /// Where peak sidecar files live.
    static var peaksDirectory: URL {
```

Add this property immediately above it:

```swift
    /// Where artwork PNG sidecars live.
    static var artworkDirectory: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Murmur", isDirectory: true)
            .appendingPathComponent("artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

```

- [ ] **Step 3: Build**

```bash
swift build -c release 2>&1 | tail -5
```

Should now succeed (MetadataExtractor from Task 1 resolves).

- [ ] **Step 4: Commit**

```bash
git add Sources/Murmur/Analysis/TrackMetadata.swift Sources/Murmur/Analysis/LibraryIndex.swift
git commit -m "feat(analysis): extend TrackMetadata + LibraryIndex with artwork dir"
```

---

### Task 3: Wire MetadataExtractor into AnalysisService

**Files:**
- Modify: `Sources/Murmur/Analysis/AnalysisService.swift`

- [ ] **Step 1: Update runAnalysis to call MetadataExtractor**

The existing `runAnalysis(url:)` is non-async. `MetadataExtractor.extract` is async. Wrap the call in a sync bridge.

Find the existing `runAnalysis(url:)` method. Replace its entire body with:

```swift
    private func runAnalysis(url: URL) -> Result? {
        do {
            let peaks = try PeakExtractor.extract(from: url)
            let bpm = try BPMDetector.detect(from: url)
            let keyResult = (try? KeyDetector.detect(from: url))
                ?? KeyDetector.Result(keyName: "", camelot: "")
            let meta = runMetadataExtract(url: url)
            let file = try AVAudioFile(forReading: url)
            let duration = Double(file.length) / file.processingFormat.sampleRate

            let peaksFilename = url.deletingPathExtension().lastPathComponent + "-" +
                String(url.path.hashValue, radix: 16) + ".peaks"
            let peaksURL = LibraryIndex.peaksDirectory.appendingPathComponent(peaksFilename)
            try PeakExtractor.writePeaks(peaks, to: peaksURL)

            let metadata = TrackMetadata(
                bpm: bpm,
                duration: duration,
                firstBeat: 0,
                peaksPath: peaksFilename,
                hotCues: [],
                keyName: keyResult.keyName,
                camelot: keyResult.camelot,
                title: meta.title,
                artist: meta.artist,
                album: meta.album,
                artworkPath: meta.artworkPath
            )
            LibraryIndex.shared.setMetadata(metadata, forPath: url.path)

            NSLog("[Analysis] %@ → BPM=%.2f, key=%@ (%@), \"%@\" by %@, duration=%.1fs",
                  url.lastPathComponent, bpm,
                  keyResult.keyName.isEmpty ? "?" : keyResult.keyName,
                  keyResult.camelot.isEmpty ? "?" : keyResult.camelot,
                  meta.title, meta.artist.isEmpty ? "unknown" : meta.artist,
                  duration)
            return Result(url: url, metadata: metadata, peaks: peaks)
        } catch {
            NSLog("[Analysis] failed for \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    /// Bridge from sync background queue to MetadataExtractor's async API.
    private func runMetadataExtract(url: URL) -> MetadataExtractor.Result {
        let semaphore = DispatchSemaphore(value: 0)
        var result = MetadataExtractor.Result(title: "", artist: "", album: "", artworkPath: "")
        Task.detached {
            result = await MetadataExtractor.extract(from: url)
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }
```

- [ ] **Step 2: Build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Analysis/AnalysisService.swift
git commit -m "feat(analysis): extract title/artist/album/artwork into TrackMetadata"
```

---

### Task 4: DeckState additions

**Files:**
- Modify: `Sources/Murmur/Decks/DeckState.swift`

- [ ] **Step 1: Add properties**

Find the existing Phase 3 property block (ends with `@Published var reverbWet: Float = 0.3`). After it, add:

```swift

    // ── Phase 5: track metadata + artwork ─────────────────────────────────

    /// Track title from metadata. Falls back to filename if empty.
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var album: String = ""
    /// Filename of artwork PNG in `LibraryIndex.artworkDirectory`. Empty = no art.
    @Published var artworkPath: String = ""
```

- [ ] **Step 2: Build and commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Decks/DeckState.swift
git commit -m "feat(decks): add Phase 5 state — title, artist, album, artworkPath"
```

---

### Task 5: DeckController wire metadata

**Files:**
- Modify: `Sources/Murmur/Decks/DeckController.swift`

- [ ] **Step 1: Restore metadata in analysis callback**

Find the analysis completion block inside `load(url:)`. It currently ends with:

```swift
                self.state.keyName = result.metadata.keyName
                self.state.camelot = result.metadata.camelot
            }
```

Replace those last two lines + closing brace with:

```swift
                self.state.keyName = result.metadata.keyName
                self.state.camelot = result.metadata.camelot
                self.state.title = result.metadata.title
                self.state.artist = result.metadata.artist
                self.state.album = result.metadata.album
                self.state.artworkPath = result.metadata.artworkPath
            }
```

- [ ] **Step 2: Reset metadata on load/error**

Two places reset state. Both end with:

```swift
            state.keyName = ""
            state.camelot = ""
```

Replace BOTH occurrences with:

```swift
            state.keyName = ""
            state.camelot = ""
            state.title = ""
            state.artist = ""
            state.album = ""
            state.artworkPath = ""
```

- [ ] **Step 3: Build and commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Decks/DeckController.swift
git commit -m "feat(decks): restore title/artist/album/artwork on track load"
```

---

### Task 6: AlbumArtView

**Files:**
- Create: `Sources/Murmur/Booth/AlbumArtView.swift`

- [ ] **Step 1: Implement**

```swift
import AppKit
import SwiftUI

/// Displays album art from a `LibraryIndex.artworkDirectory` filename, with a
/// fallback gradient placeholder when no art is available.
struct AlbumArtView: View {
    /// Filename in `LibraryIndex.artworkDirectory`. Empty string = no art.
    let artworkPath: String
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let img = loadImage() {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [Color(white: 0.18), Color(white: 0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4, weight: .regular))
                        .foregroundColor(.white.opacity(0.2))
                )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func loadImage() -> NSImage? {
        guard !artworkPath.isEmpty else { return nil }
        let url = LibraryIndex.artworkDirectory.appendingPathComponent(artworkPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Booth/AlbumArtView.swift
git commit -m "feat(booth): add AlbumArtView with placeholder fallback"
```

---

### Task 7: DeckView — title/artist row + album art + drag-and-drop

**Files:**
- Modify: `Sources/Murmur/Booth/DeckView.swift`

- [ ] **Step 1: Add UniformTypeIdentifiers import**

Open `Sources/Murmur/Booth/DeckView.swift`. The file already imports `UniformTypeIdentifiers`, so no change.

- [ ] **Step 2: Replace `displayName` row with artwork + title + artist**

Find the existing displayName block:

```swift
            Text(state.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
```

Replace with:

```swift
            HStack(alignment: .top, spacing: 10) {
                AlbumArtView(artworkPath: state.artworkPath, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if !state.artist.isEmpty {
                        Text(state.artist)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
```

And add this computed property in the same struct, near the other `private var` properties (e.g., near `pickFile` and `timeString`):

```swift
    private var displayTitle: String {
        if !state.title.isEmpty { return state.title }
        return state.displayName
    }
```

- [ ] **Step 3: Add drag-and-drop modifier**

The DeckView's outer chain currently ends:

```swift
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.06))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .cornerRadius(8)
    }
```

Change to:

```swift
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.06))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .cornerRadius(8)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                DispatchQueue.main.async {
                    onLoad(url)
                }
            }
            return true
        }
    }
```

- [ ] **Step 4: Build**

```bash
swift build -c release 2>&1 | tail -10
```

- [ ] **Step 5: Commit**

```bash
git add Sources/Murmur/Booth/DeckView.swift
git commit -m "feat(booth): show album art + title/artist; accept drag-and-drop"
```

---

### Task 8: Build bundle + manual smoke + tag + merge

- [ ] **Step 1: Build**

```bash
./build-app.sh --sign 2>&1 | tail -10
```

- [ ] **Step 2: Manual smoke**

`open dist/Murmur.app`.

1. **Load via file picker:** click the folder icon on Deck 1 → pick an M4A or MP3 with embedded metadata. After analysis:
   - The deck shows the **album art** thumbnail (44×44) next to the track info.
   - The track row shows the **real title** (from metadata, not the filename) in bold and **artist** in smaller dim text below.
   - For a file without metadata, the filename is the fallback title and no artist line appears; the artwork shows a music-note placeholder.
2. Console.app, filter "Murmur": `[Analysis] track.m4a → BPM=…, key=…, "Real Title" by Real Artist, duration=…`.
3. **Drag-and-drop:** open Finder, grab an audio file, drag it directly onto Deck 2's panel anywhere (not just the folder icon) → drops it, the deck shows analyzing → metadata + art appear. Same as loading via the picker.
4. **Cache:** quit and re-open the app. Load the same track on a deck. Album art appears immediately (it's in `~/Library/Application Support/Murmur/artwork/`); no re-extraction.
5. **Track with no embedded art** → music-note placeholder shows. Track with no embedded title → filename shown as title.

- [ ] **Step 3: Tag**

```bash
git tag -a phase-5-track-polish -m "Pocket DJ Phase 5: metadata + album art + drag-and-drop"
```

- [ ] **Step 4: Merge to main**

```bash
git checkout main
git merge --no-ff pocket-dj-phase-5 -m "Merge phase 5: track polish (metadata + album art + drag-and-drop)"
./build-app.sh --sign 2>&1 | tail -5
```

---

## Out of scope for Phase 5

- Recordings library UI (browse + play back bounced WAVs)
- Onboarding / first-run experience
- Track metadata editing in-app
- Artwork for ambient YouTube sources (would need YouTube API thumbnail fetch — separate phase)

---

## Self-Review

- **§6.1 Album art:** ✅ Extracted from `AVAsset.commonMetadata` and cached as PNG.
- **§6.2 Title/artist/album:** ✅ Read from common metadata with filename fallback.
- **§6.3 Drag-and-drop:** ✅ `.onDrop(of: [.fileURL])` on each deck panel.
- **§7.5 Persistence:** ✅ artwork in Application Support/Murmur/artwork/, indexed by source path hash.

No spec gaps for the in-scope set. Type signatures consistent across tasks (`TrackMetadata.title/artist/album/artworkPath`, `DeckState.title/artist/album/artworkPath`, `MetadataExtractor.Result.title/artist/album/artworkPath`).
