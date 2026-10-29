import SwiftUI

enum OnboardingPage: Hashable {
    case welcome
    case tutorial(Int)
    case look, timeFormat, wakeTime, sound, challenge, difficulty, snooze, dismissal, haptics, permissions, demo, review

    static let all: [OnboardingPage] = [.welcome]
        + TutorialContent.pages.map { .tutorial($0.id) }
        + [.look, .timeFormat, .wakeTime, .sound, .challenge, .difficulty, .snooze, .dismissal, .haptics, .permissions, .demo, .review]

    static var firstWizardIndex: Int { all.firstIndex(of: .look)! }
    static var reviewIndex: Int { all.firstIndex(of: .review)! }

    var isTutorial: Bool {
        if case .tutorial = self { return true }
        return false
    }

    var section: String {
        switch self {
        case .welcome: "Welcome"
        case .tutorial: "How it works"
        case .demo: "Try it"
        case .review: "All set"
        default: "Make it yours"
        }
    }
}

/// First-run setup. Progress is saved, so leaving and coming back resumes on the same page.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    private var pages: [OnboardingPage] { OnboardingPage.all }
    private var index: Int { model.data.onboardingStep.clamped(to: 0...(pages.count - 1)) }
    private var page: OnboardingPage { pages[index] }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if index > 0 {
                    Button { go(index - 1) } label: { Label("Back", systemImage: "chevron.left") }
                } else {
                    Color.clear.frame(width: 60, height: 1)
                }
                Spacer()
                Text(page.section).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text2)
                Spacer()
                skipButton
            }
            .font(.body.weight(.medium))
            .padding(.horizontal, 16)
            .frame(minHeight: 48)

            ProgressView(value: Double(index + 1), total: Double(pages.count))
                .tint(theme.accent)
                .padding(.horizontal, 16)
                .accessibilityLabel("Setup progress")
                .accessibilityValue("Page \(index + 1) of \(pages.count)")

            ScrollView {
                pageContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .id(index)
            .transition(theme.reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))

            if page != .review {
                Button(index == 0 ? "Get started" : "Next") { go(index + 1) }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .background(AppBackground())
    }

    @ViewBuilder private var skipButton: some View {
        if page.isTutorial {
            Button("Skip tutorial") { go(OnboardingPage.firstWizardIndex) }
        } else if page == .welcome {
            Button("Skip setup") { go(OnboardingPage.reviewIndex) }
        } else if page != .review {
            Button("Skip") { go(index + 1) }
        } else {
            Color.clear.frame(width: 60, height: 1)
        }
    }

    private func go(_ newIndex: Int) {
        Haptics.tap()
        withAnimation(theme.animation()) { model.data.onboardingStep = newIndex.clamped(to: 0...(pages.count - 1)) }
    }

    @ViewBuilder private var pageContent: some View {
        switch page {
        case .welcome: WelcomePage()
        case .tutorial(let i): TutorialPageView(page: TutorialContent.pages[i], number: i + 1, total: TutorialContent.pages.count)
        case .look: LookPage()
        case .timeFormat: TimeFormatPage()
        case .wakeTime: WakeTimePage()
        case .sound: SoundPage()
        case .challenge: ChallengePage()
        case .difficulty: DifficultyPage()
        case .snooze: SnoozePage()
        case .dismissal: DismissalPage()
        case .haptics: HapticsPage()
        case .permissions: PermissionsPage()
        case .demo: DemoPage()
        case .review: ReviewPage(go: go)
        }
    }
}

// MARK: - Pages

private struct PageHeader: View {
    let kicker: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker(text: kicker)
            Headline(text: title)
            Text(detail).foregroundStyle(Palette.text2)
        }
    }
}

