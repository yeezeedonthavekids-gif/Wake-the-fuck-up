import SwiftUI

/// Shows the current step of a runner, with rest periods and sequence progress.
struct ChallengeRunnerView: View {
    @ObservedObject var runner: ChallengeRunner
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            if runner.steps.count > 1 {
                SegmentBar(count: runner.steps.count, current: runner.finished ? runner.steps.count : runner.index)
                Kicker(text: "Step \(min(runner.index + 1, runner.steps.count)) of \(runner.steps.count)")
            }
            if let notice = runner.notice {
                Banner(text: notice, symbol: "timer", tint: Palette.warn)
            }
            if let rest = runner.restRemaining {
                VStack(spacing: 14) {
                    Headline(text: "Rest", size: .title)
                    ProgressRing(value: rest, total: max(rest, runner.steps[runner.index].restSeconds), caption: "seconds")
                    Button("Skip rest") { runner.skipRest() }.buttonStyle(SecondaryButtonStyle())
                }
            } else if let step = runner.current {
                ChallengeStepView(step: step, onDone: runner.completeStep)
                    .id("\(runner.index)-\(runner.attempt)")
            }
        }
    }
}

struct ChallengeStepView: View {
    let step: ChallengeStep
    let onDone: () -> Void

    var body: some View {
        switch step.kind {
        case .math: MathChallengeView(step: step, onDone: onDone)
        case .memory: MemoryChallengeView(step: step, onDone: onDone)
        case .typing: TypingChallengeView(step: step, onDone: onDone)
        case .logic: LogicChallengeView(step: step, onDone: onDone)
        case .tapSequence: TapSequenceView(step: step, onDone: onDone)
        case .matching: MatchingChallengeView(step: step, onDone: onDone)
        case .findItem: FindItemChallengeView(step: step, onDone: onDone)
        case .qrDestination: QRDestinationChallengeView(step: step, onDone: onDone)
        case .squats, .pushups: RepChallengeView(step: step, onDone: onDone)
        case .eyesOpen: EyesOpenChallengeView(step: step, onDone: onDone)
        }
    }
}

/// Used when a step can't run here (no camera, nothing set up): five medium math questions instead.
struct BackupChallengeView: View {
    let reason: String
    let onDone: () -> Void

    private var step: ChallengeStep {
        var s = ChallengeStep(kind: .math, difficulty: .medium)
        s.goal = 5
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Banner(text: "\(reason) Solve 5 math questions instead.", symbol: "arrow.triangle.branch", tint: Palette.warn)
            MathChallengeView(step: step, onDone: onDone)
        }
    }
}

private struct StepTitle: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.weight(.semibold)).foregroundStyle(Palette.text1)
            if let detail { Text(detail).font(.subheadline).foregroundStyle(Palette.text2) }
        }
    }
}

// MARK: - Math

struct MathChallengeView: View {
    let step: ChallengeStep
    let onDone: () -> Void
    @State private var solved = 0
    @State private var problem = MathProblem(text: "", answer: 0)
    @State private var answer = ""
    @State private var feedback: String? = nil
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(title: "Question \(solved + 1) of \(step.goal)", detail: nil)
            Text(problem.text)
                .font(.system(size: 46, design: .serif))
                .foregroundStyle(Palette.text1)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityLabel(problem.spoken)
            TextField("Answer", text: $answer)
                .keyboardType(.numberPad)
                .focused($focused)
                .inputField()
                .accessibilityLabel("Your answer")
            if let feedback {
                Text(feedback).font(.subheadline).foregroundStyle(Palette.warn)
            }
            Button("Check answer", action: check)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(answer.isEmpty)
        }
        .onAppear {
            problem = next()
            focused = true
        }
    }

    private func next() -> MathProblem {
        var generator = SystemRandomNumberGenerator()
        return MathGenerator.make(step.difficulty, using: &generator)
    }

    private func check() {
        if Int(answer.trimmingCharacters(in: .whitespaces)) == problem.answer {
            solved += 1
            feedback = nil
            Haptics.success()
            if solved >= step.goal { onDone() } else { problem = next() }
        } else {
            Haptics.warning()
            feedback = "Not quite. Here's a new one."
            problem = next()
        }
        answer = ""
    }
}

// MARK: - Memory

struct MemoryChallengeView: View {
    let step: ChallengeStep
    let onDone: () -> Void
    @Environment(\.theme) private var theme

