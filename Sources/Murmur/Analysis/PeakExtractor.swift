import AVFoundation
import Accelerate

/// Decodes an audio file into a fixed-count array of (min, max) sample pairs
/// for waveform rendering.
///
/// Output is interleaved: `[min0, max0, min1, max1, ...]`. The total pair
/// count is `binCount` regardless of source duration — short files produce
/// fine-grained bins, long files produce coarser bins.
enum PeakExtractor {
    /// Synchronously extract peaks. Call from a background queue.
    static func extract(from url: URL, binCount: Int = 2000) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = AVAudioFrameCount(file.length)
        let framesPerBin = max(1, Int(totalFrames) / binCount)

        let chunkFrames: AVAudioFrameCount = AVAudioFrameCount(framesPerBin * 4)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw NSError(domain: "PeakExtractor", code: 1)
        }

        var peaks = [Float]()
        peaks.reserveCapacity(binCount * 2)

        var binAccumMin: Float = .greatestFiniteMagnitude
        var binAccumMax: Float = -.greatestFiniteMagnitude
        var samplesInBin: Int = 0

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
                sample /= Float(channelCount)

                binAccumMin = min(binAccumMin, sample)
                binAccumMax = max(binAccumMax, sample)
                samplesInBin += 1

                if samplesInBin >= framesPerBin && peaks.count < binCount * 2 {
                    peaks.append(binAccumMin)
                    peaks.append(binAccumMax)
                    binAccumMin = .greatestFiniteMagnitude
                    binAccumMax = -.greatestFiniteMagnitude
                    samplesInBin = 0
                }
            }
        }
        if samplesInBin > 0 && peaks.count < binCount * 2 {
            peaks.append(binAccumMin)
            peaks.append(binAccumMax)
        }
        return peaks
    }

    /// Write a `[Float]` peaks array to a sidecar file as raw Float32.
    static func writePeaks(_ peaks: [Float], to url: URL) throws {
        try peaks.withUnsafeBufferPointer { buf in
            let data = Data(buffer: buf)
            try data.write(to: url, options: .atomic)
        }
    }

    /// Read a peaks sidecar file back into a `[Float]`.
    static func readPeaks(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        return data.withUnsafeBytes { raw -> [Float] in
            let floats = raw.bindMemory(to: Float.self)
            return Array(floats)
        }
    }
}
