import AVFoundation
import XCTest
@testable import WakeUp

final class AlarmMathTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testOneTimeAlarmLaterToday() {
        let now = date(2026, 10, 28, 6, 0) // Wednesday
        let next = AlarmMath.nextFire(hour: 7, minute: 30, days: [], after: now, calendar: calendar)
        XCTAssertEqual(next, date(2026, 10, 28, 7, 30))
    }

    func testOneTimeAlarmAlreadyPassedMovesToTomorrow() {
        let now = date(2026, 10, 28, 8, 0)
        let next = AlarmMath.nextFire(hour: 7, minute: 30, days: [], after: now, calendar: calendar)
        XCTAssertEqual(next, date(2026, 10, 29, 7, 30))
    }

    func testExactlyAtAlarmTimeMovesOn() {
        let now = date(2026, 10, 28, 7, 30)
        let next = AlarmMath.nextFire(hour: 7, minute: 30, days: [], after: now, calendar: calendar)
        XCTAssertEqual(next, date(2026, 10, 29, 7, 30))
    }

    func testWeekdaysSkipTheWeekend() {
        let friday = date(2026, 10, 30, 9, 0)
        let next = AlarmMath.nextFire(hour: 7, minute: 0, days: Weekday.weekdays, after: friday, calendar: calendar)
        XCTAssertEqual(next, date(2026, 11, 2, 7, 0)) // Monday
    }

    func testWeekendOnly() {
        let wednesday = date(2026, 10, 28, 9, 0)
        let next = AlarmMath.nextFire(hour: 9, minute: 15, days: Weekday.weekend, after: wednesday, calendar: calendar)
        XCTAssertEqual(next, date(2026, 10, 31, 9, 15)) // Saturday
    }

    func testMidnightAlarm() {
        let now = date(2026, 10, 28, 23, 59)
        let next = AlarmMath.nextFire(hour: 0, minute: 0, days: [], after: now, calendar: calendar)
        XCTAssertEqual(next, date(2026, 10, 29, 0, 0))
    }

    func testSpringForwardMissingTimeUsesNextValidTime() {
        // 2:30 doesn't exist on 8 March 2026 in New York; clocks jump from 2:00 to 3:00.
        let now = date(2026, 3, 7, 23, 0)
        let next = AlarmMath.nextFire(hour: 2, minute: 30, days: [], after: now, calendar: calendar)!
        let parts = calendar.dateComponents([.month, .day, .hour], from: next)
        XCTAssertEqual(parts.month, 3)
        XCTAssertEqual(parts.day, 8)
        XCTAssertEqual(parts.hour, 3)
    }

    func testFallBackRepeatedHourRingsOnce() {
        // 1:30 happens twice on 1 November 2026; the alarm uses the first.
        let now = date(2026, 10, 31, 23, 0)
        let next = AlarmMath.nextFire(hour: 1, minute: 30, days: [], after: now, calendar: calendar)!
        XCTAssertEqual(calendar.component(.hour, from: next), 1)
        let second = AlarmMath.nextFire(hour: 1, minute: 30, days: [], after: next, calendar: calendar)!
        XCTAssertEqual(calendar.component(.day, from: second), 2, "The repeated hour must not ring twice")
    }

    func testUpcomingRepeatsAndOneTime() {
        var config = AlarmConfig()
        config.repeatDays = Weekday.everyDay
        XCTAssertEqual(AlarmMath.upcoming(3, config, after: date(2026, 10, 28, 9, 0), calendar: calendar).count, 3)
        config.repeatDays = []
        XCTAssertEqual(AlarmMath.upcoming(3, config, after: date(2026, 10, 28, 9, 0), calendar: calendar).count, 1)
    }

    func testCountdownText() {
        let now = date(2026, 10, 28, 22, 0)
        XCTAssertEqual(AlarmMath.countdown(from: now, to: date(2026, 10, 29, 7, 5)), "9 h 5 min")
        XCTAssertEqual(AlarmMath.countdown(from: now, to: now.addingTimeInterval(90)), "2 min")
        XCTAssertEqual(AlarmMath.countdown(from: now, to: date(2026, 10, 31, 7, 0)), "2 d 9 h")
    }

    func testTimeFormats() {
        XCTAssertEqual(TimeText.parts(hour: 7, minute: 5, format: .twentyFour).time, "07:05")
        XCTAssertNil(TimeText.parts(hour: 7, minute: 5, format: .twentyFour).period)
        XCTAssertEqual(TimeText.parts(hour: 0, minute: 0, format: .twelve).time, "12:00")
        XCTAssertEqual(TimeText.parts(hour: 13, minute: 45, format: .twelve).time, "1:45")
        XCTAssertNotNil(TimeText.parts(hour: 13, minute: 45, format: .twelve).period)
    }

    func testRepeatSummary() {
        XCTAssertEqual(Weekday.summary([]), "Once")
        XCTAssertEqual(Weekday.summary(Weekday.everyDay), "Every day")
        XCTAssertEqual(Weekday.summary(Weekday.weekdays), "Weekdays")
        XCTAssertEqual(Weekday.summary(Weekday.weekend), "Weekends")
    }

    func testGreeting() {
        let evening = date(2026, 10, 28, 20, 0)
        XCTAssertTrue(Greeting.text(name: "Jackson", enabled: true, date: evening).hasSuffix(", Jackson."))
        XCTAssertFalse(Greeting.text(name: "Jackson", enabled: false, date: evening).contains("Jackson"))
        XCTAssertFalse(Greeting.text(name: "   ", enabled: true, date: evening).contains(","))
    }
}

