import AVFoundation
import Accelerate

/// Detects BPM via amplitude-onset autocorrelation.
///
/// Algorithm:
///   1. Decode full file to mono Float32 (mixing channels).
///   2. Compute frame-RMS envelope at hopSize=512 samples.
///   3. Half-wave rectified first-order difference (= onset envelope).
///   4. Autocorrelate onset at lags corresponding to 60-180 BPM.
///   5. Octave correction: if peak BPM > 140 and BPM/2 has correlation ≥ 0.7 * peak,
///      prefer the lower BPM.
enum BPMDetector {
    static let hopSize = 512
    static let minBPM: Double = 60
    static let maxBPM: Double = 180

    /// Synchronously detect BPM. Call from a background queue.
    static func detect(from url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = AVAudioFrameCount(file.length)

        let mono = try readMono(file: file, totalFrames: totalFrames)
        let envelope = rmsEnvelope(mono: mono, hopSize: hopSize)
        let onset = onsetEnvelope(envelope: envelope)

        let frameRate = sampleRate / Double(hopSize)
        let minLag = Int(frameRate * 60.0 / maxBPM)
        let maxLag = Int(frameRate * 60.0 / minBPM)
        var bestLag = minLag
        var bestCorr: Float = 0
        var corrAtLag = [Int: Float]()
        for lag in minLag...maxLag {
            let n = onset.count - lag
            if n <= 0 { break }
            var corr: Float = 0
            for i in 0..<n {
                corr += onset[i] * onset[i + lag]
            }
            corrAtLag[lag] = corr
            if corr > bestCorr {
                bestCorr = corr
                bestLag = lag
            }
        }
        var bpm = 60.0 * frameRate / Double(bestLag)

        if bpm > 140 {
            let halfLag = Int(frameRate * 60.0 / (bpm / 2))
            if let halfCorr = corrAtLag[halfLag], halfCorr >= 0.7 * bestCorr {
                bpm = bpm / 2
            }
        }
        return bpm
    }

    private static func readMono(file: AVAudioFile, totalFrames: AVAudioFrameCount) throws -> [Float] {
        let format = file.processingFormat
        let chunkFrames: AVAudioFrameCount = 32768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw NSError(domain: "BPMDetector", code: 1)
        }
        var mono = [Float]()
        mono.reserveCapacity(Int(totalFrames))

        while file.framePosition < file.length {
            try file.read(into: buffer)
            let frameCount = Int(buffer.frameLength)
            if frameCount == 0 { break }
            guard let channelData = buffer.floatChannelData else { continue }
            let channelCount = Int(format.channelCount)

            for frame in 0..<frameCount {
                var sample: Float = 0
                for ch in 0..<channelCount {
                    sample += channelData[ch][frame]
                }
                mono.append(sample / Float(channelCount))
            }
        }
        return mono
    }

    private static func rmsEnvelope(mono: [Float], hopSize: Int) -> [Float] {
        let numHops = mono.count / hopSize
        var env = [Float](repeating: 0, count: numHops)
        mono.withUnsafeBufferPointer { ptr in
            for i in 0..<numHops {
                var rms: Float = 0
                vDSP_rmsqv(ptr.baseAddress!.advanced(by: i * hopSize),
                           1, &rms, vDSP_Length(hopSize))
                env[i] = rms
            }
        }
        return env
    }

    private static func onsetEnvelope(envelope: [Float]) -> [Float] {
        var onset = [Float](repeating: 0, count: envelope.count)
        for i in 1..<envelope.count {
            onset[i] = max(0, envelope[i] - envelope[i-1])
        }
        return onset
    }
}
