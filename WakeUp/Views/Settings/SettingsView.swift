import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var browsingChallenges = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    NavigationLink { AppearanceSettingsView() } label: {
                        Label("Theme, colors and home screen", systemImage: "paintpalette")
                    }
                }
                Section("Alarm") {
                    Button { editing = true } label: { Label("Edit alarm", systemImage: "alarm") }
                    Button {
                        dismiss()
                        model.showTestSheet = true
                    } label: { Label("Test alarm", systemImage: "play.circle") }
                }
                Section {
                    NavigationLink { PlanEditorView(config: $model.data.alarm) } label: {
                        LabeledContent { Text(model.data.alarm.planSummary).lineLimit(1) } label: { Label("Challenge plan", systemImage: "flag.checkered") }
                    }
                    NavigationLink { ItemLibraryView() } label: { Label("Item library", systemImage: "shippingbox") }
                    NavigationLink { QRDestinationsView() } label: { Label("QR destinations", systemImage: "qrcode") }
                    Button { browsingChallenges = true } label: { Label("Try any challenge", systemImage: "testtube.2") }
                    LabeledContent { Text(CameraAccess.description) } label: { Label("Camera", systemImage: "camera") }
                } header: {
                    Text("Challenges")
                } footer: {
                    Text("Camera access is only requested when a challenge needs it.")
                }
                Section("General") {
                    NavigationLink { GeneralSettingsView() } label: { Label("Name, time format, haptics", systemImage: "person.crop.circle") }
                    NavigationLink { TutorialReaderView() } label: { Label("Full tutorial", systemImage: "book") }
                    Button {
                        dismiss()
                        model.replayOnboarding()
                    } label: { Label("Replay setup", systemImage: "arrow.counterclockwise") }
                }
                Section("Privacy and data") {
                    NavigationLink { PrivacySettingsView() } label: { Label("Privacy, history and data", systemImage: "hand.raised") }
                }
                Section("Diagnostics") {
                    NavigationLink { DiagnosticsView() } label: { Label("Alarm status and checks", systemImage: "stethoscope") }
                }
                Section {
                    LabeledContent("Version", value: AppInfo.version)
                    Text("WakeUp is free. No ads, accounts, subscriptions or tracking. It works offline and makes no network requests.")
                        .font(.footnote).foregroundStyle(Palette.text2)
                    Text("All 14 built-in sounds are synthesized by WakeUp's own build script and released under CC0.")
                        .font(.footnote).foregroundStyle(Palette.text2)
                } header: {
                    Text("About")
                }
            }
            .wakeForm()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $editing) { AlarmEditorView() }
            .sheet(isPresented: $browsingChallenges) { ChallengeLibraryView() }
        }
    }
}

enum AppInfo {
    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var newItem = ""