final class GeneratorTests: XCTestCase {
    /// Evaluates the generator's own text so the stated answer is checked independently.
    private func evaluate(_ text: String) -> Double? {
        let expression = text.replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
        let floats = expression.replacingOccurrences(of: #"(\d+)"#, with: "$1.0", options: .regularExpression)
        return (NSExpression(format: floats).expressionValue(with: nil, context: nil) as? NSNumber)?.doubleValue
    }

    func testMathAnswersAreCorrectWholeAndNonNegative() {
        var g = SeededGenerator(seed: 1)
        for difficulty in Difficulty.allCases {
            for _ in 0..<500 {
                let problem = MathGenerator.make(difficulty, using: &g)
                XCTAssertGreaterThanOrEqual(problem.answer, 0, problem.text)
                XCTAssertEqual(evaluate(problem.text), Double(problem.answer), problem.text)
            }
        }
    }

    func testMathQuestionsVary() {
        var g = SeededGenerator(seed: 2)
        let texts = Set((0..<50).map { _ in MathGenerator.make(.medium, using: &g).text })
        XCTAssertGreaterThan(texts.count, 30)
    }

    func testMemorySequences() {
        var g = SeededGenerator(seed: 3)
        for style in MemoryStyle.allCases {
            for length in 3...9 {
                let sequence = MemoryGenerator.sequence(length: length, style: style, using: &g)
                XCTAssertEqual(sequence.count, length)
                XCTAssertTrue(sequence.allSatisfy { (0..<MemoryGenerator.alphabetSize(style)).contains($0) })
                XCTAssertFalse(zip(sequence, sequence.dropFirst()).contains { $0 == $1 }, "No item repeats twice in a row")
            }
        }
    }

    func testTypingTolerance() {
        let target = "the sleepy cat waits for the kitchen table"
        XCTAssertTrue(TypingGenerator.accepts(target, target: target, difficulty: .hard))
        XCTAssertTrue(TypingGenerator.accepts("The Sleepy cat waits for the kitchn table", target: target, difficulty: .easy))
        XCTAssertTrue(TypingGenerator.accepts("the sleepy cat waits for the kitchn table", target: target, difficulty: .medium))
        XCTAssertFalse(TypingGenerator.accepts("the sleepy cat waits for the kitchn table", target: target, difficulty: .hard))
        XCTAssertFalse(TypingGenerator.accepts("something else entirely", target: target, difficulty: .easy))
        XCTAssertTrue(TypingGenerator.accepts("  the  sleepy cat waits for the kitchen table ", target: target, difficulty: .hard))
    }

    func testLevenshtein() {
        XCTAssertEqual(TypingGenerator.distance("kitten", "sitting"), 3)
        XCTAssertEqual(TypingGenerator.distance("", "abc"), 3)
        XCTAssertEqual(TypingGenerator.distance("same", "same"), 0)
    }

    func testTypingPhrasesVary() {
        var g = SeededGenerator(seed: 4)
        let phrases = Set((0..<40).map { _ in TypingGenerator.phrase(.medium, using: &g) })
        XCTAssertGreaterThan(phrases.count, 30)
    }

    func testLogicQuestionsHaveOneCorrectDistinctAnswer() {
        var g = SeededGenerator(seed: 5)
        for difficulty in Difficulty.allCases {
            for _ in 0..<300 {
                let q = LogicGenerator.make(difficulty, using: &g)
                XCTAssertEqual(q.choices.count, 4)
                XCTAssertEqual(Set(q.choices).count, 4, q.prompt)
                XCTAssertTrue(q.choices.indices.contains(q.answerIndex))
                if q.prompt.hasPrefix("Which number is largest") {
                    let values = q.choices.compactMap(Int.init)
                    XCTAssertEqual(values[q.answerIndex], values.max())
                }
            }
        }
    }

    func testMatchingGridHasExactlyOnePair() {
        var g = SeededGenerator(seed: 6)
        for difficulty in Difficulty.allCases {
            for _ in 0..<100 {
                let grid = MatchingGenerator.grid(size: MatchingGenerator.size(difficulty), using: &g)
                XCTAssertEqual(grid.symbols.count, MatchingGenerator.size(difficulty))
                XCTAssertEqual(grid.pair.count, 2)
                XCTAssertEqual(Set(grid.symbols).count, grid.symbols.count - 1)
                let indices = Array(grid.pair)
                XCTAssertEqual(grid.symbols[indices[0]], grid.symbols[indices[1]])
            }
        }
    }

    func testDefaultGoalsAreInRange() {
        for kind in ChallengeKind.allCases {
            for difficulty in Difficulty.allCases {
                XCTAssertTrue(kind.goalRange.contains(kind.defaultGoal(difficulty)), "\(kind) \(difficulty)")
            }
        }
    }
}

final class RepCounterTests: XCTestCase {
    func testCountsSmoothRepetitions() {
        var counter = RepCounter()
        var completed = 0
        for i in 0..<(5 * 40) {
            let position = 0.5 + 0.2 * cos(Double(i) / 40 * 2 * .pi)
            if counter.add(position) { completed += 1 }
        }
        XCTAssertEqual(completed, 5)
        XCTAssertEqual(counter.reps, 5)
    }

