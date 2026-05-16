import AVFoundation
import Combine
import Foundation

/// Lists and manages bounced recording files on disk.
final class RecordingsStore: ObservableObject {
    @Published private(set) var recordings: [Recording] = []

    init() {
        refresh()
    }

    func refresh() {
        let dir = MasterRecorder.recordingsDirectory
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            recordings = []
            return
        }

        var list: [Recording] = []
        for url in urls where url.pathExtension.lowercased() == "wav" {
            let attrs = (try? url.resourceValues(forKeys: [
                .contentModificationDateKey, .fileSizeKey,
            ])) ?? URLResourceValues()
            let date = attrs.contentModificationDate ?? Date.distantPast
            let size = Int64(attrs.fileSize ?? 0)
            let duration = (try? AVAudioFile(forReading: url)).map { f in
                Double(f.length) / f.processingFormat.sampleRate
            } ?? 0
            list.append(Recording(url: url, date: date, duration: duration, sizeBytes: size))
        }
        list.sort { $0.date > $1.date }
        recordings = list
    }

    func delete(_ recording: Recording) {
        try? FileManager.default.removeItem(at: recording.url)
        refresh()
    }
}
