import SwiftUI
import UniformTypeIdentifiers

extension TimeFormat {
    /// Locale used for time pickers so they follow the chosen 12- or 24-hour format.
    var pickerLocale: Locale {
        switch self {
        case .system: .current
        case .twelve: Locale(identifier: "en_US")
        case .twentyFour: Locale(identifier: "en_GB")
        }
    }
}

/// Edits a copy of the alarm. Nothing changes until Save.
struct AlarmEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = AlarmConfig()
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TimePickerRow(hour: $draft.hour, minute: $draft.minute)
                    Toggle("Alarm on", isOn: $draft.enabled)
                } footer: {
                    if model.ringing != nil {
                        Text("Changes apply from the next alarm. The one ringing now keeps its current plan.")
                    }
                }
                Section("Repeat") {
                    DayPicker(days: $draft.repeatDays)
                }
                Section {
                    NavigationLink {
                        SoundPickerView(soundID: $draft.soundID, volume: $draft.volume)
                    } label: {
                        LabeledContent("Sound", value: model.sound(id: draft.soundID).name)
                    }
                    Picker("Fade in", selection: $draft.fadeInSeconds) {
                        Text("Off").tag(0)
                        Text("10 seconds").tag(10)
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                    }
                } header: {
                    Text("Sound")
                } footer: {
                    Text("Volume and fade-in apply when WakeUp plays the alarm itself. The system alarm plays your chosen sound at the iPhone's alarm volume.")
                }
                Section {
                    NavigationLink {
                        PlanEditorView(config: $draft)
                    } label: {
                        LabeledContent("Challenge", value: draft.planSummary)
                    }
                    Toggle("Finish challenge to stop", isOn: $draft.requireChallenge)
                    Stepper("Emergency stop: hold \(draft.emergencyHoldSeconds) s", value: $draft.emergencyHoldSeconds, in: 2...10)
                } header: {
                    Text("Wake-up challenge")
                } footer: {
                    Text("When on, WakeUp's own screen only stops after the challenge, or with the emergency stop. iOS always shows its own Stop control on the system alarm, which WakeUp can't remove.")
                }
                SnoozeSection(snooze: $draft.snooze)
            }
            .wakeForm()
            .navigationTitle("Edit alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let saved = draft
                        model.updateAlarm(requestPermission: saved.enabled) { $0 = saved }
                        Haptics.success()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if !loaded {
                    draft = model.data.alarm
                    loaded = true
                }
            }
        }
    }
}

struct TimePickerRow: View {
    @EnvironmentObject private var model: AppModel
    @Binding var hour: Int
    @Binding var minute: Int

    var body: some View {
        DatePicker("Time", selection: Binding(
            get: { Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                hour = parts.hour ?? hour
                minute = parts.minute ?? minute
            }
        ), displayedComponents: .hourAndMinute)
        .datePickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .environment(\.locale, model.data.prefs.timeFormat.pickerLocale)
    }
}

struct DayPicker: View {
    @Environment(\.theme) private var theme
    @Binding var days: Set<Weekday>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout {
                Chip(title: "Once", selected: days.isEmpty) { days = [] }
                Chip(title: "Every day", selected: days == Weekday.everyDay) { days = Weekday.everyDay }
                Chip(title: "Weekdays", selected: days == Weekday.weekdays) { days = Weekday.weekdays }
                Chip(title: "Weekends", selected: days == Weekday.weekend) { days = Weekday.weekend }
            }
            HStack(spacing: 6) {
                ForEach(Weekday.ordered) { day in
                    let on = days.contains(day)
                    Button {
                        Haptics.tap()
                        if on { days.remove(day) } else { days.insert(day) }
                    } label: {
                        Text(day.initial)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(on ? theme.accentInk : Palette.text2)
                            .background(on ? theme.accent : Palette.raised, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.fullName)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text(days.isEmpty ? "Rings once, then turns itself off." : "Repeats: \(Weekday.summary(days))")
                .font(.footnote).foregroundStyle(Palette.text3)
        }
        .padding(.vertical, 4)
    }
}

struct SnoozeSection: View {
    @Binding var snooze: SnoozeConfig

