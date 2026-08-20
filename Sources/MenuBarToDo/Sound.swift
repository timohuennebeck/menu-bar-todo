import AVFoundation
import AppKit

/// The "task done" chime: a short, bright two-note ding (G5 → D6) with a soft
/// harmonic tail, synthesized once and replayed from memory. No asset needed.
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

    /// Two partial-rich sine notes with a 6 ms attack and exponential decay,
    /// the second note starting 90 ms after the first.
    private static func renderChime(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let duration = 0.42
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        struct Note { let frequency: Double; let start: Double; let amplitude: Double }
        let notes = [
            Note(frequency: 783.99, start: 0.00, amplitude: 0.55),   // G5
            Note(frequency: 1174.66, start: 0.09, amplitude: 0.50)   // D6
        ]

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            var sample = 0.0
            for note in notes where t >= note.start {
                let lt = t - note.start
                let envelope = min(lt / 0.006, 1) * exp(-lt * 7.5)
                let phase = 2 * Double.pi * note.frequency * lt
                let tone = sin(phase) + 0.35 * sin(2 * phase) + 0.12 * sin(3 * phase)
                sample += note.amplitude * envelope * tone
            }
            channel[i] = Float(max(-1, min(1, sample * 0.6)))
        }
        return buffer
    }
}
