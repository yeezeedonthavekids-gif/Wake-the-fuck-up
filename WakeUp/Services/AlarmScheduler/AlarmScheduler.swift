import Foundation
import UserNotifications

enum BackendKind: String, Codable {
    case alarmKit, notifications, none

    var title: String {
        switch self {
        case .alarmKit: "System alarm (AlarmKit)"
        case .notifications: "Notifications (fallback)"
        case .none: "Not scheduled"
        }
    }
}

enum ScheduleStatus: Equatable {
    case off
    case checking
    case scheduled(next: Date, backend: BackendKind)
    /// iOS won't schedule anything, so WakeUp rings by itself while it stays running in the background.
    case inAppOnly(next: Date, reason: String)
    case needsPermission(String)
    case failed(String)
}

struct ScheduleOutcome {
    var next: Date?
    var backend: BackendKind
    var error: String?
}

enum SchedulerError: LocalizedError {
    case noDate, notListed, limitReached

    var errorDescription: String? {
        switch self {
        case .noDate: "WakeUp couldn't work out when the alarm should next ring."
        case .notListed: "iOS accepted the alarm but doesn't list it as scheduled. Try again, or restart your iPhone."
        case .limitReached: "iOS says this app has reached its alarm limit."
        }
    }
}

/// One way of getting iOS to ring at a time. AlarmKit is the real thing; notifications are the fallback.
protocol AlarmBackend: AnyObject {
    var kind: BackendKind { get }
    func isAuthorized() async -> Bool
    func authorize() async -> Bool
    func authorizationDescription() async -> String
    func schedule(_ config: AlarmConfig, id: UUID, sound: AlarmSound) async throws
    func scheduleOneShot(id: UUID, at date: Date, sound: AlarmSound, title: String) async throws
    func cancel(id: UUID) async
    /// Silences an alarm that is ringing now without cancelling future repeats.
    func stop(id: UUID) async
    func isScheduled(id: UUID) async -> Bool
}

/// Remembers when an alarm button was pressed outside the app, so WakeUp can respond when it opens.
enum RingSignal {
    private static let requestKey = "wakeup.signal.challengeRequested"
    private static let stopKey = "wakeup.signal.systemStop"

    static func markChallengeRequested() { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: requestKey) }
    static func markSystemStop() { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: stopKey) }

    /// True if someone asked for the challenge within `window` seconds. Clears the request.
    static func takeChallengeRequest(within window: TimeInterval) -> Bool {
        let stamp = UserDefaults.standard.double(forKey: requestKey)
        UserDefaults.standard.removeObject(forKey: requestKey)
        return stamp > 0 && Date().timeIntervalSince1970 - stamp < window
    }

    /// True if the system Stop button was used after `date`. Clears the record.
    static func takeSystemStop(after date: Date) -> Bool {
        let stamp = UserDefaults.standard.double(forKey: stopKey)
        UserDefaults.standard.removeObject(forKey: stopKey)
        return stamp > 0 && stamp >= date.timeIntervalSince1970
    }
}

// MARK: - Notification fallback

/// Used before iOS 26, or when AlarmKit permission is denied. A notification plays its sound once
/// (up to 30 seconds) and stays silent if the ring/silent switch is on, so this is weaker than a
/// system alarm. WakeUp schedules a burst of them and says so in the app.
final class NotificationBackend: AlarmBackend {
    let kind = BackendKind.notifications
    /// Notifications per ring, 18 seconds apart, so it keeps going for about 3 minutes.
    static let burst = 10
    static let spacing: TimeInterval = 18
    private var center: UNUserNotificationCenter { .current() }

    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    func authorize() async -> Bool {
        if await isAuthorized() { return true }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func authorizationDescription() async -> String {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized: "Allowed"
        case .provisional: "Delivered quietly"
        case .denied: "Off in Settings"
        case .notDetermined: "Not asked yet"
        case .ephemeral: "Allowed for now"
        @unknown default: "Unknown"
        }
    }

    func schedule(_ config: AlarmConfig, id: UUID, sound: AlarmSound) async throws {
        await cancel(id: id)
        // iOS keeps at most 64 pending notifications per app, so only the next three rings are queued.
        // WakeUp tops this up every time it opens.
        let dates = AlarmMath.upcoming(3, config)
        guard !dates.isEmpty else { throw SchedulerError.noDate }
        for (ring, date) in dates.enumerated() {
            try await addBurst(prefix: "\(id.uuidString)-\(ring)", start: date, sound: sound, title: "Time to wake up")
        }
    }

    func scheduleOneShot(id: UUID, at date: Date, sound: AlarmSound, title: String) async throws {
        await cancel(id: id)
        try await addBurst(prefix: id.uuidString, start: date, sound: sound, title: title)
    }

    private func addBurst(prefix: String, start: Date, sound: AlarmSound, title: String) async throws {
        for k in 0..<Self.burst {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = k == 0 ? "Open WakeUp to start your challenge." : "Still ringing. Open WakeUp to start your challenge."
            content.sound = UNNotificationSound(named: UNNotificationSoundName(sound.fileName))
            content.interruptionLevel = .timeSensitive
            content.userInfo = ["wakeup": "ring"]
            let when = start.addingTimeInterval(Double(k) * Self.spacing)
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: when)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try await center.add(UNNotificationRequest(identifier: "\(prefix)-\(k)", content: content, trigger: trigger))
        }
    }

    func cancel(id: UUID) async {
        let prefix = id.uuidString
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(prefix) }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }

    func stop(id: UUID) async {
        let prefix = id.uuidString
        let soon = Date().addingTimeInterval(Double(Self.burst) * Self.spacing + 60)
        let pending = await center.pendingNotificationRequests().filter { request in
            guard request.identifier.hasPrefix(prefix),
                  let next = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() else { return false }
            return next <= soon
        }
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
        let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(prefix) }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }

    func isScheduled(id: UUID) async -> Bool {
        await center.pendingNotificationRequests().contains { $0.identifier.hasPrefix(id.uuidString) }
    }
}