    private enum Phase { case ready, showing, answering }
    @State private var phase = Phase.ready
    @State private var sequence: [Int] = []
    @State private var shown: Int? = nil
    @State private var input: [Int] = []
    @State private var feedback: String? = nil

    private var style: MemoryStyle { step.memoryStyle }
    private static let colors: [Color] = [.red, .blue, .green, .yellow, .purple, .orange]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(title: "Remember \(step.goal) \(style.title.lowercased())",
                      detail: phase == .answering ? "Now repeat them in order." : "Watch closely. They appear one at a time.")
            if let feedback { Text(feedback).font(.subheadline).foregroundStyle(Palette.warn) }
            switch phase {
            case .ready:
                Button("Show me the sequence", action: start).buttonStyle(PrimaryButtonStyle())
            case .showing:
                ZStack {
                    RoundedRectangle(cornerRadius: theme.radius, style: .continuous).fill(Palette.raised)
                    if let shown { item(shown, size: 90) }
                }
                .frame(height: 170)
                .accessibilityElement()
                .accessibilityLabel(shown.map { MemoryGenerator.name($0, style: style) } ?? "")
            case .answering:
                HStack(spacing: 6) {
                    ForEach(Array(input.enumerated()), id: \.offset) { _, value in item(value, size: 26) }
                    ForEach(input.count..<sequence.count, id: \.self) { _ in
                        Circle().strokeBorder(Palette.line, lineWidth: 2).frame(width: 26, height: 26)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: style == .numbers ? 5 : 3), spacing: 10) {
                    ForEach(0..<MemoryGenerator.alphabetSize(style), id: \.self) { value in
                        Button { press(value) } label: {
                            item(value, size: 34)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(Palette.raised, in: RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(MemoryGenerator.name(value, style: style))
                    }
                }
                Button("Undo") { if !input.isEmpty { input.removeLast() } }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(input.isEmpty)
            }
        }
    }

    @ViewBuilder private func item(_ value: Int, size: CGFloat) -> some View {
        switch style {
        case .numbers:
            Text("\(value)").font(.system(size: size, weight: .semibold, design: .rounded)).foregroundStyle(Palette.text1)
        case .colors:
            Circle().fill(Self.colors[value]).frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Palette.line))
        case .symbols:
            Image(systemName: MemoryGenerator.symbols[value]).font(.system(size: size * 0.8)).foregroundStyle(theme.accent)
        }
    }

    private func start() {
        var generator = SystemRandomNumberGenerator()
        sequence = MemoryGenerator.sequence(length: step.goal, style: style, using: &generator)
        input = []
        feedback = nil
        phase = .showing
        let per = MemoryGenerator.secondsPerItem(step.difficulty)
        Task {
            for value in sequence {
                shown = value
                try? await Task.sleep(for: .seconds(per))
                shown = nil
                try? await Task.sleep(for: .milliseconds(180))
            }
            phase = .answering
        }
    }

    private func press(_ value: Int) {
        Haptics.tap()
        input.append(value)
        guard input.count == sequence.count else { return }
        if input == sequence {
            Haptics.success()
            onDone()
        } else {
            Haptics.warning()
            feedback = "That wasn't it. Here's a new sequence."
            phase = .ready
        }
    }
}

// MARK: - Typing

struct TypingChallengeView: View {
    let step: ChallengeStep
    let onDone: () -> Void
    @State private var target = ""
    @State private var input = ""
    @State private var done = 0
    @State private var feedback: String? = nil
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(title: "Sentence \(done + 1) of \(step.goal)", detail: toleranceText)
            Text(target)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Palette.text1)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            TextField("Type it here", text: $input, axis: .vertical)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit(check)
                .inputField()
            if let feedback { Text(feedback).font(.subheadline).foregroundStyle(Palette.warn) }
            Button("Check", action: check).buttonStyle(PrimaryButtonStyle()).disabled(input.isEmpty)
        }
        .onAppear {
            target = next()
            focused = true
        }
    }

    private var toleranceText: String {
        switch step.difficulty {
        case .easy: "Up to 3 small typos are fine. Capitals and punctuation don't matter."
        case .medium: "One small typo is fine. Capitals and punctuation don't matter."
        case .hard: "Type it exactly, including capitals and punctuation."
        }
    }

    private func next() -> String {
        var generator = SystemRandomNumberGenerator()
        return TypingGenerator.phrase(step.difficulty, using: &generator)
    }

    private func check() {
        if TypingGenerator.accepts(input, target: target, difficulty: step.difficulty) {
            done += 1
            feedback = nil
            Haptics.success()
            if done >= step.goal { onDone() } else { target = next() }
        } else {
            Haptics.warning()
            feedback = "Not quite. Check the sentence and try again."
        }
        input = ""
    }
}

