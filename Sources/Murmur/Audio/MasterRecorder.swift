import AVFoundation
import Foundation

/// Records the engine's `mainMixerNode` output to a 48 kHz / 16-bit stereo WAV.
///
/// Only one recording can be active at a time. Files land in
/// `~/Library/Application Support/Murmur/Recordings/<timestamp>.wav`.
final class MasterRecorder {
    private let engine: AVAudioEngine
    private var outputFile: AVAudioFile?
    private(set) var isRecording = false
    private(set) var currentOutputURL: URL?

    init(engine: AVAudioEngine) {
        self.engine = engine
    }

    static var recordingsDirectory: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Murmur", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }

    @discardableResult
    func start() -> URL? {
        guard !isRecording else { return currentOutputURL }
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = Self.recordingsDirectory.appendingPathComponent("\(timestamp).wav")

        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            let file = try AVAudioFile(forWriting: url, settings: fileSettings)
            self.outputFile = file
            self.currentOutputURL = url
        } catch {
            NSLog("MasterRecorder failed to open file: \(error)")
            return nil
        }

        let mixer = engine.mainMixerNode
        let tapFormat = mixer.outputFormat(forBus: 0)
        mixer.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            guard let self = self, let file = self.outputFile else { return }
            do {
                try file.write(from: buffer)
            } catch {
                NSLog("MasterRecorder write error: \(error)")
            }
        }
        isRecording = true
        return url
    }

    @discardableResult
    func stop() -> URL? {
        guard isRecording else { return nil }
        engine.mainMixerNode.removeTap(onBus: 0)
        let url = currentOutputURL
        outputFile = nil
        isRecording = false
        return url
    }
}
