import AVFoundation
import Combine
import Foundation

/// Orchestrates background analysis of an audio file.
///
/// On `analyze(url:)`, checks the `LibraryIndex` first. If cached, the cached
/// metadata + sidecar peaks are returned via the completion immediately. If
/// not, queues both PeakExtractor and BPMDetector on the analysis queue,
/// writes the results, and fires completion.
///
/// One analysis per file at a time; calling `analyze(url:)` twice for the same
/// URL while the first is in-flight returns the same result to both callers.
final class AnalysisService {
    static let shared = AnalysisService()

    struct Result {
        let url: URL
        let metadata: TrackMetadata
        let peaks: [Float]
        let bandPeaks: [Float]
    }

    private let queue = DispatchQueue(label: "murmur.analysis", qos: .userInitiated)
    private let resultQueue = DispatchQueue.main
    private var inFlight: [String: [(Result?) -> Void]] = [:]
    private let inFlightLock = NSLock()

    private init() {}

    func analyze(url: URL, completion: @escaping (Result?) -> Void) {
        let path = url.path

        if let cached = LibraryIndex.shared.metadata(forPath: path) {
            let peaksURL = LibraryIndex.peaksDirectory.appendingPathComponent(cached.peaksPath)
            if FileManager.default.fileExists(atPath: peaksURL.path),
               let peaks = try? PeakExtractor.readPeaks(from: peaksURL) {
                var bandPeaks: [Float] = []
                if !cached.bandPeaksPath.isEmpty {
                    let bandURL = LibraryIndex.peaksDirectory.appendingPathComponent(cached.bandPeaksPath)
                    if FileManager.default.fileExists(atPath: bandURL.path) {
                        bandPeaks = (try? BandExtractor.readBands(from: bandURL)) ?? []
                    }
                }
                resultQueue.async {
                    completion(Result(url: url, metadata: cached, peaks: peaks, bandPeaks: bandPeaks))
                }
                return
            }
        }

        inFlightLock.lock()
        if var callbacks = inFlight[path] {
            callbacks.append(completion)
            inFlight[path] = callbacks
            inFlightLock.unlock()
            return
        }
        inFlight[path] = [completion]
        inFlightLock.unlock()

        queue.async {
            let result = self.runAnalysis(url: url)
            self.inFlightLock.lock()
            let callbacks = self.inFlight.removeValue(forKey: path) ?? []
            self.inFlightLock.unlock()
            self.resultQueue.async {
                for cb in callbacks { cb(result) }
            }
        }
    }

    private func runAnalysis(url: URL) -> Result? {
        do {
            let peaks = try PeakExtractor.extract(from: url)
            let bands = (try? BandExtractor.extract(from: url)) ?? []
            let bpm = try BPMDetector.detect(from: url)
            let keyResult = (try? KeyDetector.detect(from: url))
                ?? KeyDetector.Result(keyName: "", camelot: "")
            let meta = runMetadataExtract(url: url)
            let file = try AVAudioFile(forReading: url)
            let duration = Double(file.length) / file.processingFormat.sampleRate

            let baseName = url.deletingPathExtension().lastPathComponent + "-" +
                String(url.path.hashValue, radix: 16)
            let peaksFilename = baseName + ".peaks"
            let bandsFilename = baseName + ".bands"
            let peaksURL = LibraryIndex.peaksDirectory.appendingPathComponent(peaksFilename)
            let bandsURL = LibraryIndex.peaksDirectory.appendingPathComponent(bandsFilename)
            try PeakExtractor.writePeaks(peaks, to: peaksURL)
            if !bands.isEmpty {
                try? BandExtractor.writeBands(bands, to: bandsURL)
            }

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
                artworkPath: meta.artworkPath,
                bandPeaksPath: bands.isEmpty ? "" : bandsFilename
            )
            LibraryIndex.shared.setMetadata(metadata, forPath: url.path)

            NSLog("[Analysis] %@ → BPM=%.2f, key=%@ (%@), \"%@\" by %@, duration=%.1fs, bands=%d",
                  url.lastPathComponent, bpm,
                  keyResult.keyName.isEmpty ? "?" : keyResult.keyName,
                  keyResult.camelot.isEmpty ? "?" : keyResult.camelot,
                  meta.title, meta.artist.isEmpty ? "unknown" : meta.artist,
                  duration, bands.count / 3)
            return Result(url: url, metadata: metadata, peaks: peaks, bandPeaks: bands)
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
}
