import Foundation
import SwiftUI
import UserNotifications

/// What the ringing screen needs. The plan is copied when ringing starts, so editing the alarm
/// while it rings only affects the next occurrence.
struct RingContext: Identifiable {
    let id = UUID()
    let isTest: Bool
    let scheduledFor: Date?
    let startedAt: Date
    let steps: [ChallengeStep]
    let snoozes: Int
    let startIndex: Int
    let requireChallenge: Bool
    let holdSeconds: Int
    let snooze: SnoozeConfig
    let maxDuration: TimeInterval?
}

@MainActor
final class AppModel: ObservableObject {
    @Published var data: AppData {
        didSet { if data != oldValue { persist() } }
    }
    @Published var ringing: RingContext?
    @Published var notice: String?
    @Published var showTestSheet = false

    let persistence: Persistence
    let audio = AudioEngine()
    let scheduler = SchedulerService()

    /// The follow-up ring if the challenge isn't finished: a real alarm in case WakeUp is closed mid-challenge.
    static let followUpDelay: TimeInterval = 5 * 60

    private var fallbackTimer: Timer?
    private let notificationDelegate = NotificationDelegate()

    init(persistence: Persistence = Persistence()) {
        self.persistence = persistence
        data = persistence.load()
        Haptics.enabled = data.prefs.haptics
        resetChecklistIfNewDay()
        notificationDelegate.model = self
        UNUserNotificationCenter.current().delegate = notificationDelegate
        scheduler.observeAlerts { [weak self] id in self?.systemAlarmAlerting(id) }
    }

    private func persist() {
        Haptics.enabled = data.prefs.haptics
        do {
            try persistence.save(data)
        } catch {
            notice = "WakeUp couldn't save your settings: \(error.localizedDescription)"
        }
    }

    // MARK: Sounds

    var currentSound: AlarmSound { SoundLibrary.sound(id: data.alarm.soundID, custom: data.customSound) }

    func sound(id: String) -> AlarmSound { SoundLibrary.sound(id: id, custom: data.customSound) }

    func importSound(from url: URL) throws {
        let name = url.deletingPathExtension().lastPathComponent
        let imported = try SoundLibrary.importCustom(from: url, name: name)
        if let old = data.customSound { SoundLibrary.removeCustom(old) }
        data.customSound = imported
    }

    func removeCustomSound() {
        guard let old = data.customSound else { return }
        SoundLibrary.removeCustom(old)
        data.customSound = nil
        if data.alarm.soundID == SoundLibrary.customID {
            updateAlarm { $0.soundID = SoundLibrary.builtIn[0].id }
        }
    }

    // MARK: Scheduling

    func updateAlarm(requestPermission: Bool = false, _ change: (inout AlarmConfig) -> Void) {
        change(&data.alarm)
        Task { await reschedule(requestPermission: requestPermission) }
    }

    /// Makes the scheduled alarm match the saved settings and records the result for Diagnostics.
    func reschedule(requestPermission: Bool = false) async {
        let outcome = await scheduler.apply(data.alarm, sound: currentSound, requestPermission: requestPermission)
        data.diagnostics.lastCheck = Date()
        data.diagnostics.backend = outcome.backend.rawValue
        if let error = outcome.error {
            data.diagnostics.lastError = error
        } else if outcome.next != nil {
            data.diagnostics.lastSuccess = Date()
            data.diagnostics.lastError = nil
        }
        data.expectedFire = outcome.next
        armFallback(outcome)
    }

    /// With the notification fallback, WakeUp also rings in-app if it's still running at alarm time.
    private func armFallback(_ outcome: ScheduleOutcome) {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        let fallback = outcome.backend == .notifications && data.alarm.enabled
        audio.setKeepAlive(fallback && data.prefs.keepAwakeInFallback)
        guard fallback, let next = outcome.next else { return }
        armTimer(at: next) { [weak self] in self?.startRinging(isTest: false, scheduledFor: next) }
    }

