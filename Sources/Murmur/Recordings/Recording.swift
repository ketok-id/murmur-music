import AVFoundation
import Foundation

/// One bounced master recording on disk.
struct Recording: Identifiable, Equatable {
    let url: URL
    let date: Date
    let duration: Double
    let sizeBytes: Int64

    var id: URL { url }

    var sizeLabel: String {
        ByteCountFormatter().string(fromByteCount: sizeBytes)
    }

    var durationLabel: String {
        let s = Int(duration)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var dateLabel: String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}