    var body: some View {
        Form {
            Section { AppearanceControls().padding(.vertical, 6) }
            Section {
                Picker("Animations", selection: $model.data.prefs.motion) {
                    ForEach(MotionPreference.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                Text("Reduced turns off sliding and springy animations. Match iPhone follows Reduce Motion in Accessibility settings.")
            }
            Section {
                Toggle("Show widgets under the alarm", isOn: $model.data.prefs.showDashboard)
                if model.data.prefs.showDashboard {
                    Toggle("Clock", isOn: $model.data.prefs.showClock)
                    Toggle("Morning message", isOn: $model.data.prefs.showMessage)
                    Toggle("Morning checklist", isOn: $model.data.prefs.showChecklist)
                    Toggle("Recent mornings", isOn: $model.data.prefs.showHistory)
                }
            } header: {
                Text("Home screen")
            } footer: {
                Text("The alarm always stays at the top. Widgets are optional extras.")
            }
            if model.data.prefs.showDashboard && model.data.prefs.showChecklist {
                Section("Checklist items") {
                    ForEach($model.data.prefs.checklist) { $item in
                        TextField("Item", text: $item.title)
                    }
                    .onDelete { model.data.prefs.checklist.remove(atOffsets: $0) }
                    HStack {
                        TextField("New item", text: $newItem)
                        Button("Add") {
                            let title = newItem.trimmingCharacters(in: .whitespaces)
                            guard !title.isEmpty else { return }
                            model.data.prefs.checklist.append(ChecklistItem(title: String(title.prefix(80))))
                            newItem = ""
                        }
                        .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty || model.data.prefs.checklist.count >= 20)
                    }
                }
            }
        }
        .wakeForm()
        .navigationTitle("Appearance")
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var scheduler: SchedulerService
    @State private var notificationStatus = "…"

    var body: some View {
        Form {
            Section("You") {
                TextField("Name (optional)", text: $model.data.prefs.name)
                Toggle("Personal greeting", isOn: $model.data.prefs.greetingEnabled)
                Text(Greeting.text(name: model.data.prefs.name, enabled: model.data.prefs.greetingEnabled))
                    .font(.system(.body, design: .serif)).foregroundStyle(Palette.text2)
            }
            Section("Time") {
                Picker("Time format", selection: $model.data.prefs.timeFormat) {
                    ForEach(TimeFormat.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Feedback") {
                Toggle("Haptics", isOn: $model.data.prefs.haptics)
            }
            Section {
                LabeledContent("Notifications", value: notificationStatus)
                Button("Open iPhone Settings") { SystemSettings.open() }
                Toggle("Keep WakeUp awake overnight", isOn: $model.data.prefs.keepAwakeInFallback)
                    .onChange(of: model.data.prefs.keepAwakeInFallback) { _, _ in Task { await model.reschedule() } }
            } header: {
                Text("Notifications")
            } footer: {
                Text((scheduler.alarmKitAvailable
                     ? "On iOS 26 WakeUp uses system alarms. Notifications are only a backup."
                     : "Before iOS 26, WakeUp rings through notifications.")
                     + " When iOS won't schedule a system alarm, keeping WakeUp awake plays silent audio overnight so it can ring by itself. It uses some battery and stops if you swipe WakeUp away.")
            }
        }
        .wakeForm()
        .navigationTitle("General")
        .task { notificationStatus = await scheduler.notificationPermissionDescription() }
    }
}

struct SettingsFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct PrivacySettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var exportFile: SettingsFile? = nil
    @State private var exporting = false
    @State private var importing = false
    @State private var confirmingErase = false
    @State private var confirmingHistory = false
    @State private var message: String? = nil

    var body: some View {
        Form {
            Section("How WakeUp handles your data") {
                Text("Everything stays on this iPhone in WakeUp's own storage: your settings, item photos, imported sound and (if you turn it on) history. WakeUp has no servers, accounts, analytics or ads, and makes no network requests.")
                    .font(.subheadline)
                Text("The camera is only used during challenges that need it. Frames are analyzed on this iPhone and discarded. Photos for “Photo check” are never saved; reference photos you add to the item library are stored locally.")
                    .font(.subheadline)
            }
            Section {
                Toggle("Keep wake-up history", isOn: $model.data.prefs.historyEnabled)
                NavigationLink("View history (\(model.data.history.count))") { HistoryListView() }
                Button("Delete history", role: .destructive) { confirmingHistory = true }
                    .disabled(model.data.history.isEmpty)
            } header: {
                Text("History")
            } footer: {
                Text("History stores the date, outcome, snooze count and time taken. Nothing else.")
            }
            Section {
                Button("Export settings") {
                    do {
                        exportFile = SettingsFile(data: try model.exportSettings())
                        exporting = true
                    } catch {
                        message = "Export failed: \(error.localizedDescription)"
                    }
                }
                Button("Import settings") { importing = true }
                if let message { Text(message).font(.footnote).foregroundStyle(Palette.text2) }
            } header: {
                Text("Settings file")
            } footer: {
                Text("Exports your alarm, challenges, appearance, item names and QR destinations as a JSON file. Photos and history aren't included. Imported files are checked and every value is kept within its normal range.")
            }
            Section {
                Button("Erase all WakeUp data", role: .destructive) { confirmingErase = true }
            } footer: {
                Text("Deletes settings, history, item photos and your imported sound, and cancels the alarm. Setup starts again.")
            }
        }
        .wakeForm()
        .navigationTitle("Privacy")
        .fileExporter(isPresented: $exporting, document: exportFile, contentType: .json, defaultFilename: "WakeUp Settings") { result in
            if case .failure(let error) = result { message = "Export failed: \(error.localizedDescription)" } else { message = "Settings exported." }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    try model.importSettings(try Data(contentsOf: url))
                    message = "Settings imported."
                } catch {
                    message = error.localizedDescription
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .confirmationDialog("Delete all wake-up history?", isPresented: $confirmingHistory, titleVisibility: .visible) {
            Button("Delete history", role: .destructive) { model.data.history = [] }
        }
        .confirmationDialog("Erase everything WakeUp has stored?", isPresented: $confirmingErase, titleVisibility: .visible) {
            Button("Erase all data", role: .destructive) { model.eraseEverything() }
        } message: {
            Text("This can't be undone.")
        }
    }
}

struct HistoryListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            if model.data.history.isEmpty {
                Text(model.data.prefs.historyEnabled ? "No mornings recorded yet." : "History is off.").foregroundStyle(Palette.text3)
            }
            ForEach(model.data.history.reversed()) { record in HistoryRow(record: record) }
        }
        .wakeForm()
        .navigationTitle("History")
    }
}

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var scheduler: SchedulerService
    @EnvironmentObject private var audio: AudioEngine
    @State private var alarmPermission = "…"
    @State private var notificationPermission = "…"
    @State private var checking = false