    private func armTimer(at date: Date, _ action: @escaping @MainActor () -> Void) {
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in Task { @MainActor in action() } }
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
    }

    // MARK: App lifecycle

    func becameActive() {
        resetChecklistIfNewDay()
        if ringing == nil {
            if RingSignal.takeChallengeRequest(within: 30 * 60) {
                startRinging(isTest: false, scheduledFor: data.expectedFire)
            } else {
                checkMissed()
            }
        }
        // Reconcile every time WakeUp opens: replaces rather than duplicates, and tops up fallback rings.
        Task { await reschedule() }
    }

    /// Notices an alarm time that passed while WakeUp wasn't on screen.
    private func checkMissed() {
        guard let fire = data.expectedFire, fire < Date().addingTimeInterval(-30), data.lastHandledFire != fire else { return }
        data.lastHandledFire = fire
        let stoppedFromLockScreen = RingSignal.takeSystemStop(after: fire.addingTimeInterval(-60))
        if !stoppedFromLockScreen, Date().timeIntervalSince(fire) < 20 * 60 {
            // Recent and not stopped: it may still be ringing, so pick up the challenge.
            startRinging(isTest: false, scheduledFor: fire)
            return
        }
        let time = TimeText.string(fire, format: data.prefs.timeFormat)
        if stoppedFromLockScreen {
            notice = "Your \(time) alarm was stopped from the lock screen, so the challenge was skipped. iOS always allows that."
            record(.stoppedWithoutChallenge, scheduledFor: fire, snoozes: 0, seconds: 0, isTest: false)
        } else {
            notice = "Your \(time) alarm went off while WakeUp was closed, and the challenge wasn't started."
            record(.missed, scheduledFor: fire, snoozes: 0, seconds: 0, isTest: false)
        }
    }

    /// A system alarm started ringing while WakeUp is running.
    func systemAlarmAlerting(_ id: UUID) {
        guard scheduler.allIDs.contains(id) else { return }
        if ringing != nil {
            // Already doing the challenge in-app: silence the follow-up and push it back.
            Task { await scheduler.stopAlerting() }
            challengeProgressed()
            return
        }
        startRinging(isTest: id == scheduler.testID, scheduledFor: id == scheduler.primaryID ? data.expectedFire : nil)
    }

    // MARK: Ringing

    /// Steps that can't run on this device are swapped for a backup so the alarm can always be finished.
    private func resolvedSteps() -> [ChallengeStep] {
        data.alarm.steps.map { step in
            guard step.kind == .eyesOpen, !EyeTracking.isSupported else { return step }
            var backup = ChallengeStep(kind: .math, difficulty: .medium)
            backup.goal = 5
            return backup
        }
    }

    func startRinging(isTest: Bool, scheduledFor: Date?) {
        guard ringing == nil else { return }
        let session = data.session
        Task { await scheduler.stopAlerting() }
        audio.startRinging(currentSound, volume: data.alarm.volume, fadeIn: data.alarm.fadeInSeconds)
        let alarm = data.alarm
        ringing = RingContext(
            isTest: session?.isTest ?? isTest,
            scheduledFor: scheduledFor ?? session?.scheduledFor,
            startedAt: session?.startedAt ?? Date(),
            steps: session?.steps ?? resolvedSteps(),
            snoozes: session?.snoozes ?? 0,
            startIndex: session?.resumeIndex ?? 0,
            requireChallenge: alarm.requireChallenge,
            holdSeconds: alarm.emergencyHoldSeconds,
            snooze: alarm.snooze,
            maxDuration: alarm.maxDurationMinutes > 0 ? TimeInterval(alarm.maxDurationMinutes * 60) : nil
        )
        if let scheduledFor { data.lastHandledFire = scheduledFor }
        if !(session?.isTest ?? isTest) { armFollowUp() }
    }

    func challengeProgressed() {
        guard let ringing, !ringing.isTest else { return }
        armFollowUp()
    }

    private func armFollowUp() {
        let at = Date().addingTimeInterval(Self.followUpDelay)
        let sound = currentSound
        Task { _ = await scheduler.scheduleOneShot(id: scheduler.followUpID, at: at, sound: sound, title: "Your challenge isn't finished") }
    }

    func canSnooze(_ context: RingContext, started: Bool) -> Bool {
        context.snooze.enabled
            && context.snoozes < context.snooze.maxCount
            && (context.snooze.availability == .anytime || !started)
    }

    func snooze(currentIndex: Int) {
        guard let context = ringing else { return }
        audio.stopRinging()
        let at = Date().addingTimeInterval(TimeInterval(context.snooze.minutes * 60))
        data.session = RingSession(
            scheduledFor: context.scheduledFor,
            startedAt: context.startedAt,
            steps: context.steps,
            snoozes: context.snoozes + 1,
            resumeIndex: context.snooze.resetsProgress ? 0 : currentIndex,
            isTest: context.isTest
        )
        ringing = nil
        let sound = currentSound
        Task {
            await scheduler.cancel(id: scheduler.followUpID)
            await scheduler.stopAlerting()
            let result = await scheduler.scheduleOneShot(id: scheduler.snoozeID, at: at, sound: sound, title: "Snooze is over")
            if let error = result.error {
                notice = "Snooze couldn't be scheduled: \(error) WakeUp will still ring if it stays open."
            }
            if result.backend != .alarmKit {
                armTimer(at: at) { [weak self] in self?.startRinging(isTest: context.isTest, scheduledFor: context.scheduledFor) }
            }
        }
        notice = "Snoozing until \(TimeText.string(at, format: data.prefs.timeFormat))."
    }

    /// Stops the sound and clears pending rings. The ringing screen stays up to show the result.
    func completeRinging(_ outcome: WakeRecord.Outcome) {
        guard let context = ringing else { return }
        audio.stopRinging()
        data.session = nil
        record(outcome, scheduledFor: context.scheduledFor, snoozes: context.snoozes,
               seconds: Int(Date().timeIntervalSince(context.startedAt)), isTest: context.isTest)
        let oneTime = data.alarm.repeatDays.isEmpty && !context.isTest && context.scheduledFor != nil
        if oneTime { data.alarm.enabled = false }
        Task {
            await scheduler.cancel(id: scheduler.followUpID)
            await scheduler.cancel(id: scheduler.snoozeID)
            await scheduler.stopAlerting()
            if !context.isTest || oneTime { await reschedule() }
        }
        Haptics.success()
    }

    func dismissRinging() { ringing = nil }

    // MARK: Testing

    func testRingNow() {
        data.session = nil
        startRinging(isTest: true, scheduledFor: nil)
    }

    func scheduleTest(in seconds: TimeInterval = 60) async -> String {
        let at = Date().addingTimeInterval(seconds)
        let result = await scheduler.scheduleOneShot(id: scheduler.testID, at: at, sound: currentSound, title: "WakeUp test alarm")
        if let error = result.error { return "The test couldn't be scheduled: \(error)" }
        let time = TimeText.string(at, format: data.prefs.timeFormat)
        if result.backend == .alarmKit {
            return "Test alarm set for \(time) as a system alarm. Lock your iPhone and wait for it."
        }
        armTimer(at: at) { [weak self] in self?.startRinging(isTest: true, scheduledFor: nil) }
        return "Test set for \(time) using notifications. Lock your iPhone: you'll hear the notification sound, then open WakeUp."
    }

    // MARK: History

    private func record(_ outcome: WakeRecord.Outcome, scheduledFor: Date?, snoozes: Int, seconds: Int, isTest: Bool) {
        guard data.prefs.historyEnabled else { return }
        data.history.append(WakeRecord(date: Date(), scheduledFor: scheduledFor, outcome: outcome, snoozes: snoozes, seconds: seconds, isTest: isTest))
        if data.history.count > 400 { data.history.removeFirst(data.history.count - 400) }
    }

    // MARK: Checklist

    private func resetChecklistIfNewDay() {
        let today = Date().formatted(.iso8601.year().month().day())
        guard data.prefs.checklistDay != today else { return }
        data.prefs.checklistDay = today
        for i in data.prefs.checklist.indices { data.prefs.checklist[i].done = false }
    }

    // MARK: Onboarding

    func finishOnboarding(enableAlarm: Bool) {
        data.onboardingDone = true
        if enableAlarm {
            updateAlarm(requestPermission: true) { $0.enabled = true }
        }
    }

    func replayOnboarding() {
        data.onboardingStep = 0
        data.onboardingDone = false
    }

    // MARK: Privacy

    func exportSettings() throws -> Data { try Persistence.export(data) }

    func importSettings(_ fileData: Data) throws {
        data = try Persistence.importing(fileData, into: data)
        Task { await reschedule() }
    }

    func eraseEverything() {
        audio.stopRinging()
        audio.setKeepAlive(false)
        fallbackTimer?.invalidate()
        ringing = nil
        persistence.eraseAll()
        data = AppData()
        Task { await scheduler.cancelEverything() }
    }
}

/// Handles notification taps (fallback mode) and notifications arriving while WakeUp is open.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    weak var model: AppModel?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.content.userInfo["wakeup"] as? String == "ring" else { return }
        RingSignal.markChallengeRequested()
        await MainActor.run { model?.becameActive() }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        guard notification.request.content.userInfo["wakeup"] as? String == "ring" else { return [.banner, .sound] }
        await MainActor.run {
            guard let model, model.ringing == nil else { return }
            model.startRinging(isTest: false, scheduledFor: model.data.expectedFire)
        }
        // WakeUp is already ringing in-app, so the notification itself stays quiet.
        return []
    }
}
