import Foundation

// MARK: - Days

enum Weekday: Int, Codable, CaseIterable, Identifiable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }
    /// Monday-first position, used for sorting and display.
    var order: Int { (rawValue + 5) % 7 }
    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.order < rhs.order }

    var shortName: String { Calendar.current.shortStandaloneWeekdaySymbols[rawValue - 1] }
    var fullName: String { Calendar.current.standaloneWeekdaySymbols[rawValue - 1] }
    var initial: String { Calendar.current.veryShortStandaloneWeekdaySymbols[rawValue - 1] }

    static let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    static let weekend: Set<Weekday> = [.saturday, .sunday]
    static let everyDay = Set(Weekday.allCases)
    static var ordered: [Weekday] { allCases.sorted() }

    static func summary(_ days: Set<Weekday>) -> String {
        if days.isEmpty { return "Once" }
        if days == everyDay { return "Every day" }
        if days == weekdays { return "Weekdays" }
        if days == weekend { return "Weekends" }
        return days.sorted().map(\.shortName).joined(separator: ", ")
    }
}

// MARK: - Challenges

enum Difficulty: String, Codable, CaseIterable, Identifiable {
    case easy, medium, hard
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum MemoryStyle: String, Codable, CaseIterable, Identifiable {
    case numbers, colors, symbols
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum FindMode: String, Codable, CaseIterable, Identifiable {
    case randomTarget, qrCode, photo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .randomTarget: "Random item"
        case .qrCode: "Scan the item's QR code"
        case .photo: "Photo check"
        }
    }
    var explanation: String {
        switch self {
        case .randomTarget: "WakeUp picks an item. You go and get it, then confirm. This trusts you: it's confirmation, not verification."
        case .qrCode: "Stick a printed WakeUp code on the item. Scanning it proves you reached the code, not that you used the item."
        case .photo: "Take a photo of the item. WakeUp tries to recognize it on your iPhone. If it can't, you confirm it yourself. Photos are never stored."
        }
    }
}

enum ChallengeCategory: String, CaseIterable, Identifiable {
    case mind, place, body, check
    var id: String { rawValue }
    var title: String {
        switch self {
        case .mind: "Wake your mind"
        case .place: "Get out of bed"
        case .body: "Move your body"
        case .check: "Camera check"
        }
    }
}

