import Foundation

/// Walks through a challenge sequence: progress, rest periods, retries and the optional time limit.
@MainActor
final class ChallengeRunner: ObservableObject {
    let steps: [ChallengeStep]
    let isTest: Bool
    let maxDuration: TimeInterval?

    @Published private(set) var index: Int
    /// Changes whenever a step should start fresh (retry, restart), so its view rebuilds.
    @Published private(set) var attempt = 0
    @Published private(set) var restRemaining: Int?
    @Published private(set) var finished = false
    @Published var notice: String?

    /// Called after each completed step, so the alarm can push its follow-up ring back.
    var onStepComplete: (() -> Void)?

    private var startedAt = Date()
    private var restTimer: Timer?

    init(steps: [ChallengeStep], isTest: Bool, maxDuration: TimeInterval? = nil, startIndex: Int = 0) {
        self.steps = steps
        self.isTest = isTest
        self.maxDuration = maxDuration
        index = steps.isEmpty ? 0 : startIndex.clamped(to: 0...(steps.count - 1))
        finished = steps.isEmpty
    }

    var current: ChallengeStep? { finished || index >= steps.count ? nil : steps[index] }
    var completedCount: Int { finished ? steps.count : index }

    func completeStep() {
        guard !finished, index < steps.count else { return }
        onStepComplete?()
        if let maxDuration, Date().timeIntervalSince(startedAt) > maxDuration {
            notice = "Time's up for this sequence, so it starts again."
            restart()
            return
        }
        notice = nil
        if index + 1 >= steps.count {
            finished = true
            return
        }
        let rest = steps[index].restSeconds
        if rest > 0 { startRest(rest) } else { advance() }
    }

    func retry() { attempt += 1 }

    func restart() {
        restTimer?.invalidate()
        restRemaining = nil
        index = 0
        attempt += 1
        startedAt = Date()
        finished = false
    }

    func skipRest() {
        restTimer?.invalidate()
        restRemaining = nil
        advance()
    }

    private func advance() {
        index += 1
        attempt += 1
    }

    private func startRest(_ seconds: Int) {
        restRemaining = seconds
        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickRest() }
        }
    }

    private func tickRest() {
        guard let remaining = restRemaining else { return }
        if remaining > 1 {
            restRemaining = remaining - 1
        } else {
            skipRest()
        }
    }
}
