import SwiftUI

/// The alarm screen. Always dark and high-contrast so it reads instantly when half asleep.
struct RingingView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var audio: AudioEngine
    @Environment(\.theme) private var theme
    let context: RingContext
    @StateObject private var runner: ChallengeRunner
    @State private var started = false
    @State private var outcome: WakeRecord.Outcome?

    init(context: RingContext) {
        self.context = context
        _runner = StateObject(wrappedValue: ChallengeRunner(steps: context.steps, isTest: context.isTest,
                                                            maxDuration: context.maxDuration, startIndex: context.startIndex))
    }

    var body: some View {
        ZStack {
            Palette.ringBase.ignoresSafeArea()
            RadialGradient(colors: [theme.accent.opacity(theme.gradients ? 0.35 : 0.15), .clear],
                           center: .top, startRadius: 20, endRadius: 520)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    clock
                    if let outcome {
                        completion(outcome)
                    } else if !started {
                        intro
                    } else {
                        Card { ChallengeRunnerView(runner: runner) }
                        snoozeButton
                    }
                    if outcome == nil {
                        HoldButton(title: "Hold to stop (emergency)", seconds: Double(context.holdSeconds)) {
                            outcome = .emergency
                            model.completeRinging(.emergency)
                        }
                        .padding(.top, 8)
                        Text("Hold for \(context.holdSeconds) seconds. Use it whenever you need to.")
                            .font(.footnote).foregroundStyle(Palette.text3)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .environment(\.colorScheme, .dark)
        .interactiveDismissDisabled()
        .onAppear {
            let appModel = model
            runner.onStepComplete = { [weak appModel] in appModel?.challengeProgressed() }
            if context.startIndex > 0 || model.screenshotScreen == "ringing-challenge" { started = true }
        }
        .onChange(of: runner.finished) { _, finished in
            guard finished, outcome == nil else { return }
            outcome = .completed
            model.completeRinging(.completed)
        }
    }

    private var clock: some View {
        VStack(spacing: 4) {
            Kicker(text: context.isTest ? "Test alarm" : "Alarm")
            TimelineView(.everyMinute) { timeline in
                Text(TimeText.string(timeline.date, format: model.data.prefs.timeFormat))
                    .font(.system(size: 76, design: .serif))
                    .foregroundStyle(Palette.text1)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            if outcome == nil {
                Label(audio.isRinging ? "Ringing" : "Sound off", systemImage: audio.isRinging ? "speaker.wave.3.fill" : "speaker.slash")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.text2)
            }
        }
        .padding(.top, 12)
    }

    private var intro: some View {
        VStack(spacing: 16) {
            Headline(text: Greeting.text(name: model.data.prefs.name, enabled: model.data.prefs.greetingEnabled), size: .title)
                .multilineTextAlignment(.center)
            Card {
                Kicker(text: context.steps.count == 1 ? "Your challenge" : "Your challenge · \(context.steps.count) steps")
                ForEach(Array(context.steps.enumerated()), id: \.element.id) { index, step in
                    Label("\(index + 1). \(step.label)", systemImage: step.kind.symbol)
                        .font(.body)
                        .foregroundStyle(Palette.text1)
                }
                if context.snoozes > 0 {
                    Text("Snoozed \(context.snoozes) time\(context.snoozes == 1 ? "" : "s").").font(.footnote).foregroundStyle(Palette.text3)
                }
            }
            Button(context.startIndex > 0 ? "Continue challenge" : "I'm up. Start the challenge") {
                Haptics.tap()
                withAnimation(theme.animation()) { started = true }
            }
            .buttonStyle(PrimaryButtonStyle())
            snoozeButton
            if !context.requireChallenge {
                Button("Stop alarm") {
                    outcome = .stoppedWithoutChallenge
                    model.completeRinging(.stoppedWithoutChallenge)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    @ViewBuilder private var snoozeButton: some View {
        if model.canSnooze(context, started: started) {
            Button("Snooze \(context.snooze.minutes) min (\(context.snooze.maxCount - context.snoozes) left)") {
                model.snooze(currentIndex: runner.index)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func completion(_ outcome: WakeRecord.Outcome) -> some View {
        Card {
            VStack(spacing: 14) {
                Image(systemName: outcome == .completed ? "sun.max.fill" : "checkmark.circle")
                    .font(.system(size: 60))
                    .foregroundStyle(outcome == .completed ? theme.accent : Palette.text2)
                    .accessibilityHidden(true)
                switch outcome {
                case .completed:
                    Headline(text: "You're up. Nice work.", size: .title)
                    Text("Alarm stopped after \(elapsed). Have a good morning.").foregroundStyle(Palette.text2)
                default:
                    Headline(text: "Alarm stopped.", size: .title)
                    Text("No problem. Look after yourself.").foregroundStyle(Palette.text2)
                }
                if context.isTest { Text("This was a test. Your real alarm is unchanged.").font(.footnote).foregroundStyle(Palette.text3) }
                Button("Done") { model.dismissRinging() }.buttonStyle(PrimaryButtonStyle())
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }

    private var elapsed: String {
        let seconds = Int(Date().timeIntervalSince(context.startedAt))
        return seconds >= 60 ? "\(seconds / 60) min \(seconds % 60) s" : "\(seconds) s"
    }
}