    func testIgnoresSmallJitter() {
        var counter = RepCounter()
        var g = SeededGenerator(seed: 7)
        for _ in 0..<500 { _ = counter.add(0.5 + Double.random(in: -0.02...0.02, using: &g)) }
        XCTAssertEqual(counter.reps, 0)
    }
}

final class PersistenceTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTrip() throws {
        let store = Persistence(directory: directory)
        var data = AppData()
        data.prefs.name = "Jackson"
        data.alarm.hour = 6
        data.alarm.minute = 15
        data.alarm.repeatDays = [.monday, .thursday]
        data.alarm.steps = [ChallengeStep(kind: .squats, difficulty: .medium), ChallengeStep(kind: .typing)]
        data.onboardingDone = true
        try store.save(data)
        XCTAssertEqual(Persistence(directory: directory).load(), data)
    }

    private func assertDefaults(_ data: AppData, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(data.onboardingDone, file: file, line: line)
        XCTAssertEqual(data.prefs.name, "", file: file, line: line)
        XCTAssertEqual(data.alarm.hour, AlarmConfig().hour, file: file, line: line)
        XCTAssertFalse(data.alarm.enabled, file: file, line: line)
        XCTAssertEqual(data.items.map(\.name), HouseholdItem.defaults.map(\.name), file: file, line: line)
    }

    func testMissingFileGivesDefaults() {
        assertDefaults(Persistence(directory: directory).load())
    }

    func testCorruptFileGivesDefaults() throws {
        let store = Persistence(directory: directory)
        try Data("not json".utf8).write(to: store.fileURL)
        assertDefaults(store.load())
    }

    func testExportImportRoundTrip() throws {
        var data = AppData()
        data.prefs.accent = .ocean
        data.alarm.hour = 5
        data.destinations = [QRDestination(name: "Bathroom mirror")]
        let exported = try Persistence.export(data)
        let imported = try Persistence.importing(exported, into: AppData())
        XCTAssertEqual(imported.prefs.accent, .ocean)
        XCTAssertEqual(imported.alarm.hour, 5)
        XCTAssertEqual(imported.destinations.map(\.name), ["Bathroom mirror"])
    }

