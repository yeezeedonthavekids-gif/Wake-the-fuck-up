import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var editing = false
    @State private var showingSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.gap * 1.2) {
                header
                if let notice = model.notice {
                    Banner(text: notice) { withAnimation(theme.animation()) { model.notice = nil } }
                }
                AlarmHeroCard(editing: $editing)
                if model.data.prefs.showDashboard { DashboardSection() }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(AppBackground())
        .sheet(isPresented: $editing) { AlarmEditorView() }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $model.showTestSheet) { TestAlarmSheet().presentationDetents([.medium, .large]) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            TimelineView(.everyMinute) { context in
                Headline(text: Greeting.text(name: model.data.prefs.name, enabled: model.data.prefs.greetingEnabled, date: context.date))
            }
            Spacer()
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(Palette.text2)
                    .frame(width: 44, height: 44)
                    .background(Palette.sheet, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.line))
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 12)
    }
}

/// The one alarm: time, on/off, next ring, scheduling status and what happens when it rings.
struct AlarmHeroCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var scheduler: SchedulerService
    @Environment(\.theme) private var theme
    @Binding var editing: Bool

    private var alarm: AlarmConfig { model.data.alarm }

    var body: some View {
        Card {
            HStack {
                Kicker(text: "Your alarm")
                Spacer()
                Toggle("Alarm on", isOn: Binding(
                    get: { alarm.enabled },
                    set: { on in model.updateAlarm(requestPermission: on) { $0.enabled = on } }
                ))
                .labelsHidden()
                .tint(theme.accent)
            }
            let parts = TimeText.parts(hour: alarm.hour, minute: alarm.minute, format: model.data.prefs.timeFormat)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(parts.time)
                    .font(.system(size: 78, weight: .regular, design: .serif))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if let period = parts.period {
                    Text(period).font(.system(.title2, design: .serif))
                }
            }
            .foregroundStyle(alarm.enabled ? Palette.text1 : Palette.text3)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Alarm time \(TimeText.string(hour: alarm.hour, minute: alarm.minute, format: model.data.prefs.timeFormat)), \(alarm.enabled ? "on" : "off")")

            TimelineView(.everyMinute) { context in
                Text(nextLine(now: context.date))
                    .font(.subheadline)
                    .foregroundStyle(Palette.text2)
            }
            StatusRow(status: scheduler.status, enabled: alarm.enabled)

            Divider()
            InfoRow(symbol: "repeat", title: "Repeat", value: Weekday.summary(alarm.repeatDays))
            InfoRow(symbol: "speaker.wave.2", title: "Sound", value: model.currentSound.name)
            InfoRow(symbol: "flag.checkered", title: "Challenge", value: alarm.planSummary)
            InfoRow(symbol: "zzz", title: "Snooze",
                    value: alarm.snooze.enabled ? "\(alarm.snooze.minutes) min, up to \(alarm.snooze.maxCount)×" : "Off")

            HStack(spacing: 10) {
                Button("Edit alarm") { editing = true }.buttonStyle(PrimaryButtonStyle())
                Button("Test") { model.showTestSheet = true }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func nextLine(now: Date) -> String {
        guard alarm.enabled else { return "Off. Turn it on to schedule it." }
        guard let next = AlarmMath.nextFire(alarm, after: now) else { return "No upcoming time." }
        return "\(TimeText.dayAndTime(next, format: model.data.prefs.timeFormat, now: now)) · in \(AlarmMath.countdown(from: now, to: next))"
    }
}

struct StatusRow: View {
    @EnvironmentObject private var model: AppModel
    let status: ScheduleStatus
    let enabled: Bool

    var body: some View {
        switch status {
        case .off:
            label("moon.zzz.fill", enabled ? "Not scheduled yet" : "Nothing will ring", Palette.text3)
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                Text("Checking with iOS…").font(.subheadline).foregroundStyle(Palette.text2)
            }
        case .scheduled(_, let backend) where backend == .alarmKit:
            label("checkmark.seal.fill", "Scheduled as a system alarm", Palette.good)
        case .scheduled:
            VStack(alignment: .leading, spacing: 4) {
                label("exclamationmark.triangle.fill", "Scheduled with notifications (fallback)", Palette.warn)
                Text("Notifications play their sound once and stay silent in silent mode. Keep WakeUp open in the background for a full ringing alarm.")
                    .font(.footnote).foregroundStyle(Palette.text2)
            }
        case .needsPermission(let message), .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                label("xmark.octagon.fill", "Not scheduled", Palette.bad)
                Text(message).font(.footnote).foregroundStyle(Palette.text2)
                HStack {
                    Button("Try again") { Task { await model.reschedule(requestPermission: true) } }
                    Spacer()
                    Button("Open Settings") { SystemSettings.open() }
                }
                .font(.footnote.weight(.semibold))
            }
        }
    }

    private func label(_ symbol: String, _ text: String, _ color: Color) -> some View {
        Label {
            Text(text).foregroundStyle(Palette.text1)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
        .font(.subheadline.weight(.medium))
    }
}

