#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
import AppIntents
import Foundation
import SwiftUI

@available(iOS 26.0, *)
struct WakeUpAlarmMetadata: AlarmMetadata {}

/// Schedules WakeUp's alarm with AlarmKit (iOS 26 and later). iOS presents it like the Clock app's
/// alarms: it breaks through silent mode and Focus, and shows on the lock screen even when WakeUp
/// isn't running. iOS always offers its own Stop control, which WakeUp can't remove.
@available(iOS 26.0, *)
final class AlarmKitBackend: AlarmBackend {
    let kind = BackendKind.alarmKit
    private var manager: AlarmManager { .shared }

    func isAuthorized() async -> Bool { manager.authorizationState == .authorized }

    func authorize() async -> Bool {
        switch manager.authorizationState {
        case .authorized: return true
        case .denied: return false
        case .notDetermined: return (try? await manager.requestAuthorization()) == .authorized
        @unknown default: return false
        }
    }

    func authorizationDescription() async -> String {
        switch manager.authorizationState {
        case .authorized: "Allowed"
        case .denied: "Off in Settings"
        case .notDetermined: "Not asked yet"
        @unknown default: "Unknown"
        }
    }

    func schedule(_ config: AlarmConfig, id: UUID, sound: AlarmSound) async throws {
        let time = Alarm.Schedule.Relative.Time(hour: config.hour, minute: config.minute)
        let repeats: Alarm.Schedule.Relative.Recurrence = config.repeatDays.isEmpty
            ? .never
            : .weekly(config.repeatDays.sorted().map(\.localeWeekday))
        try await schedule(id: id, schedule: .relative(.init(time: time, repeats: repeats)), sound: sound, title: "Time to wake up")
    }

    func scheduleOneShot(id: UUID, at date: Date, sound: AlarmSound, title: String) async throws {
        try await schedule(id: id, schedule: .fixed(date), sound: sound, title: title)
    }

    private func schedule(id: UUID, schedule: Alarm.Schedule, sound: AlarmSound, title: String) async throws {
        try? manager.cancel(id: id)
        let start = AlarmButton(text: "Start challenge", textColor: .white, systemImageName: "sun.max.fill")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title), secondaryButton: start, secondaryButtonBehavior: .custom)
        } else {
            let stop = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
            alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title), stopButton: stop, secondaryButton: start, secondaryButtonBehavior: .custom)
        }
        let attributes = AlarmAttributes<WakeUpAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: WakeUpAlarmMetadata(),
            tintColor: Color(red: 0.85, green: 0.51, blue: 0.17)
        )
        let configuration = AlarmManager.AlarmConfiguration<WakeUpAlarmMetadata>.alarm(
            schedule: schedule,
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: id.uuidString),
            secondaryIntent: StartChallengeIntent(alarmID: id.uuidString),
            sound: .named(sound.fileName)
        )
        do {
            _ = try await manager.schedule(id: id, configuration: configuration)
        } catch let error as AlarmManager.AlarmError where error == .maximumLimitReached {
            throw SchedulerError.limitReached
        }
    }

    func cancel(id: UUID) async { try? manager.cancel(id: id) }

    func stop(id: UUID) async {
        guard let alarm = (try? manager.alarms)?.first(where: { $0.id == id }), alarm.state == .alerting else { return }
        try? manager.stop(id: id)
    }

    func isScheduled(id: UUID) async -> Bool {
        ((try? manager.alarms) ?? []).contains { $0.id == id }
    }

    static func observeAlerts(_ handler: @escaping @MainActor (UUID) -> Void) {
        Task { @MainActor in
            for await alarms in AlarmManager.shared.alarmUpdates {
                for alarm in alarms where alarm.state == .alerting {
                    handler(alarm.id)
                }
            }
        }
    }
}

@available(iOS 26.0, *)
private extension Weekday {
    var localeWeekday: Locale.Weekday {
        switch self {
        case .sunday: .sunday
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        }
    }
}

/// Runs when the alarm's "Start challenge" button is pressed: opens WakeUp on the challenge.
@available(iOS 26.0, *)
struct StartChallengeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start wake-up challenge"
    static var description = IntentDescription("Opens WakeUp on your wake-up challenge.")
    static var openAppWhenRun = true

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init(alarmID: String) { self.alarmID = alarmID }
    init() { alarmID = "" }

    func perform() async throws -> some IntentResult {
        RingSignal.markChallengeRequested()
        return .result()
    }
}

/// Runs when the system Stop control is used. WakeUp records it so it can tell you later.
@available(iOS 26.0, *)
struct StopAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop alarm"
    static var description = IntentDescription("Stops the WakeUp alarm without the challenge.")

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init(alarmID: String) { self.alarmID = alarmID }
    init() { alarmID = "" }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try? AlarmManager.shared.stop(id: id) }
        RingSignal.markSystemStop()
        return .result()
    }
}
#endif