    var body: some View {
        Section {
            Toggle("Allow snooze", isOn: $snooze.enabled)
            if snooze.enabled {
                Stepper("\(snooze.minutes) minutes", value: $snooze.minutes, in: 1...30)
                Stepper("Up to \(snooze.maxCount) snooze\(snooze.maxCount == 1 ? "" : "s")", value: $snooze.maxCount, in: 1...10)
                Picker("Available", selection: $snooze.availability) {
                    ForEach(SnoozeAvailability.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Snoozing restarts the challenge", isOn: $snooze.resetsProgress)
            }
        } header: {
            Text("Snooze")
        } footer: {
            Text("Snooze schedules one extra alarm. With the system alarm it rings even if WakeUp is closed. iOS's own lock-screen controls may differ.")
        }
    }
}

struct SoundPickerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var audio: AudioEngine
    @Binding var soundID: String
    @Binding var volume: Double
    @State private var importing = false
    @State private var importError: String? = nil

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(Palette.text3)
                    Slider(value: $volume, in: 0.1...1) { Text("Volume") }
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(Palette.text3)
                }
                .onChange(of: volume) { _, value in audio.setPreviewVolume(value) }
            } header: {
                Text("WakeUp volume")
            } footer: {
                Text("Scaled by your iPhone's volume. iOS doesn't let apps change the system volume.")
            }
            if let error = audio.lastError ?? importError {
                Section { Banner(text: error, symbol: "exclamationmark.triangle.fill", tint: Palette.warn) }
            }
            Section("Built-in sounds") {
                ForEach(SoundLibrary.builtIn) { sound in
                    SoundRow(sound: sound, selected: soundID == sound.id, volume: volume) { soundID = sound.id }
                }
            }
            Section {
                if let custom = model.data.customSound {
                    let sound = model.sound(id: SoundLibrary.customID)
                    SoundRow(sound: sound, selected: soundID == SoundLibrary.customID, volume: volume) { soundID = SoundLibrary.customID }
                    Button("Remove “\(custom.name)”", role: .destructive) {
                        if soundID == SoundLibrary.customID { soundID = SoundLibrary.builtIn[0].id }
                        model.removeCustomSound()
                    }
                }
                Button(model.data.customSound == nil ? "Import a sound…" : "Replace with another sound…") { importing = true }
            } header: {
                Text("Custom sound")
            } footer: {
                Text("WakeUp keeps the first 29 seconds: iOS only plays alarm sounds up to 30 seconds long. MP3, M4A, WAV, AIFF and CAF files work. Only import sounds you have the right to use.")
            }
        }
        .wakeForm()
        .navigationTitle("Sound")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url):
                do {
                    try model.importSound(from: url)
                    soundID = SoundLibrary.customID
                    importError = nil
                } catch {
                    importError = error.localizedDescription
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .onDisappear { audio.stopPreview() }
    }
}

struct SoundRow: View {
    @EnvironmentObject private var audio: AudioEngine
    @Environment(\.theme) private var theme
    let sound: AlarmSound
    let selected: Bool
    let volume: Double
    let select: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                audio.togglePreview(sound, volume: volume)
            } label: {
                Image(systemName: audio.previewingID == sound.id ? "stop.fill" : "play.fill")
                    .font(.body)
                    .foregroundStyle(theme.accent)
                    .frame(width: 40, height: 40)
                    .background(theme.accent.opacity(0.14), in: Circle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(audio.previewingID == sound.id ? "Stop preview" : "Preview \(sound.name)")
            Button(action: select) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sound.name).foregroundStyle(Palette.text1)
                        Text(sound.detail).font(.footnote).foregroundStyle(Palette.text2)
                        if let seconds = SoundLibrary.duration(of: sound) {
                            Text("\(Int(seconds.rounded())) seconds, loops").font(.caption).foregroundStyle(Palette.text3)
                        } else {
                            Text("File missing").font(.caption).foregroundStyle(Palette.bad)
                        }
                    }
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(theme.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}