enum ChallengeKind: String, Codable, CaseIterable, Identifiable {
    case math, memory, typing, logic, tapSequence, matching, findItem, qrDestination, squats, pushups, eyesOpen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .math: "Math"
        case .memory: "Memory"
        case .typing: "Typing"
        case .logic: "Logic"
        case .tapSequence: "Tap in order"
        case .matching: "Find the pair"
        case .findItem: "Find an item"
        case .qrDestination: "QR destination"
        case .squats: "Squats"
        case .pushups: "Push-ups"
        case .eyesOpen: "Eyes open"
        }
    }

    var summary: String {
        switch self {
        case .math: "Solve freshly generated sums. New questions every time."
        case .memory: "Watch a sequence of numbers, colors or symbols, then repeat it."
        case .typing: "Type a randomly generated sentence accurately."
        case .logic: "Spot the next number in a pattern or the largest value."
        case .tapSequence: "Tap numbered tiles in order as fast as you can."
        case .matching: "Find the one symbol that appears twice."
        case .findItem: "Go and find an everyday item, like your toothbrush."
        case .qrDestination: "Walk to a spot, like the bathroom mirror, and scan its code."
        case .squats: "Do a comfortable number of squats."
        case .pushups: "Do a comfortable number of push-ups."
        case .eyesOpen: "Look at the camera with your eyes open."
        }
    }

    var symbol: String {
        switch self {
        case .math: "plus.forwardslash.minus"
        case .memory: "square.grid.3x3.fill"
        case .typing: "keyboard"
        case .logic: "lightbulb"
        case .tapSequence: "hand.tap"
        case .matching: "square.on.square"
        case .findItem: "magnifyingglass"
        case .qrDestination: "qrcode.viewfinder"
        case .squats: "figure.strengthtraining.functional"
        case .pushups: "figure.core.training"
        case .eyesOpen: "eye"
        }
    }

    var category: ChallengeCategory {
        switch self {
        case .math, .memory, .typing, .logic, .tapSequence, .matching: .mind
        case .findItem, .qrDestination: .place
        case .squats, .pushups: .body
        case .eyesOpen: .check
        }
    }

    /// Hardware or permission the challenge can use, shown on its tile.
    var permission: String? {
        switch self {
        case .qrDestination: "Camera"
        case .findItem: "Camera (some modes)"
        case .squats, .pushups: "Camera (optional)"
        case .eyesOpen: "Camera, Face ID iPhone"
        default: nil
        }
    }

    var isPhysical: Bool { self == .squats || self == .pushups }

    var goalRange: ClosedRange<Int> {
        switch self {
        case .math: 1...10
        case .memory: 3...9
        case .typing: 1...3
        case .logic: 1...5
        case .tapSequence: 4...16
        case .matching: 1...5
        case .findItem: 1...3
        case .qrDestination: 1...1
        case .squats, .pushups: 1...30
        case .eyesOpen: 5...30
        }
    }

    var goalUnit: String {
        switch self {
        case .math, .logic: "questions"
        case .memory: "items to remember"
        case .typing: "sentences"
        case .tapSequence: "tiles"
        case .matching: "rounds"
        case .findItem: "items"
        case .qrDestination: "scan"
        case .squats, .pushups: "reps"
        case .eyesOpen: "seconds"
        }
    }

    func defaultGoal(_ difficulty: Difficulty) -> Int {
        let goal: Int = switch (self, difficulty) {
        case (.math, .easy): 3
        case (.math, .medium): 3
        case (.math, .hard): 4
        case (.memory, .easy): 4
        case (.memory, .medium): 5
        case (.memory, .hard): 7
        case (.typing, _): 1
        case (.logic, .hard): 3
        case (.logic, _): 2
        case (.tapSequence, .easy): 6
        case (.tapSequence, .medium): 9
        case (.tapSequence, .hard): 12
        case (.matching, .hard): 3
        case (.matching, _): 2
        case (.findItem, _): 1
        case (.qrDestination, _): 1
        case (.squats, .easy): 5
        case (.squats, .medium): 10
        case (.squats, .hard): 15
        case (.pushups, .easy): 3
        case (.pushups, .medium): 6
        case (.pushups, .hard): 10
        case (.eyesOpen, .easy): 5
        case (.eyesOpen, .medium): 10
        case (.eyesOpen, .hard): 15
        }
        return goal.clamped(to: goalRange)
    }

    /// What the challenge can and can't verify, shown before it's used.
    var limitation: String {
        switch self {
        case .math, .logic: "Checks that you can answer correctly. It can't tell whether you'll stay up afterwards."
        case .memory: "Checks that you can repeat the sequence. It can't prove you're fully alert."
        case .typing: "Checks what you type, allowing a few typos on easier levels."
        case .tapSequence, .matching: "Checks that you tapped the right things. A quick, low-movement option."
        case .findItem: FindMode.randomTarget.explanation
        case .qrDestination: "Scanning confirms you reached the code, not that you finished your morning routine."
        case .squats, .pushups: "Manual counting trusts you. Camera counting is experimental: it estimates reps from your shoulder position and isn't medically accurate. Stop if anything hurts."
        case .eyesOpen: "Needs a Face ID camera. It checks that your eyes are open, not that you're alert."
        }
    }
}

struct ChallengeStep: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var kind: ChallengeKind
    var difficulty: Difficulty
    var goal: Int
    var restSeconds = 0
    var memoryStyle = MemoryStyle.numbers
    var findMode = FindMode.randomTarget
    var destinationID: UUID?
    var cameraCounting = false

    init(kind: ChallengeKind, difficulty: Difficulty = .easy) {
        self.kind = kind
        self.difficulty = difficulty
        goal = kind.defaultGoal(difficulty)
    }

    var label: String {
        kind == .qrDestination ? kind.title : "\(kind.title) · \(goal) \(kind.goalUnit)"
    }
}

// MARK: - Alarm

enum SnoozeAvailability: String, Codable, CaseIterable, Identifiable {
    case beforeChallenge, anytime
    var id: String { rawValue }
    var title: String { self == .beforeChallenge ? "Before starting the challenge" : "Any time until it's done" }
}