private struct WelcomePage: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 54))
                .foregroundStyle(theme.accent)
                .frame(width: 100, height: 100)
                .background(theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .accessibilityHidden(true)
            Headline(text: "Welcome to WakeUp")
            Text("One alarm, and one wake-up plan. Instead of tapping Stop half asleep, you finish a small challenge you choose, so your morning actually starts.")
                .foregroundStyle(Palette.text2)
            Text("WakeUp is free, works offline, and keeps everything on your iPhone. No account, no ads.")
                .font(.subheadline).foregroundStyle(Palette.text3)
            Card {
                Kicker(text: "What should we call you?")
                TextField("Your name (optional)", text: $model.data.prefs.name)
                    .textContentType(.givenName)
                    .inputField()
                Toggle("Personal greeting", isOn: $model.data.prefs.greetingEnabled).tint(theme.accent)
                Text(Greeting.text(name: model.data.prefs.name, enabled: model.data.prefs.greetingEnabled))
                    .font(.system(.title2, design: .serif))
                    .foregroundStyle(Palette.text1)
                    .accessibilityLabel("Preview: \(Greeting.text(name: model.data.prefs.name, enabled: model.data.prefs.greetingEnabled))")
            }
        }
    }
}

struct LookPage: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(kicker: "Theme", title: "Pick a look", detail: "Change any of this later in Settings → Appearance.")
            AppearanceControls()
            Card {
                Kicker(text: "Preview")
                Text(TimeText.string(hour: model.data.alarm.hour, minute: model.data.alarm.minute, format: model.data.prefs.timeFormat))
                    .font(.system(size: 48, design: .serif))
                    .foregroundStyle(Palette.text1)
                Button("Edit alarm") {}.buttonStyle(PrimaryButtonStyle()).allowsHitTesting(false)
            }
        }
    }
}

/// Shared with Settings → Appearance.
struct AppearanceControls: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Kicker(text: "Theme")
            FlowLayout {
                ForEach(ThemeMode.allCases) { mode in
                    Chip(title: mode.title, selected: model.data.prefs.theme == mode) { model.data.prefs.theme = mode }
                }
            }
            Kicker(text: "Accent color")
            FlowLayout(spacing: 10) {
                ForEach(AccentChoice.allCases) { accent in
                    let selected = model.data.prefs.accent == accent
                    Button {
                        Haptics.tap()
                        model.data.prefs.accent = accent
                    } label: {
                        Circle()
                            .fill(accent.color)
                            .frame(width: 40, height: 40)
                            .overlay(Circle().strokeBorder(Palette.text1, lineWidth: selected ? 3 : 0).padding(-4))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accent.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Kicker(text: "Background")
            FlowLayout {
                ForEach(BackgroundChoice.allCases) { choice in
                    Chip(title: choice.title, selected: model.data.prefs.background == choice) { model.data.prefs.background = choice }
                }
            }
            Toggle("Soft gradients", isOn: $model.data.prefs.gradientsEnabled).tint(theme.accent)
            Kicker(text: "Corners")
            FlowLayout {
                ForEach(ShapeChoice.allCases) { shape in
                    Chip(title: shape.title, selected: model.data.prefs.shape == shape) { model.data.prefs.shape = shape }
                }
            }
            Kicker(text: "Spacing")
            FlowLayout {
                ForEach(Density.allCases) { density in
                    Chip(title: density.title, selected: model.data.prefs.density == density) { model.data.prefs.density = density }
                }
            }
        }
    }
}

private struct TimeFormatPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(kicker: "Time format", title: "12 or 24 hours?", detail: "Match iPhone follows your region settings.")
            FlowLayout {
                ForEach(TimeFormat.allCases) { format in
                    Chip(title: format.title, selected: model.data.prefs.timeFormat == format) { model.data.prefs.timeFormat = format }
                }
            }
            Card {
                Kicker(text: "Preview")
                Text(TimeText.string(hour: 6, minute: 45, format: model.data.prefs.timeFormat))
                    .font(.system(size: 48, design: .serif)).foregroundStyle(Palette.text1)
                Text(TimeText.string(hour: 19, minute: 30, format: model.data.prefs.timeFormat))
                    .font(.system(.title2, design: .serif)).foregroundStyle(Palette.text2)
            }
        }
    }
}

