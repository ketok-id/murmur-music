import AVFoundation
import Accelerate

/// Extracts 3-band frequency energy per peak bin for waveform coloring.
///
/// Output: interleaved `[low0, mid0, high0, low1, mid1, high1, ...]` — `binCount × 3`
/// floats in 0…1 (normalized so the loudest single-band value is 1.0).
///
/// Band cutoffs:
///   - low:  20 – 250 Hz   (kick, sub-bass)
///   - mid:  250 – 4000 Hz (vocals, melody)
///   - high: 4000 Hz +     (cymbals, percussion, air)
enum BandExtractor {
    static let fftSize = 2048
    static let hopSize = 1024
    static let lowCutoffHz: Double = 250
    static let midCutoffHz: Double = 4000

    static func extract(from url: URL, binCount: Int = 2000) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate

        let mono = try readMono(file: file)
        if mono.isEmpty { return [] }

        let n = fftSize
        let log2n = vDSP_Length(log2(Double(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return []
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))

        let halfN = n / 2
        var realp = [Float](repeating: 0, count: halfN)
        var imagp = [Float](repeating: 0, count: halfN)
        var magnitudes = [Float](repeating: 0, count: halfN)

        let binHz = sampleRate / Double(n)
        let lowBandBin = max(1, Int(lowCutoffHz / binHz))
        let midBandBin = max(lowBandBin + 1, Int(midCutoffHz / binHz))

        var fftLow = [Float]()
        var fftMid = [Float]()
        var fftHigh = [Float]()
        fftLow.reserveCapacity(mono.count / hopSize)
        fftMid.reserveCapacity(mono.count / hopSize)
        fftHigh.reserveCapacity(mono.count / hopSize)

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

            var low: Float = 0
            var mid: Float = 0
            var high: Float = 0
            for bin in 1..<halfN {
                let m = magnitudes[bin]
                if bin < lowBandBin { low += m }
                else if bin < midBandBin { mid += m }
                else { high += m }
            }
            fftLow.append(low)
            fftMid.append(mid)
            fftHigh.append(high)
            pos += hopSize
        }

        let windowCount = fftLow.count
        guard windowCount > 0 else { return [] }

        var output = [Float](repeating: 0, count: binCount * 3)
        var maxBand: Float = 0
        for binIdx in 0..<binCount {
            let startWin = Int(Double(binIdx) / Double(binCount) * Double(windowCount))
            let endWin = max(startWin + 1,
                             Int(Double(binIdx + 1) / Double(binCount) * Double(windowCount)))
            let clamped = min(endWin, windowCount)
            guard clamped > startWin else { continue }
            var low: Float = 0
            var mid: Float = 0
            var high: Float = 0
            for w in startWin..<clamped {
                low += fftLow[w]
                mid += fftMid[w]
                high += fftHigh[w]
            }
            let div = Float(clamped - startWin)
            let lowAvg = low / div
            let midAvg = mid / div
            let highAvg = high / div
            output[binIdx * 3 + 0] = lowAvg
            output[binIdx * 3 + 1] = midAvg
            output[binIdx * 3 + 2] = highAvg
            maxBand = max(maxBand, lowAvg, midAvg, highAvg)
        }

        if maxBand > 0 {
            var scale = 1.0 / maxBand
            vDSP_vsmul(output, 1, &scale, &output, 1, vDSP_Length(output.count))
        }

        return output
    }

    static func writeBands(_ bands: [Float], to url: URL) throws {
        try bands.withUnsafeBufferPointer { buf in
            let data = Data(buffer: buf)
            try data.write(to: url, options: .atomic)
        }
    }

    static func readBands(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        return data.withUnsafeBytes { raw -> [Float] in
            let floats = raw.bindMemory(to: Float.self)
            return Array(floats)
        }
    }

    private static func readMono(file: AVAudioFile) throws -> [Float] {
        let format = file.processingFormat
        let chunkFrames: AVAudioFrameCount = 32768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw NSError(domain: "BandExtractor", code: 1)
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
}
