import Foundation

/// Deterministic generator for tests. The app itself uses SystemRandomNumberGenerator.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Math

struct MathProblem: Equatable {
    let text: String
    let answer: Int

    /// "12 × 4 + 7" read aloud by VoiceOver.
    var spoken: String {
        text.replacingOccurrences(of: "×", with: "times")
            .replacingOccurrences(of: "÷", with: "divided by")
            .replacingOccurrences(of: "−", with: "minus")
            .replacingOccurrences(of: "+", with: "plus")
    }
}

/// Every answer is a whole number of zero or more, and division always comes out exactly.
enum MathGenerator {
    static func make<G: RandomNumberGenerator>(_ difficulty: Difficulty, using g: inout G) -> MathProblem {
        switch difficulty {
        case .easy:
            let a = Int.random(in: 2...20, using: &g)
            let b = Int.random(in: 1...10, using: &g)
            if Bool.random(using: &g) { return MathProblem(text: "\(a) + \(b)", answer: a + b) }
            return MathProblem(text: "\(max(a, b)) − \(min(a, b))", answer: max(a, b) - min(a, b))
        case .medium:
            switch Int.random(in: 0..<4, using: &g) {
            case 0:
                let a = Int.random(in: 12...99, using: &g), b = Int.random(in: 12...99, using: &g)
                return MathProblem(text: "\(a) + \(b)", answer: a + b)
            case 1:
                let a = Int.random(in: 30...99, using: &g), b = Int.random(in: 11...(a - 1), using: &g)
                return MathProblem(text: "\(a) − \(b)", answer: a - b)
            case 2:
                let a = Int.random(in: 3...12, using: &g), b = Int.random(in: 3...9, using: &g)
                return MathProblem(text: "\(a) × \(b)", answer: a * b)
            default:
                let b = Int.random(in: 2...9, using: &g), q = Int.random(in: 2...12, using: &g)
                return MathProblem(text: "\(b * q) ÷ \(b)", answer: q)
            }
        case .hard:
            switch Int.random(in: 0..<3, using: &g) {
            case 0:
                let a = Int.random(in: 6...15, using: &g), b = Int.random(in: 3...9, using: &g), c = Int.random(in: 11...60, using: &g)
                return MathProblem(text: "\(a) × \(b) + \(c)", answer: a * b + c)
            case 1:
                let b = Int.random(in: 3...9, using: &g), q = Int.random(in: 4...15, using: &g), c = Int.random(in: 2...q, using: &g)
                return MathProblem(text: "\(b * q) ÷ \(b) − \(c)", answer: q - c)
            default:
                let a = Int.random(in: 11...40, using: &g), b = Int.random(in: 11...40, using: &g), c = Int.random(in: 2...6, using: &g)
                return MathProblem(text: "(\(a) + \(b)) × \(c)", answer: (a + b) * c)
            }
        }
    }
}

// MARK: - Memory

enum MemoryGenerator {
    static let colorNames = ["Red", "Blue", "Green", "Yellow", "Purple", "Orange"]
    static let symbols = ["star.fill", "heart.fill", "moon.fill", "bolt.fill", "leaf.fill", "drop.fill"]
    static let symbolNames = ["Star", "Heart", "Moon", "Bolt", "Leaf", "Drop"]

    static func alphabetSize(_ style: MemoryStyle) -> Int { style == .numbers ? 10 : 6 }

    /// Indexes into the style's alphabet. No item repeats twice in a row, which is hard to follow.
    static func sequence<G: RandomNumberGenerator>(length: Int, style: MemoryStyle, using g: inout G) -> [Int] {
        var result: [Int] = []
        let size = alphabetSize(style)
        while result.count < length {
            let next = Int.random(in: 0..<size, using: &g)
            if next != result.last { result.append(next) }
        }
        return result
    }

    static func secondsPerItem(_ difficulty: Difficulty) -> Double {
        switch difficulty {
        case .easy: 1.1
        case .medium: 0.8
        case .hard: 0.55
        }
    }

    static func name(_ index: Int, style: MemoryStyle) -> String {
        switch style {
        case .numbers: "\(index)"
        case .colors: colorNames[index]
        case .symbols: symbolNames[index]
        }
    }
}

// MARK: - Typing

enum TypingGenerator {
    static let subjects = ["the sleepy cat", "a bright morning", "my warm coffee", "the quiet street", "a blue kettle",
                           "the early bird", "fresh orange juice", "the open window", "a small green plant", "the morning sun"]
    static let verbs = ["waits for", "shines on", "sits beside", "rolls past", "drifts over",
                        "leans against", "hums near", "looks at", "follows", "rests on"]
    static let objects = ["the kitchen table", "seven paper boats", "a sunny window", "the green door", "two striped socks",
                          "the garden path", "a stack of books", "the river bank", "a red bicycle", "the soft pillow"]
    static let extras = ["before breakfast", "at half past six", "without a sound", "in the cool air",
                         "on a Tuesday", "for twelve minutes"]

    static func phrase<G: RandomNumberGenerator>(_ difficulty: Difficulty, using g: inout G) -> String {
        let subject = subjects.randomElement(using: &g)!
        let verb = verbs.randomElement(using: &g)!
        let object = objects.randomElement(using: &g)!
        switch difficulty {
        case .easy:
            return "\(subject) \(verb) \(object)"
        case .medium:
            return "\(subject) \(verb) \(object) \(extras.randomElement(using: &g)!)"
        case .hard:
            let number = Int.random(in: 12...98, using: &g)
            let first = subject.prefix(1).uppercased() + subject.dropFirst()
            return "\(first) \(verb) \(object), \(extras.randomElement(using: &g)!), and \(number) more."
        }
    }

