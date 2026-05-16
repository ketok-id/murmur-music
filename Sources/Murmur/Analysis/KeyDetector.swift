import AVFoundation
import Accelerate

/// Detects the musical key of an audio file via chromagram + Krumhansl-Schmuckler.
///
/// Returns both the human-readable musical name ("D minor") and the Camelot
/// notation ("7A") used in harmonic mixing.
enum KeyDetector {
    static let fftSize = 4096
    static let hopSize = 2048
    static let referenceFreq: Double = 440.0   // A4

    /// 12 pitch class names, C..B (semitones up from C).
    static let pitchNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    /// Camelot wheel mapping. Major:
    static let camelotMajor: [Int: String] = [
        0: "8B", 1: "3B", 2: "10B", 3: "5B", 4: "12B", 5: "7B",
        6: "2B", 7: "9B", 8: "4B", 9: "11B", 10: "6B", 11: "1B"
    ]
    static let camelotMinor: [Int: String] = [
        0: "5A", 1: "12A", 2: "7A", 3: "2A", 4: "9A", 5: "4A",
        6: "11A", 7: "6A", 8: "1A", 9: "8A", 10: "3A", 11: "10A"
    ]

    /// Krumhansl-Schmuckler major profile (C major), to be rotated.
    static let majorProfile: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09,
                                         2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    /// Krumhansl-Schmuckler minor profile (C minor), to be rotated.
    static let minorProfile: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53,
                                         2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    struct Result {
        let keyName: String
        let camelot: String
    }

    /// Synchronously detect key. Call from a background queue.
    static func detect(from url: URL) throws -> Result {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let mono = try readMono(file: file)
        let chromagram = computeChromagram(mono: mono, sampleRate: sampleRate)
        let (pitchClass, isMinor) = bestKeyProfile(chromagram: chromagram)
        let nameSuffix = isMinor ? "minor" : "major"
        let keyName = "\(pitchNames[pitchClass]) \(nameSuffix)"
        let camelot = (isMinor ? camelotMinor : camelotMajor)[pitchClass] ?? "?"
        return Result(keyName: keyName, camelot: camelot)
    }

    private static func readMono(file: AVAudioFile) throws -> [Float] {
        let format = file.processingFormat
        let chunkFrames: AVAudioFrameCount = 32768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw NSError(domain: "KeyDetector", code: 1)
        }
        var mono = [Float]()
        mono.reserveCapacity(Int(file.length))
        while file.framePosition < file.length {
            try file.read(into: buffer)
            let frameCount = Int(buffer.frameLength)
            if frameCount == 0 { break }
            guard let channelData = buffer.floatChannelData else { continue }
            let ch = Int(format.channelCount)
            for i in 0..<frameCount {
                var s: Float = 0
                for c in 0..<ch { s += channelData[c][i] }
                mono.append(s / Float(ch))
            }
        }
        return mono
    }

    private static func computeChromagram(mono: [Float], sampleRate: Double) -> [Float] {
        let n = fftSize
        let log2n = vDSP_Length(log2(Double(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return [Float](repeating: 0, count: 12)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))

        var chroma = [Float](repeating: 0, count: 12)
        let halfN = n / 2

        var realp = [Float](repeating: 0, count: halfN)
        var imagp = [Float](repeating: 0, count: halfN)
        var magnitudes = [Float](repeating: 0, count: halfN)

        var pos = 0
        while pos + n <= mono.count {
            var frame = [Float](repeating: 0, count: n)
            vDSP_vmul(Array(mono[pos..<pos + n]), 1, window, 1, &frame, 1, vDSP_Length(n))

            realp.withUnsafeMutableBufferPointer { rp in
                imagp.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    frame.withUnsafeBufferPointer { fp in
                        fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(halfN))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(halfN))
                }
            }

            let binHz = sampleRate / Double(n)
            for bin in 1..<halfN {
                let freq = Double(bin) * binHz
                if freq < 30 || freq > 5000 { continue }
                let midi = 69.0 + 12.0 * log2(freq / referenceFreq)
                let pc = Int(midi.rounded().truncatingRemainder(dividingBy: 12) + 12) % 12
                chroma[pc] += magnitudes[bin]
            }
            pos += hopSize
        }

        var maxV: Float = 0
        vDSP_maxv(chroma, 1, &maxV, vDSP_Length(12))
        if maxV > 0 { vDSP_vsdiv(chroma, 1, &maxV, &chroma, 1, vDSP_Length(12)) }
        return chroma
    }

    private static func bestKeyProfile(chromagram: [Float]) -> (Int, Bool) {
        var bestPC = 0
        var bestMinor = false
        var bestScore: Float = -.greatestFiniteMagnitude

        for pc in 0..<12 {
            for (profile, isMinor) in [(majorProfile, false), (minorProfile, true)] {
                var score: Float = 0
                for i in 0..<12 {
                    score += chromagram[i] * profile[(i - pc + 12) % 12]
                }
                if score > bestScore {
                    bestScore = score
                    bestPC = pc
                    bestMinor = isMinor
                }
            }
        }
        return (bestPC, bestMinor)
    }
}
