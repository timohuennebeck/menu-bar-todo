import AVFoundation
import AppKit

/// The "task done" sound: two wet "bloops" a fifth apart ("bu-dup"), each a sine
/// whose pitch glides up as it decays, synthesized once and replayed from memory.
/// No asset needed.
final class CompletionSound {
    static let shared = CompletionSound()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let buffer: AVAudioPCMBuffer?

    private init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        engine.attach(player)
        if let format {
            engine.connect(player, to: engine.mainMixerNode, format: format)
            buffer = CompletionSound.renderChime(format: format)
            if buffer == nil { NSLog("MenuBarToDo: could not render the chime; using the system sound") }
        } else {
            buffer = nil
            NSLog("MenuBarToDo: could not create the audio format; using the system sound")
        }
        engine.prepare()
        // An output-device change (headphones, AirPods, docking) tears the graph
        // down while isRunning can still read true; stop the engine so the next
        // play() restarts it against the new configuration instead of scheduling
        // into a dead player forever.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                               object: engine, queue: .main) { [engine] _ in
            engine.stop()
        }
    }

    func play() {
        guard let buffer else { playFallback(); return }
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            NSLog("MenuBarToDo: could not start the audio engine (\(error)); using the system sound")
            playFallback()
            return
        }
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    private func playFallback() {
        let sound = NSSound(named: "Glass")
        if sound?.play() != true {
            NSLog("MenuBarToDo: completion-sound fallback failed (NSSound 'Glass' \(sound == nil ? "missing" : "did not play"))")
        }
    }

    /// Two bloops 110 ms apart (180 → 720 Hz, then 270 → 1080 Hz): each a sine plus a
    /// touch of second harmonic whose pitch glides up over ~30 ms while the level
    /// decays, with a 4 ms attack. Normalized and soft-clipped to a fixed peak.
    private static func renderChime(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let duration = 0.42
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        struct Bloop { let baseFrequency: Double; let start: Double }
        let bloops = [Bloop(baseFrequency: 180, start: 0.0), Bloop(baseFrequency: 270, start: 0.11)]
        var phases = [Double](repeating: 0, count: bloops.count)
        var samples = [Double](repeating: 0, count: Int(frameCount))

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            var sample = 0.0
            for (k, bloop) in bloops.enumerated() where t >= bloop.start {
                let lt = t - bloop.start
                let frequency = bloop.baseFrequency + 3 * bloop.baseFrequency * (1 - exp(-lt / 0.03))
                phases[k] += 2 * Double.pi * frequency / sampleRate
                let envelope = min(lt / 0.004, 1) * exp(-lt * 13)
                sample += envelope * (sin(phases[k]) + 0.25 * sin(2 * phases[k]))
            }
            samples[i] = sample
        }
        let peak = samples.map(abs).max() ?? 1
        for i in 0..<Int(frameCount) {
            channel[i] = Float(tanh(samples[i] / peak * 0.9)) * 0.8
        }
        return buffer
    }
}