    /// Typos allowed, counted as single-character edits.
    static func tolerance(_ difficulty: Difficulty) -> Int {
        switch difficulty {
        case .easy: 3
        case .medium: 1
        case .hard: 0
        }
    }

    /// Easy and medium ignore case and punctuation; hard compares exactly apart from spacing.
    static func normalize(_ text: String, strict: Bool) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !strict else { return collapsed }
        return String(collapsed.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " })
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return previous[b.count]
    }

    static func accepts(_ input: String, target: String, difficulty: Difficulty) -> Bool {
        let strict = difficulty == .hard
        return distance(normalize(input, strict: strict), normalize(target, strict: strict)) <= tolerance(difficulty)
    }
}

// MARK: - Logic

struct LogicQuestion: Equatable {
    let prompt: String
    let choices: [String]
    let answerIndex: Int
}

enum LogicGenerator {
    static func make<G: RandomNumberGenerator>(_ difficulty: Difficulty, using g: inout G) -> LogicQuestion {
        switch Int.random(in: 0..<3, using: &g) {
        case 0:
            let start = Int.random(in: 1...20, using: &g)
            let step = difficulty == .easy ? Int.random(in: 2...5, using: &g) : Int.random(in: 3...12, using: &g)
            let shown = (0..<4).map { String(start + $0 * step) }.joined(separator: ", ")
            return choices(prompt: "What comes next?\n\(shown), ?", answer: start + 4 * step, spread: step, using: &g)
        case 1:
            let start = Int.random(in: 1...5, using: &g)
            let ratio = difficulty == .hard ? 3 : 2
            let terms = (0..<4).map { start * Int(pow(Double(ratio), Double($0))) }
            let answer = terms[3] * ratio
            return choices(prompt: "What comes next?\n\(terms.map(String.init).joined(separator: ", ")), ?", answer: answer, spread: max(2, terms[3] / 2), using: &g)
        default:
            let base = difficulty == .easy ? Int.random(in: 10...50, using: &g) : Int.random(in: 100...900, using: &g)
            let gap = difficulty == .hard ? 3 : 9
            var values = Set<Int>()
            while values.count < 4 { values.insert(base + Int.random(in: -gap * 4...gap * 4, using: &g)) }
            let list = Array(values).shuffled(using: &g)
            let answer = list.firstIndex(of: list.max()!)!
            return LogicQuestion(prompt: "Which number is largest?", choices: list.map(String.init), answerIndex: answer)
        }
    }

    /// Builds four distinct choices around the answer.
    private static func choices<G: RandomNumberGenerator>(prompt: String, answer: Int, spread: Int, using g: inout G) -> LogicQuestion {
        var options: Set<Int> = [answer]
        var offset = 1
        while options.count < 4 {
            let candidate = answer + (Bool.random(using: &g) ? 1 : -1) * max(1, spread / 2) * offset + Int.random(in: -1...1, using: &g)
            if candidate >= 0 { options.insert(candidate) }
            offset += 1
        }
        let list = Array(options).shuffled(using: &g)
        return LogicQuestion(prompt: prompt, choices: list.map(String.init), answerIndex: list.firstIndex(of: answer)!)
    }
}

// MARK: - Find the pair

enum MatchingGenerator {
    static let pool = ["sun.max.fill", "moon.fill", "star.fill", "cloud.fill", "bolt.fill", "leaf.fill", "flame.fill", "drop.fill",
                       "heart.fill", "bell.fill", "key.fill", "cup.and.saucer.fill", "book.fill", "music.note", "camera.fill", "paperplane.fill"]

    static func size(_ difficulty: Difficulty) -> Int {
        switch difficulty {
        case .easy: 6
        case .medium: 9
        case .hard: 12
        }
    }

    /// A grid where exactly one symbol appears twice.
    static func grid<G: RandomNumberGenerator>(size: Int, using g: inout G) -> (symbols: [String], pair: Set<Int>) {
        var picks = Array(pool.shuffled(using: &g).prefix(size - 1))
        let duplicate = picks.randomElement(using: &g)!
        picks.append(duplicate)
        picks.shuffle(using: &g)
        return (picks, Set(picks.indices.filter { picks[$0] == duplicate }))
    }
}

// MARK: - Rep counting

/// Counts squats or push-ups from a stream of normalized vertical positions (0 is the bottom
/// of the camera frame, 1 the top). A rep is a fall of at least `minimumTravel` followed by a
/// rise back most of the way. It's an estimate, not a medical measurement.
struct RepCounter {
    private(set) var reps = 0
    let minimumTravel: Double
    private var smoothed: Double?
    private var high = -Double.infinity
    private var low = Double.infinity
    private var goingDown = false

    init(minimumTravel: Double = 0.08) { self.minimumTravel = minimumTravel }

    /// Returns true when a repetition completes.
    mutating func add(_ position: Double) -> Bool {
        let value = smoothed.map { $0 * 0.6 + position * 0.4 } ?? position
        smoothed = value
        if goingDown {
            low = min(low, value)
            if high - low >= minimumTravel, value >= low + (high - low) * 0.6 {
                reps += 1
                goingDown = false
                high = value
                return true
            }
        } else {
            high = max(high, value)
            if value <= high - minimumTravel {
                goingDown = true
                low = value
            }
        }
        return false
    }
}