/// Optional widgets under the alarm. Each can be turned off in Settings → Appearance.
struct DashboardSection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let prefs = model.data.prefs
        if prefs.showClock {
            Card {
                TimelineView(.everyMinute) { context in
                    HStack {
                        Kicker(text: "Now")
                        Spacer()
                        Text(TimeText.string(context.date, format: prefs.timeFormat))
                            .font(.system(.title, design: .serif)).foregroundStyle(Palette.text1)
                    }
                }
            }
        }
        if prefs.showMessage {
            Card {
                Kicker(text: "For the morning")
                Text(Greeting.message()).font(.system(.title3, design: .serif)).foregroundStyle(Palette.text1)
            }
        }
        if prefs.showChecklist {
            Card {
                Kicker(text: "Morning checklist")
                ForEach($model.data.prefs.checklist) { $item in
                    Button {
                        Haptics.tap()
                        item.done.toggle()
                    } label: {
                        HStack {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.done ? theme.accent : Palette.text3)
                            Text(item.title).strikethrough(item.done).foregroundStyle(item.done ? Palette.text3 : Palette.text1)
                            Spacer()
                        }
                        .font(.body)
                        .frame(minHeight: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(item.done ? .isSelected : [])
                }
                if model.data.prefs.checklist.isEmpty {
                    Text("Add items in Settings → Appearance.").font(.subheadline).foregroundStyle(Palette.text3)
                }
            }
        }
        if prefs.showHistory {
            Card {
                Kicker(text: "Recent mornings")
                let recent = model.data.history.filter { !$0.isTest }.suffix(5).reversed()
                if !prefs.historyEnabled {
                    Text("Wake-up history is off. Turn it on in Settings → Privacy.").font(.subheadline).foregroundStyle(Palette.text3)
                } else if recent.isEmpty {
                    Text("Nothing yet.").font(.subheadline).foregroundStyle(Palette.text3)
                } else {
                    ForEach(Array(recent)) { record in HistoryRow(record: record) }
                }
            }
        }
    }
}

struct HistoryRow: View {
    @EnvironmentObject private var model: AppModel
    let record: WakeRecord

    var body: some View {
        HStack {
            Image(systemName: record.outcome == .completed ? "sun.max.fill" : "moon.zzz")
                .foregroundStyle(record.outcome == .completed ? Palette.good : Palette.text3)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.subheadline.weight(.medium)).foregroundStyle(Palette.text1)
                Text("\(record.outcome.title)\(record.snoozes > 0 ? " · \(record.snoozes) snooze\(record.snoozes == 1 ? "" : "s")" : "")\(record.isTest ? " · test" : "")")
                    .font(.footnote).foregroundStyle(Palette.text2)
            }
            Spacer()
            if record.seconds > 0 {
                Text("\(record.seconds / 60) min \(record.seconds % 60) s").font(.footnote).foregroundStyle(Palette.text3)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct TestAlarmSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var result: String? = nil
    @State private var working = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Card {
                        Kicker(text: "Ring now")
                        Text("Plays your sound and runs your challenge right away. No alarm is scheduled, and nothing is recorded as a real morning.")
                            .font(.subheadline).foregroundStyle(Palette.text2)
                        Button("Ring now") {
                            dismiss()
                            model.testRingNow()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    Card {
                        Kicker(text: "Real test in 1 minute")
                        Text("Schedules a one-time alarm the same way as your real one. Lock your iPhone and wait, to check it rings on the lock screen.")
                            .font(.subheadline).foregroundStyle(Palette.text2)
                        Button(working ? "Scheduling…" : "Schedule test alarm") {
                            working = true
                            Task {
                                result = await model.scheduleTest()
                                working = false
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(working)
                        if let result { Banner(text: result) }
                    }
                }
                .padding(16)
            }
            .background(AppBackground())
            .navigationTitle("Test your alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