// MARK: - Logic

struct LogicChallengeView: View {
    let step: ChallengeStep
    let onDone: () -> Void
    @State private var question = LogicQuestion(prompt: "", choices: [], answerIndex: 0)
    @State private var solved = 0
    @State private var feedback: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(title: "Question \(solved + 1) of \(step.goal)", detail: nil)
            Text(question.prompt).font(.system(.title2, design: .serif)).foregroundStyle(Palette.text1)
            if let feedback { Text(feedback).font(.subheadline).foregroundStyle(Palette.warn) }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
                    Button(choice) { pick(index) }.buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .onAppear { question = next() }
    }

    private func next() -> LogicQuestion {
        var generator = SystemRandomNumberGenerator()
        return LogicGenerator.make(step.difficulty, using: &generator)
    }

    private func pick(_ index: Int) {
        if index == question.answerIndex {
            solved += 1
            feedback = nil
            Haptics.success()
            if solved >= step.goal { onDone() } else { question = next() }
        } else {
            Haptics.warning()
            feedback = "Not that one. Try a new question."
            question = next()
        }
    }
}

// MARK: - Tap in order

struct TapSequenceView: View {
    let step: ChallengeStep
    let onDone: () -> Void
    @Environment(\.theme) private var theme
    @State private var tiles: [Int] = []
    @State private var nextNumber = 1
    @State private var feedback: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(title: "Tap 1 to \(step.goal) in order",
                      detail: step.difficulty == .easy ? "Wrong taps don't reset you." : "A wrong tap starts you over.")
            if let feedback { Text(feedback).font(.subheadline).foregroundStyle(Palette.warn) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: step.goal > 9 ? 4 : 3), spacing: 10) {
                ForEach(tiles, id: \.self) { number in
                    let done = number < nextNumber
                    Button { tap(number) } label: {
                        Text("\(number)")
                            .font(.title2.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .foregroundStyle(done ? theme.accentInk : Palette.text1)
                            .background(done ? theme.accent : Palette.raised, in: RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(done)
                }
            }
        }
        .onAppear { tiles = Array(1...step.goal).shuffled() }
    }

    private func tap(_ number: Int) {
        if number == nextNumber {
            Haptics.tap()
            nextNumber += 1
            feedback = nil
            if nextNumber > step.goal { onDone() }
        } else {
            Haptics.warning()
            if step.difficulty == .easy {
                feedback = "Look for \(nextNumber)."
            } else {
                feedback = "Wrong tile. Start again from 1."
                nextNumber = 1
                if step.difficulty == .hard { tiles.shuffle() }
            }
        }
    }
}

// MARK: - Find the pair

struct MatchingChallengeView: View {
    let step: ChallengeStep
    let onDone: () -> Void
    @Environment(\.theme) private var theme
    @State private var symbols: [String] = []
    @State private var pair: Set<Int> = []
    @State private var selected: Set<Int> = []
    @State private var rounds = 0
    @State private var feedback: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(title: "Round \(rounds + 1) of \(step.goal)", detail: "One symbol appears twice. Tap both.")
            if let feedback { Text(feedback).font(.subheadline).foregroundStyle(Palette.warn) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                    Button { tap(index) } label: {
                        Image(systemName: symbol)
                            .font(.title)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .foregroundStyle(selected.contains(index) ? theme.accentInk : theme.accent)
                            .background(selected.contains(index) ? theme.accent : Palette.raised,
                                        in: RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " "))
                }
            }
        }
        .onAppear(perform: newRound)
    }

    private func newRound() {
        var generator = SystemRandomNumberGenerator()
        let grid = MatchingGenerator.grid(size: MatchingGenerator.size(step.difficulty), using: &generator)
        symbols = grid.symbols
        pair = grid.pair
        selected = []
    }

    private func tap(_ index: Int) {
        Haptics.tap()
        if selected.contains(index) {
            selected.remove(index)
            return
        }
        selected.insert(index)
        guard selected.count == 2 else { return }
        if selected == pair {
            rounds += 1
            feedback = nil
            Haptics.success()
            if rounds >= step.goal { onDone() } else { newRound() }
        } else {
            Haptics.warning()
            feedback = "Those don't match. Try again."
            selected = []
        }
    }
}