private struct WakeTimePage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(kicker: "Wake-up time", title: "When do you want to get up?", detail: "You'll switch the alarm on at the end of setup.")
            Card {
                TimePickerRow(hour: $model.data.alarm.hour, minute: $model.data.alarm.minute)
            }
            Card {
                Kicker(text: "Repeat")
                DayPicker(days: $model.data.alarm.repeatDays)
            }
            if let next = AlarmMath.nextFire(model.data.alarm) {
                Text("It would next ring \(TimeText.dayAndTime(next, format: model.data.prefs.timeFormat)), in \(AlarmMath.countdown(from: Date(), to: next)).")
                    .font(.subheadline).foregroundStyle(Palette.text2)
            }
        }
    }
}

private struct SoundPage: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var audio: AudioEngine
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(kicker: "Alarm sound", title: "Choose your sound", detail: "Tap play to hear each one. They're built in and work offline.")
            Card(padding: 12) {
                ForEach(SoundLibrary.builtIn) { sound in
                    SoundRow(sound: sound, selected: model.data.alarm.soundID == sound.id, volume: model.data.alarm.volume) {
                        model.data.alarm.soundID = sound.id
                    }
                    if sound.id != SoundLibrary.builtIn.last?.id { Divider() }
                }
            }
            Card {
                Kicker(text: "WakeUp volume")
                Slider(value: $model.data.alarm.volume, in: 0.1...1).tint(theme.accent)
                    .onChange(of: model.data.alarm.volume) { _, value in audio.setPreviewVolume(value) }
                Kicker(text: "Fade in")
                FlowLayout {
                    ForEach([0, 10, 30, 60], id: \.self) { seconds in
                        Chip(title: seconds == 0 ? "Off" : "\(seconds) s", selected: model.data.alarm.fadeInSeconds == seconds) {
                            model.data.alarm.fadeInSeconds = seconds
                        }
                    }
                }
                Text("Volume and fade-in apply when WakeUp plays the alarm itself. iOS doesn't let apps set the system volume.")
                    .font(.footnote).foregroundStyle(Palette.text3)
            }
        }
        .onDisappear { audio.stopPreview() }
    }
}

private struct ChallengePage: View {
    @EnvironmentObject private var model: AppModel

    private var selectedKind: ChallengeKind? { model.data.alarm.steps.first?.kind }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(kicker: "Challenge", title: "How will you prove you're up?",
                       detail: "Pick one to start. You can build a sequence of several later in Edit alarm.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(ChallengeKind.allCases) { kind in
                    ChallengeTile(kind: kind, selected: selectedKind == kind) {}
                        .onTapGesture {
                            Haptics.tap()
                            model.data.alarm.steps = [ChallengeStep(kind: kind)]
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAddTraits(selectedKind == kind ? .isSelected : [])
                }
            }
        }
    }
}