struct SnoozeConfig: Codable, Equatable {
    var enabled = true
    var minutes = 5
    var maxCount = 2
    var resetsProgress = true
    var availability = SnoozeAvailability.beforeChallenge
}

struct AlarmConfig: Codable, Equatable {
    static let maxSteps = 6

    var hour = 7
    var minute = 0
    var enabled = false
    var repeatDays: Set<Weekday> = Weekday.weekdays
    var soundID = "classic-bell"
    /// WakeUp's own playback level (0.1 to 1). iOS doesn't let apps set the system volume.
    var volume = 0.9
    /// Seconds to ramp from quiet to full in WakeUp's own playback. 0 is off.
    var fadeInSeconds = 0
    var snooze = SnoozeConfig()
    var steps: [ChallengeStep] = [ChallengeStep(kind: .math)]
    var requireChallenge = true
    var emergencyHoldSeconds = 3
    /// If the whole sequence takes longer than this it starts over. 0 means no limit.
    var maxDurationMinutes = 0

    var planSummary: String {
        steps.isEmpty ? "No challenge" : steps.map(\.label).joined(separator: " → ")
    }
}

struct CustomSound: Codable, Equatable {
    var name: String
    var file: String
}

// MARK: - Preferences

enum ThemeMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { self == .system ? "System" : rawValue.capitalized }
}

enum AccentChoice: String, Codable, CaseIterable, Identifiable {
    case sunrise, coral, rose, lavender, ocean, mint, forest, graphite
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum BackgroundChoice: String, Codable, CaseIterable, Identifiable {
    case plain, dawn, dusk, glow, mist
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum ShapeChoice: String, Codable, CaseIterable, Identifiable {
    case rounded, compact
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum Density: String, Codable, CaseIterable, Identifiable {
    case comfortable, compact
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum MotionPreference: String, Codable, CaseIterable, Identifiable {
    case system, reduced, full
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Match iPhone"
        case .reduced: "Reduced"
        case .full: "Full"
        }
    }
}

enum TimeFormat: String, Codable, CaseIterable, Identifiable {
    case system, twelve, twentyFour
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Match iPhone"
        case .twelve: "12-hour"
        case .twentyFour: "24-hour"
        }
    }
}

struct ChecklistItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var done = false
}

struct Preferences: Codable, Equatable {
    var name = ""
    var greetingEnabled = true
    var theme = ThemeMode.system
    var accent = AccentChoice.sunrise
    var background = BackgroundChoice.dawn
    var gradientsEnabled = true
    var shape = ShapeChoice.rounded
    var density = Density.comfortable
    var motion = MotionPreference.system
    var timeFormat = TimeFormat.system
    var haptics = true
    var historyEnabled = false
    /// Fallback mode only: plays silent audio overnight so WakeUp can ring in full.
    var keepAwakeInFallback = true
    var showDashboard = true
    var showClock = false
    var showChecklist = false
    var showMessage = true
    var showHistory = false
    var checklist: [ChecklistItem] = [
        ChecklistItem(title: "Drink a glass of water"),
        ChecklistItem(title: "Open the curtains"),
        ChecklistItem(title: "Make the bed"),
    ]
    var checklistDay = ""
}

// MARK: - Library and history

struct HouseholdItem: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var symbol: String
    /// Words matched against on-device image labels in photo mode.
    var keywords: [String]
    var inRandomPool = true
    var photoFile: String?
    var qrCode: String

    init(name: String, symbol: String, keywords: [String]) {
        let id = UUID()
        self.id = id
        self.name = name
        self.symbol = symbol
        self.keywords = keywords
        qrCode = "wakeup://item/\(id.uuidString)"
    }

    static var defaults: [HouseholdItem] {
        [
            HouseholdItem(name: "Toothbrush", symbol: "mouth", keywords: ["toothbrush"]),
            HouseholdItem(name: "Water bottle", symbol: "waterbottle", keywords: ["bottle", "water"]),
            HouseholdItem(name: "Hairbrush", symbol: "comb", keywords: ["brush", "comb", "hairbrush"]),
            HouseholdItem(name: "Book", symbol: "book.closed", keywords: ["book"]),
            HouseholdItem(name: "Shoes", symbol: "shoe", keywords: ["shoe", "footwear", "sneaker"]),
            HouseholdItem(name: "Keys", symbol: "key", keywords: ["key"]),
        ]
    }
}

