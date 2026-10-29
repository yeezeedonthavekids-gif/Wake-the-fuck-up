import AVFoundation
import Foundation

struct AlarmSound: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let fileName: String
    var isCustom = false
}

enum SoundError: LocalizedError {
    case unreadable, empty

    var errorDescription: String? {
        switch self {
        case .unreadable: "WakeUp couldn't read that audio file. Try an MP3, M4A, WAV, AIFF or CAF file."
        case .empty: "That audio file has no sound in it."
        }
    }
}

/// The 14 built-in sounds (synthesized by scripts/gen_sounds.py, CC0) plus one imported sound.
enum SoundLibrary {
    static let customID = "custom"
    /// iOS only plays alarm and notification sounds up to 30 seconds long.
    static let maxCustomSeconds: Double = 29

    static let builtIn: [AlarmSound] = [
        sound("classic-bell", "Classic Bell", "Bright two-tone bell strikes."),
        sound("digital-beep", "Digital Beep", "Four steady beeps, then a pause."),
        sound("double-beep", "Double Beep", "Quick pairs of high beeps."),
        sound("retro-alarm", "Retro Alarm Clock", "A hammer rattling between two bells."),
        sound("gentle-chimes", "Gentle Chimes", "Soft chimes that slowly get louder."),
        sound("morning-birds", "Morning Birds", "Synthesized birdsong chirps."),
        sound("rain-chimes", "Rain and Chimes", "Soft rain noise with occasional chimes."),
        sound("rising-tones", "Rising Tones", "Sweeping tones that climb in pitch and volume."),
        sound("synth-pulse", "Synth Pulse", "A bouncing synthesizer arpeggio."),
        sound("urgent-buzzer", "Urgent Buzzer", "A low, insistent buzz."),
        sound("fast-digital", "Fast Digital Alarm", "Rapid bursts of high beeps."),
        sound("deep-bell", "Deep Bell", "A low bell with a long ring."),
        sound("soft-piano", "Soft Piano", "Calm broken chords on a piano-like tone."),
        sound("rising-beeps", "Rising Beeps", "Beeps that speed up and get louder."),
    ]

    private static func sound(_ id: String, _ name: String, _ detail: String) -> AlarmSound {
        AlarmSound(id: id, name: name, detail: detail, fileName: "\(id).wav")
    }

    static func sound(id: String, custom: CustomSound?) -> AlarmSound {
        if id == customID, let custom {
            return AlarmSound(id: customID, name: custom.name, detail: "Your imported sound.", fileName: custom.file, isCustom: true)
        }
        return builtIn.first { $0.id == id } ?? builtIn[0]
    }

    /// Imported sounds live in Library/Sounds, where iOS looks for notification and alarm sounds.
    static var soundsDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Sounds", isDirectory: true)
    }

    static func url(for sound: AlarmSound) -> URL? {
        if sound.isCustom {
            let url = soundsDirectory.appendingPathComponent(sound.fileName)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return Bundle.main.url(forResource: sound.id, withExtension: "wav")
    }

    private static var durations: [String: TimeInterval] = [:]

    static func duration(of sound: AlarmSound) -> TimeInterval? {
        if let cached = durations[sound.fileName] { return cached }
        guard let url = url(for: sound), let file = try? AVAudioFile(forReading: url) else { return nil }
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        durations[sound.fileName] = seconds
        return seconds
    }

    /// Copies the first 29 seconds of an audio file into Library/Sounds as 16-bit PCM CAF.
    static func importCustom(from source: URL, name: String) throws -> CustomSound {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let input: AVAudioFile
        do { input = try AVAudioFile(forReading: source) } catch { throw SoundError.unreadable }
        let format = input.processingFormat
        let frames = AVAudioFrameCount(min(Double(input.length), format.sampleRate * maxCustomSeconds))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { throw SoundError.empty }
        do { try input.read(into: buffer, frameCount: frames) } catch { throw SoundError.unreadable }

        try FileManager.default.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
        let file = "custom-\(UUID().uuidString.prefix(8)).caf"
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let output = try AVAudioFile(forWriting: soundsDirectory.appendingPathComponent(file), settings: settings,
                                     commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        try output.write(from: buffer)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return CustomSound(name: trimmed.isEmpty ? "My sound" : String(trimmed.prefix(40)), file: file)
    }

    static func removeCustom(_ sound: CustomSound) {
        try? FileManager.default.removeItem(at: soundsDirectory.appendingPathComponent(sound.file))
    }
}