    var body: some View {
        let diagnostics = model.data.diagnostics
        Form {
            Section("Scheduling") {
                LabeledContent("Status", value: statusText)
                LabeledContent("Method", value: BackendKind(rawValue: diagnostics.backend)?.title ?? "Not checked yet")
                if let next = model.data.expectedFire {
                    LabeledContent("Next ring", value: TimeText.dayAndTime(next, format: model.data.prefs.timeFormat))
                }
                LabeledContent("Last check", value: stamp(diagnostics.lastCheck))
                LabeledContent("Last successful schedule", value: stamp(diagnostics.lastSuccess))
                if let error = diagnostics.lastError {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last error").font(.subheadline.weight(.semibold))
                        Text(error).font(.footnote).foregroundStyle(Palette.bad)
                    }
                }
                Button(checking ? "Checking…" : "Verify with iOS now") {
                    checking = true
                    Task {
                        await model.reschedule()
                        await refresh()
                        checking = false
                    }
                }
                .disabled(checking)
            }
            Section("Permissions") {
                LabeledContent("System alarms", value: alarmPermission)
                LabeledContent("Notifications", value: notificationPermission)
                LabeledContent("Camera", value: CameraAccess.description)
                Button("Open iPhone Settings") { SystemSettings.open() }
            }
            Section {
                Button(audio.previewingID == nil ? "Play “\(model.currentSound.name)”" : "Stop") {
                    audio.togglePreview(model.currentSound, volume: model.data.alarm.volume)
                }
                if let error = audio.lastError { Text(error).font(.footnote).foregroundStyle(Palette.bad) }
                LabeledContent("Sound file", value: SoundLibrary.url(for: model.currentSound) == nil ? "Missing" : "Found")
            } header: {
                Text("Audio")
            } footer: {
                Text("If you hear nothing, check the volume buttons. Previews follow the ring/silent switch only through the system volume.")
            }
            Section("This device") {
                LabeledContent("iOS", value: UIDevice.current.systemVersion)
                LabeledContent("System alarms (AlarmKit)", value: scheduler.alarmKitAvailable ? "Available" : "Needs iOS 26")
                LabeledContent("Face ID camera", value: EyeTracking.isSupported ? "Yes" : "No")
                LabeledContent("Fallback keep-awake", value: audio.keepAliveActive ? "Running" : "Off")
                LabeledContent("WakeUp", value: AppInfo.version)
            }
            Section("What iOS doesn't allow") {
                Text("• Nothing rings if the iPhone is off or the battery is empty.\n• The system alarm always shows iOS's own Stop control.\n• Apps can't change the system volume.\n• Notification sounds play once, for up to 30 seconds, and stay silent in silent mode.\n• WakeUp can't run code in the background indefinitely; challenges run while it's open.")
                    .font(.footnote)
            }
        }
        .wakeForm()
        .navigationTitle("Diagnostics")
        .task { await refresh() }
    }

    private var statusText: String {
        switch scheduler.status {
        case .off: model.data.alarm.enabled ? "Not scheduled" : "Alarm is off"
        case .checking: "Checking…"
        case .scheduled(let next, _): "Scheduled for \(TimeText.dayAndTime(next, format: model.data.prefs.timeFormat))"
        case .inAppOnly(let next, _): "WakeUp rings by itself at \(TimeText.dayAndTime(next, format: model.data.prefs.timeFormat))"
        case .needsPermission: "Needs permission"
        case .failed: "Failed"
        }
    }

    private func stamp(_ date: Date?) -> String {
        date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never"
    }

    private func refresh() async {
        alarmPermission = await scheduler.alarmPermissionDescription()
        notificationPermission = await scheduler.notificationPermissionDescription()
    }
}
