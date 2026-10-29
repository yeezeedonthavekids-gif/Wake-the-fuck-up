import AVFoundation
import Foundation

/// Plays previews and WakeUp's own in-app alarm sound. Only one preview plays at a time.
/// This works while WakeUp is open or playing audio in the background; it can't keep running
/// after iOS suspends or quits the app. That's what the system alarm is for.
@MainActor
final class AudioEngine: ObservableObject {
    @Published private(set) var previewingID: String?
    @Published private(set) var isRinging = false
    @Published var lastError: String?

    private var previewPlayer: AVAudioPlayer?
    private var ringPlayer: AVAudioPlayer?
    private var keepAlivePlayer: AVAudioPlayer?
    private var previewStop: DispatchWorkItem?
    private var keepAliveWanted = false
    private var interruptionObserver: NSObjectProtocol?

    static let previewSeconds: TimeInterval = 8

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let ended = raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .ended
            Task { @MainActor in self?.interruptionChanged(ended: ended) }
        }
    }

    // MARK: Previews

    func togglePreview(_ sound: AlarmSound, volume: Double) {
        if previewingID == sound.id {
            stopPreview()
            return
        }
        stopPreview()
        guard !isRinging, activate(mixWithOthers: false), let player = makePlayer(sound) else { return }
        player.volume = Float(volume)
        player.play()
        previewPlayer = player
        previewingID = sound.id
        lastError = nil
        let stop = DispatchWorkItem { [weak self] in Task { @MainActor in self?.stopPreview() } }
        previewStop = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + min(player.duration, Self.previewSeconds), execute: stop)
    }

    func setPreviewVolume(_ volume: Double) { previewPlayer?.volume = Float(volume) }

    func stopPreview() {
        previewStop?.cancel()
        previewStop = nil
        previewPlayer?.stop()
        previewPlayer = nil
        previewingID = nil
        settle()
    }

    // MARK: Ringing

    /// Starts the looping in-app alarm sound. Falls back to Classic Bell if the chosen sound is missing.
    @discardableResult
    func startRinging(_ sound: AlarmSound, volume: Double, fadeIn: Int) -> Bool {
        stopPreview()
        guard activate(mixWithOthers: false),
              let player = makePlayer(sound) ?? makePlayer(SoundLibrary.builtIn[0]) else { return false }
        player.numberOfLoops = -1
        if fadeIn > 0 {
            player.volume = 0.05
            player.play()
            player.setVolume(Float(volume), fadeDuration: TimeInterval(fadeIn))
        } else {
            player.volume = Float(volume)
            player.play()
        }
        ringPlayer = player
        isRinging = true
        return true
    }

    func stopRinging() {
        ringPlayer?.stop()
        ringPlayer = nil
        isRinging = false
        settle()
    }

    // MARK: Fallback keep-awake

    /// Notification fallback only: loops silent audio so iOS keeps WakeUp running overnight and it
    /// can ring in full. Uses some battery, stops if the app is force-quit, and is off with AlarmKit.
    func setKeepAlive(_ on: Bool) {
        keepAliveWanted = on
        if on {
            if !isRinging && previewPlayer == nil { startKeepAlive() }
        } else {
            keepAlivePlayer?.stop()
            keepAlivePlayer = nil
            settle()
        }
    }

    var keepAliveActive: Bool { keepAlivePlayer?.isPlaying == true }

    private func startKeepAlive() {
        guard keepAlivePlayer?.isPlaying != true,
              let url = Bundle.main.url(forResource: "silence", withExtension: "wav"),
              activate(mixWithOthers: true),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = -1
        player.volume = 0
        player.play()
        keepAlivePlayer = player
    }

    // MARK: Session

    private func activate(mixWithOthers: Bool) -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: mixWithOthers ? [.mixWithOthers] : [])
            try session.setActive(true)
            return true
        } catch {
            lastError = "WakeUp couldn't start audio: \(error.localizedDescription)"
            return false
        }
    }

    private func makePlayer(_ sound: AlarmSound) -> AVAudioPlayer? {
        guard let url = SoundLibrary.url(for: sound) else {
            lastError = "The sound “\(sound.name)” is missing."
            return nil
        }
        do {
            return try AVAudioPlayer(contentsOf: url)
        } catch {
            lastError = "WakeUp couldn't open “\(sound.name)”: \(error.localizedDescription)"
            return nil
        }
    }

    /// Returns to the quiet state: silent keep-alive if wanted, otherwise releases the audio session.
    private func settle() {
        guard !isRinging, previewPlayer == nil else { return }
        if keepAliveWanted {
            startKeepAlive()
        } else {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func interruptionChanged(ended: Bool) {
        guard ended else { return }
        if isRinging {
            _ = activate(mixWithOthers: false)
            ringPlayer?.play()
        } else if keepAliveWanted {
            _ = activate(mixWithOthers: true)
            keepAlivePlayer?.play()
        }
    }
}