private struct DifficultyPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(kicker: "Difficulty", title: "How hard?", detail: "Easy is fine. The point is getting up, not suffering.")
            if !model.data.alarm.steps.isEmpty {
                let step = $model.data.alarm.steps[0]
                Card {
                    Label(step.wrappedValue.kind.title, systemImage: step.wrappedValue.kind.symbol).font(.headline)
                    Picker("Difficulty", selection: step.difficulty) {
                        ForEach(Difficulty.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: step.wrappedValue.difficulty) { _, level in step.wrappedValue.goal = step.wrappedValue.kind.defaultGoal(level) }
                    if step.wrappedValue.kind.goalRange.count > 1 {
                        Stepper("\(step.wrappedValue.goal) \(step.wrappedValue.kind.goalUnit)", value: step.goal, in: step.wrappedValue.kind.goalRange)
                    }
                    if step.wrappedValue.kind == .memory {
                        Picker("Sequence of", selection: step.memoryStyle) {
                            ForEach(MemoryStyle.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    if step.wrappedValue.kind == .findItem {
                        Picker("Mode", selection: step.findMode) {
                            ForEach(FindMode.choices) { Text($0.title).tag($0) }
                        }
                        Text(step.wrappedValue.findMode.explanation).font(.footnote).foregroundStyle(Palette.text2)
                    }
                    if step.wrappedValue.kind.isPhysical {
                        Text("Choose a number you can do comfortably, even when stiff. You can always tap for a low-movement alternative.")
                            .font(.footnote).foregroundStyle(Palette.text2)
                    }
                }
                Card {
                    Kicker(text: "What it can and can't check")
                    Text(step.wrappedValue.kind.limitation).font(.subheadline).foregroundStyle(Palette.text2)
                }
            }
        }
    }
}

private struct SnoozePage: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(kicker: "Snooze", title: "Allow snooze?", detail: "Snooze is optional and always secondary to getting up.")
            Card {
                Toggle("Allow snooze", isOn: $model.data.alarm.snooze.enabled).tint(theme.accent)
                if model.data.alarm.snooze.enabled {
                    Stepper("\(model.data.alarm.snooze.minutes) minutes", value: $model.data.alarm.snooze.minutes, in: 1...30)
                    Stepper("Up to \(model.data.alarm.snooze.maxCount) times", value: $model.data.alarm.snooze.maxCount, in: 1...10)
                    Toggle("Snoozing restarts the challenge", isOn: $model.data.alarm.snooze.resetsProgress).tint(theme.accent)
                    Picker("Available", selection: $model.data.alarm.snooze.availability) {
                        ForEach(SnoozeAvailability.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
        }
    }
}

private struct DismissalPage: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(kicker: "Stopping the alarm", title: "Finish the challenge to stop?",
                       detail: "When this is on, WakeUp's own alarm screen only stops after the challenge, or with the emergency stop.")
            Card {
                Toggle("Finish challenge to stop", isOn: $model.data.alarm.requireChallenge).tint(theme.accent)
                Stepper("Emergency stop: hold \(model.data.alarm.emergencyHoldSeconds) s", value: $model.data.alarm.emergencyHoldSeconds, in: 2...10)
            }
            Banner(text: "To be honest about iOS: the system alarm on your lock screen always has its own Stop control, and WakeUp can't remove it. If you use it, WakeUp tells you next time you open it.",
                   symbol: "info.circle.fill")
        }
    }
}

private struct HapticsPage: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(kicker: "Feel and history", title: "A few last choices", detail: "Both can be changed later.")
            Card {
                Toggle("Haptic feedback", isOn: $model.data.prefs.haptics).tint(theme.accent)
                    .onChange(of: model.data.prefs.haptics) { _, on in if on { Haptics.success() } }
                Text("Small taps when you press buttons and finish steps.").font(.footnote).foregroundStyle(Palette.text2)
            }
            Card {
                Toggle("Keep wake-up history", isOn: $model.data.prefs.historyEnabled).tint(theme.accent)
                Text("Saves the date, outcome, snooze count and time taken for each alarm, only on this iPhone. Off by default.")
                    .font(.footnote).foregroundStyle(Palette.text2)
            }
        }
    }
}