    func testImportRejectsOtherFiles() {
        XCTAssertThrowsError(try Persistence.importing(Data("{\"hello\": 1}".utf8), into: AppData()))
        XCTAssertThrowsError(try Persistence.importing(Data("garbage".utf8), into: AppData()))
    }

    func testImportClampsValues() throws {
        var data = AppData()
        data.alarm.hour = 99
        data.alarm.volume = 7
        data.alarm.snooze.maxCount = 500
        var step = ChallengeStep(kind: .math)
        step.goal = 1000
        data.alarm.steps = Array(repeating: step, count: 20)
        data.alarm.soundID = "../../etc/passwd"
        let imported = try Persistence.importing(try Persistence.export(data), into: AppData())
        XCTAssertEqual(imported.alarm.hour, 23)
        XCTAssertEqual(imported.alarm.volume, 1)
        XCTAssertEqual(imported.alarm.snooze.maxCount, 10)
        XCTAssertEqual(imported.alarm.steps.count, AlarmConfig.maxSteps)
        XCTAssertEqual(imported.alarm.steps[0].goal, ChallengeKind.math.goalRange.upperBound)
        XCTAssertEqual(imported.alarm.soundID, SoundLibrary.builtIn[0].id)
    }

    func testEraseAllRemovesData() throws {
        let store = Persistence(directory: directory)
        var data = AppData()
        data.prefs.name = "Someone"
        try store.save(data)
        store.eraseAll()
        assertDefaults(store.load())
    }
}

final class SoundTests: XCTestCase {
    func testAtLeastFourteenDistinctBuiltInSounds() {
        XCTAssertGreaterThanOrEqual(SoundLibrary.builtIn.count, 14)
        XCTAssertEqual(Set(SoundLibrary.builtIn.map(\.id)).count, SoundLibrary.builtIn.count)
    }

    func testEveryBuiltInSoundIsARealPlayableFile() throws {
        for sound in SoundLibrary.builtIn {
            let url = try XCTUnwrap(SoundLibrary.url(for: sound), "\(sound.name) is missing from the bundle")
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertGreaterThan(player.duration, 10, sound.name)
            XCTAssertLessThanOrEqual(player.duration, 30, "\(sound.name) is longer than iOS allows for alarm sounds")
        }
        XCTAssertNotNil(Bundle.main.url(forResource: "silence", withExtension: "wav"))
    }

    func testSoundsAreNotSilent() throws {
        for sound in SoundLibrary.builtIn {
            let file = try AVAudioFile(forReading: try XCTUnwrap(SoundLibrary.url(for: sound)))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
            XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.3, "\(sound.name) is too quiet")
        }
    }
}

@MainActor
final class ChallengeRunnerTests: XCTestCase {
    func testSequenceProgressesAndFinishes() {
        let runner = ChallengeRunner(steps: [ChallengeStep(kind: .math), ChallengeStep(kind: .typing)], isTest: true)
        XCTAssertEqual(runner.current?.kind, .math)
        runner.completeStep()
        XCTAssertEqual(runner.current?.kind, .typing)
        XCTAssertFalse(runner.finished)
        runner.completeStep()
        XCTAssertTrue(runner.finished)
        XCTAssertNil(runner.current)
    }

    func testRestartGoesBackToTheFirstStep() {
        let runner = ChallengeRunner(steps: [ChallengeStep(kind: .math), ChallengeStep(kind: .memory)], isTest: true)
        runner.completeStep()
        runner.restart()
        XCTAssertEqual(runner.index, 0)
    }

    func testRestPeriodPausesBeforeTheNextStep() {
        var first = ChallengeStep(kind: .math)
        first.restSeconds = 10
        let runner = ChallengeRunner(steps: [first, ChallengeStep(kind: .logic)], isTest: true)
        runner.completeStep()
        XCTAssertEqual(runner.restRemaining, 10)
        runner.skipRest()
        XCTAssertEqual(runner.current?.kind, .logic)
    }

    func testResumeIndexIsClamped() {
        let runner = ChallengeRunner(steps: [ChallengeStep(kind: .math)], isTest: false, startIndex: 9)
        XCTAssertEqual(runner.index, 0)
    }
}