struct QRDestination: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var code: String

    init(name: String) {
        let id = UUID()
        self.id = id
        self.name = name
        code = "wakeup://destination/\(id.uuidString)"
    }
}

struct WakeRecord: Codable, Identifiable, Equatable {
    enum Outcome: String, Codable {
        case completed, emergency, stoppedWithoutChallenge, missed

        var title: String {
            switch self {
            case .completed: "Challenge completed"
            case .emergency: "Emergency stop"
            case .stoppedWithoutChallenge: "Stopped without the challenge"
            case .missed: "Not answered"
            }
        }
    }

    var id = UUID()
    var date: Date
    var scheduledFor: Date?
    var outcome: Outcome
    var snoozes: Int
    var seconds: Int
    var isTest: Bool
}

/// Progress kept across a snooze so the next ring can resume or restart.
struct RingSession: Codable, Equatable {
    var scheduledFor: Date?
    var startedAt: Date
    var steps: [ChallengeStep]
    var snoozes: Int
    var resumeIndex: Int
    var isTest: Bool
}

struct Diagnostics: Codable, Equatable {
    var lastCheck: Date?
    var lastSuccess: Date?
    var lastError: String?
    var backend = ""
}

// MARK: - Everything WakeUp stores

struct AppData: Codable, Equatable {
    var version = 1
    var prefs = Preferences()
    var alarm = AlarmConfig()
    var customSound: CustomSound?
    var items = HouseholdItem.defaults
    var destinations: [QRDestination] = []
    var history: [WakeRecord] = []
    var onboardingDone = false
    var onboardingStep = 0
    var diagnostics = Diagnostics()
    /// The occurrence WakeUp last scheduled, used to notice alarms that went off while it was closed.
    var expectedFire: Date?
    var lastHandledFire: Date?
    var session: RingSession?

    /// Clamps every value into its allowed range. Used on load and on import.
    func sanitized() -> AppData {
        var d = self
        d.alarm.hour = d.alarm.hour.clamped(to: 0...23)
        d.alarm.minute = d.alarm.minute.clamped(to: 0...59)
        d.alarm.volume = d.alarm.volume.clamped(to: 0.1...1)
        d.alarm.fadeInSeconds = d.alarm.fadeInSeconds.clamped(to: 0...120)
        d.alarm.snooze.minutes = d.alarm.snooze.minutes.clamped(to: 1...30)
        d.alarm.snooze.maxCount = d.alarm.snooze.maxCount.clamped(to: 1...10)
        d.alarm.emergencyHoldSeconds = d.alarm.emergencyHoldSeconds.clamped(to: 2...10)
        d.alarm.maxDurationMinutes = d.alarm.maxDurationMinutes.clamped(to: 0...60)
        d.alarm.steps = d.alarm.steps.prefix(AlarmConfig.maxSteps).map { step in
            var s = step
            s.goal = s.goal.clamped(to: s.kind.goalRange)
            s.restSeconds = s.restSeconds.clamped(to: 0...120)
            return s
        }
        if d.alarm.steps.isEmpty { d.alarm.steps = [ChallengeStep(kind: .math)] }
        let knownSound = SoundLibrary.builtIn.contains { $0.id == d.alarm.soundID }
            || (d.alarm.soundID == SoundLibrary.customID && d.customSound != nil)
        if !knownSound { d.alarm.soundID = SoundLibrary.builtIn[0].id }
        d.prefs.name = String(d.prefs.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        d.prefs.checklist = d.prefs.checklist.prefix(20).map { item in
            var i = item
            i.title = String(i.title.prefix(80))
            return i
        }
        d.items = d.items.prefix(60).compactMap { item in
            var i = item
            i.name = String(i.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            i.keywords = i.keywords.prefix(10).map { String($0.prefix(30)) }
            return i.name.isEmpty ? nil : i
        }
        d.destinations = d.destinations.prefix(20).compactMap { dest in
            var x = dest
            x.name = String(x.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            return x.name.isEmpty ? nil : x
        }
        d.history = Array(d.history.suffix(400))
        return d
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
