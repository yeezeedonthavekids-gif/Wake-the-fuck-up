import SwiftUI

struct TutorialPage: Identifiable {
    let id: Int
    let title: String
    let symbol: String
    let body: String
    let points: [String]
}

enum TutorialContent {
    static let pages: [TutorialPage] = [
        TutorialPage(id: 0, title: "Set the time", symbol: "clock",
                     body: "WakeUp has one alarm. Tap Edit alarm on the home screen and turn the wheel to your wake-up time.",
                     points: ["Choose 12- or 24-hour time in Settings.", "The home screen shows exactly when it rings next, and how long until then."]),
        TutorialPage(id: 1, title: "Choose repeat days", symbol: "calendar",
                     body: "Pick Every day, Weekdays, Weekends, or tap individual days.",
                     points: ["With no days chosen it rings once, then turns itself off.", "Daylight-saving and time-zone changes are handled by iOS."]),
        TutorialPage(id: 2, title: "Pick a sound", symbol: "speaker.wave.2",
                     body: "Fourteen built-in sounds, from gentle chimes to an urgent buzzer. Tap play to preview one.",
                     points: ["Only one preview plays at a time.", "You can import your own sound (up to 29 seconds)."]),
        TutorialPage(id: 3, title: "Set up your challenge", symbol: "flag.checkered",
                     body: "The challenge is what you do to stop the alarm: math, memory, typing, finding an item, scanning a code, squats and more.",
                     points: ["Each challenge has a difficulty and a goal.", "Combine up to six steps into a sequence."]),
        TutorialPage(id: 4, title: "Finishing the challenge", symbol: "checkmark.seal",
                     body: "When the alarm rings, tap Start challenge. The sound keeps going until you finish every step.",
                     points: ["Get something wrong and you simply get a new question.", "If you leave WakeUp mid-challenge, a follow-up alarm rings 5 minutes later."]),
        TutorialPage(id: 5, title: "Test it", symbol: "play.circle",
                     body: "Use Test on the home screen. Ring now tries everything instantly. A real test schedules an alarm one minute from now, so you can check it on the lock screen.",
                     points: ["Testing never changes your real alarm."]),
        TutorialPage(id: 6, title: "Snooze", symbol: "zzz",
                     body: "If you allow it, snooze schedules one more alarm a few minutes later.",
                     points: ["Set how long and how many times.", "Choose whether snoozing restarts the challenge."]),
        TutorialPage(id: 7, title: "Emergency stop", symbol: "hand.raised",
                     body: "Hold the emergency stop button for a few seconds to silence WakeUp without the challenge. It's always there.",
                     points: ["Use it whenever you need to. No guilt trips.", "VoiceOver users can activate it directly."]),
        TutorialPage(id: 8, title: "Permissions and iOS limits", symbol: "lock.shield",
                     body: "On iOS 26 WakeUp uses system alarms, which ring on the lock screen even in silent mode. iOS always shows its own Stop button there, and WakeUp can't hide it.",
                     points: ["Older iOS uses notifications, which are quieter and silent in silent mode.", "Nothing rings if your iPhone is off or out of battery.", "The camera is only used for challenges that need it, on the device."]),
        TutorialPage(id: 9, title: "Check it's scheduled", symbol: "stethoscope",
                     body: "The home screen shows a status under the time. A green check means iOS has the alarm. Settings → Diagnostics shows the details.",
                     points: ["If something fails, WakeUp tells you what and why.", "WakeUp checks again every time you open it."]),
    ]
}

struct TutorialPageView: View {
    @Environment(\.theme) private var theme
    let page: TutorialPage
    let number: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: page.symbol)
                .font(.system(size: 40))
                .foregroundStyle(theme.accent)
                .frame(width: 84, height: 84)
                .background(theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .accessibilityHidden(true)
            Kicker(text: "How WakeUp works · \(number) of \(total)")
            Headline(text: page.title)
            Text(page.body).font(.body).foregroundStyle(Palette.text2)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(page.points, id: \.self) { point in
                    Label {
                        Text(point).foregroundStyle(Palette.text1)
                    } icon: {
                        Image(systemName: "checkmark").foregroundStyle(theme.accent)
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}

/// The full tutorial, reopened from Settings.
struct TutorialReaderView: View {
    var body: some View {
        TabView {
            ForEach(TutorialContent.pages) { page in
                ScrollView {
                    TutorialPageView(page: page, number: page.id + 1, total: TutorialContent.pages.count)
                        .padding(20)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(AppBackground())
        .navigationTitle("Tutorial")
        .navigationBarTitleDisplayMode(.inline)
    }
}