struct PermissionsPage: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var scheduler: SchedulerService
    @State private var alarmStatus = "…"
    @State private var notificationStatus = "…"

    private var needsCamera: Bool { model.data.alarm.steps.contains { $0.kind.permission != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(kicker: "Permissions", title: "Let WakeUp ring", detail: "Without permission, iOS won't let WakeUp ring when it's closed.")
            if scheduler.alarmKitAvailable {
                Card {
                    Label("Alarms", systemImage: "alarm").font(.headline)
                    Text("Lets WakeUp set a real system alarm. It rings on the lock screen, even in silent mode and Focus.")
                        .font(.subheadline).foregroundStyle(Palette.text2)
                    LabeledContent("Status", value: alarmStatus)
                    Button("Allow alarms") {
                        Task {
                            _ = await scheduler.requestAlarmPermission()
                            await refresh()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            Card {
                Label("Notifications", systemImage: "bell.badge").font(.headline)
                Text(scheduler.alarmKitAvailable
                     ? "Only used as a backup if alarms aren't allowed."
                     : "This iPhone runs an iOS version before 26, so WakeUp uses notifications. They play the sound once, up to 30 seconds, and stay quiet in silent mode.")
                    .font(.subheadline).foregroundStyle(Palette.text2)
                LabeledContent("Status", value: notificationStatus)
                Button("Allow notifications") {
                    Task {
                        _ = await scheduler.requestNotificationPermission()
                        await refresh()
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            Card {
                Label("Camera", systemImage: "camera").font(.headline)
                Text(needsCamera
                     ? "Your challenge can use the camera. WakeUp will ask the first time it's needed. Images are processed on this iPhone and never stored or uploaded."
                     : "Your challenge doesn't need the camera, so WakeUp won't ask.")
                    .font(.subheadline).foregroundStyle(Palette.text2)
                LabeledContent("Status", value: CameraAccess.description)
            }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        alarmStatus = await scheduler.alarmPermissionDescription()
        notificationStatus = await scheduler.notificationPermissionDescription()
    }
}

private struct DemoPage: View {
    @EnvironmentObject private var model: AppModel
    @State private var trying: TestPlan? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(kicker: "Try it", title: "Practise your challenge", detail: "This doesn't set an alarm. It's the same screen you'll see in the morning.")
            Card {
                ForEach(Array(model.data.alarm.steps.enumerated()), id: \.element.id) { index, step in
                    Label("\(index + 1). \(step.label)", systemImage: step.kind.symbol)
                }
                Button("Start the demo") { trying = TestPlan(steps: model.data.alarm.steps) }
                    .buttonStyle(PrimaryButtonStyle())
            }
            if let step = model.data.alarm.steps.first {
                Card {
                    Kicker(text: "What it can and can't check")
                    Text(step.kind.limitation).font(.subheadline).foregroundStyle(Palette.text2)
                    if let permission = step.kind.permission {
                        Text("Uses: \(permission). Processed on this iPhone only.").font(.footnote).foregroundStyle(Palette.text3)
                    }
                }
            }
        }
        .fullScreenCover(item: $trying) { plan in ChallengeTestScreen(steps: plan.steps) }
    }
}

private struct ReviewPage: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var scheduler: SchedulerService
    let go: (Int) -> Void
    @State private var alarmStatus = "…"
    @State private var notificationStatus = "…"

    var body: some View {
        let alarm = model.data.alarm
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(kicker: "All set", title: Greeting.text(name: model.data.prefs.name, enabled: model.data.prefs.greetingEnabled),
                       detail: "Here's your wake-up plan.")
            Card {
                Text(TimeText.string(hour: alarm.hour, minute: alarm.minute, format: model.data.prefs.timeFormat))
                    .font(.system(size: 56, design: .serif)).foregroundStyle(Palette.text1)
                InfoRow(symbol: "repeat", title: "Repeat", value: Weekday.summary(alarm.repeatDays))
                InfoRow(symbol: "speaker.wave.2", title: "Sound", value: model.currentSound.name)
                InfoRow(symbol: "flag.checkered", title: "Challenge", value: alarm.planSummary)
                InfoRow(symbol: "zzz", title: "Snooze", value: alarm.snooze.enabled ? "\(alarm.snooze.minutes) min, up to \(alarm.snooze.maxCount)×" : "Off")
                InfoRow(symbol: "hand.raised", title: "To stop", value: alarm.requireChallenge ? "Finish the challenge" : "Challenge optional")
            }
            Card {
                Kicker(text: "Permissions")
                if scheduler.alarmKitAvailable { LabeledContent("System alarms", value: alarmStatus) }
                LabeledContent("Notifications", value: notificationStatus)
                LabeledContent("Camera", value: CameraAccess.description)
                if alarmStatus != "Allowed" && notificationStatus != "Allowed" {
                    Text("Nothing can ring while WakeUp is closed until you allow alarms or notifications. Go back a few pages, or allow it when you switch the alarm on.")
                        .font(.footnote).foregroundStyle(Palette.warn)
                }
            }
            VStack(spacing: 10) {
                Button("Start using WakeUp") { model.finishOnboarding(enableAlarm: true) }.buttonStyle(PrimaryButtonStyle())
                Button("Test my alarm") {
                    model.finishOnboarding(enableAlarm: true)
                    model.showTestSheet = true
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Change my settings") { go(OnboardingPage.firstWizardIndex) }.buttonStyle(SecondaryButtonStyle())
                Button("Read the full tutorial") { go(1) }.buttonStyle(SecondaryButtonStyle())
            }
        }
        .task {
            alarmStatus = await scheduler.alarmPermissionDescription()
            notificationStatus = await scheduler.notificationPermissionDescription()
        }
    }
}