// MARK: - Scheduler

/// Owns the single primary alarm plus three helper alarms (snooze, follow-up and test), each with
/// a fixed ID, so rescheduling replaces the old alarm instead of adding a duplicate.
@MainActor
final class SchedulerService: ObservableObject {
    @Published private(set) var status: ScheduleStatus = .off

    let primaryID = SchedulerService.storedID("primary")
    let snoozeID = SchedulerService.storedID("snooze")
    let followUpID = SchedulerService.storedID("followUp")
    let testID = SchedulerService.storedID("test")

    private let notifications = NotificationBackend()
    private let alarmKit: (any AlarmBackend)?

    init() {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            alarmKit = AlarmKitBackend()
        } else {
            alarmKit = nil
        }
        #else
        alarmKit = nil
        #endif
    }

    var alarmKitAvailable: Bool { alarmKit != nil }
    var allIDs: [UUID] { [primaryID, snoozeID, followUpID, testID] }
    private var backends: [any AlarmBackend] { [alarmKit, notifications as (any AlarmBackend)?].compactMap { $0 } }

    private static func storedID(_ key: String) -> UUID {
        let defaultsKey = "wakeup.alarmID.\(key)"
        if let saved = UserDefaults.standard.string(forKey: defaultsKey), let id = UUID(uuidString: saved) { return id }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: defaultsKey)
        return id
    }

    /// The strongest backend the person has allowed: AlarmKit first, then notifications.
    func activeBackend(requestPermission: Bool) async -> (any AlarmBackend)? {
        if let alarmKit {
            let allowed = requestPermission ? await alarmKit.authorize() : await alarmKit.isAuthorized()
            if allowed { return alarmKit }
        }
        let allowed = requestPermission ? await notifications.authorize() : await notifications.isAuthorized()
        return allowed ? notifications : nil
    }

    /// Makes iOS's scheduled alarms match `config`, then checks iOS actually lists it.
    func apply(_ config: AlarmConfig, sound: AlarmSound, requestPermission: Bool) async -> ScheduleOutcome {
        status = .checking
        for backend in backends { await backend.cancel(id: primaryID) }
        guard config.enabled else {
            status = .off
            return ScheduleOutcome(next: nil, backend: .none, error: nil)
        }
        guard let next = AlarmMath.nextFire(config) else {
            let message = SchedulerError.noDate.localizedDescription
            status = .failed(message)
            return ScheduleOutcome(next: nil, backend: .none, error: message)
        }
        guard let backend = await activeBackend(requestPermission: requestPermission) else {
            let message = alarmKitAvailable
                ? "iOS isn't letting WakeUp set a system alarm or send notifications (this is common for sideloaded apps)."
                : "Notifications are off for WakeUp."
            status = .inAppOnly(next: next, reason: message)
            return ScheduleOutcome(next: next, backend: .none, error: message)
        }
        do {
            try await backend.schedule(config, id: primaryID, sound: sound)
            guard await backend.isScheduled(id: primaryID) else { throw SchedulerError.notListed }
            status = .scheduled(next: next, backend: backend.kind)
            return ScheduleOutcome(next: next, backend: backend.kind, error: nil)
        } catch {
            let message = error.localizedDescription
            status = .failed(message)
            return ScheduleOutcome(next: nil, backend: backend.kind, error: message)
        }
    }

    /// Schedules a single extra ring (snooze, follow-up or test). Returns an error message on failure.
    func scheduleOneShot(id: UUID, at date: Date, sound: AlarmSound, title: String) async -> (backend: BackendKind, error: String?) {
        for backend in backends { await backend.cancel(id: id) }
        guard let backend = await activeBackend(requestPermission: true) else {
            return (.none, "WakeUp isn't allowed to set alarms or send notifications.")
        }
        do {
            try await backend.scheduleOneShot(id: id, at: date, sound: sound, title: title)
            return (backend.kind, nil)
        } catch {
            return (backend.kind, error.localizedDescription)
        }
    }

    func cancel(id: UUID) async {
        for backend in backends { await backend.cancel(id: id) }
    }

    /// Silences anything ringing now. Future repeats of the primary alarm stay scheduled.
    func stopAlerting() async {
        for backend in backends {
            for id in allIDs { await backend.stop(id: id) }
        }
    }

    func cancelEverything() async {
        for backend in backends {
            for id in allIDs { await backend.cancel(id: id) }
        }
        status = .off
    }

    func alarmPermissionDescription() async -> String {
        guard let alarmKit else { return "Needs iOS 26" }
        return await alarmKit.authorizationDescription()
    }

    func notificationPermissionDescription() async -> String {
        await notifications.authorizationDescription()
    }

    func requestAlarmPermission() async -> Bool {
        guard let alarmKit else { return false }
        return await alarmKit.authorize()
    }

    func requestNotificationPermission() async -> Bool {
        await notifications.authorize()
    }

    /// Calls `handler` whenever one of WakeUp's system alarms starts ringing while the app is running.
    func observeAlerts(_ handler: @escaping @MainActor (UUID) -> Void) {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), alarmKit != nil {
            AlarmKitBackend.observeAlerts(handler)
        }
        #endif
    }
}
