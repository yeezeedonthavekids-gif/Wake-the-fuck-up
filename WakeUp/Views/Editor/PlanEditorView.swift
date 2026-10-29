import SwiftUI

struct TestPlan: Identifiable {
    let id = UUID()
    let steps: [ChallengeStep]
}

/// Builds the challenge sequence: add, remove, reorder, configure and preview steps.
struct PlanEditorView: View {
    @Binding var config: AlarmConfig
    @State private var adding = false
    @State private var testing: TestPlan? = nil

    var body: some View {
        List {
            Section {
                ForEach($config.steps) { $step in
                    NavigationLink {
                        StepEditorView(step: $step)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.kind.title).foregroundStyle(Palette.text1)
                                Text("\(step.difficulty.title) · \(step.label)\(step.restSeconds > 0 ? " · rest \(step.restSeconds) s" : "")")
                                    .font(.footnote).foregroundStyle(Palette.text2)
                            }
                        } icon: {
                            Image(systemName: step.kind.symbol)
                        }
                    }
                }
                .onDelete { offsets in
                    config.steps.remove(atOffsets: offsets)
                    if config.steps.isEmpty { config.steps = [ChallengeStep(kind: .math)] }
                }
                .onMove { config.steps.move(fromOffsets: $0, toOffset: $1) }
                if config.steps.count < AlarmConfig.maxSteps {
                    Button {
                        adding = true
                    } label: {
                        Label("Add a step", systemImage: "plus.circle.fill")
                    }
                }
            } header: {
                Text("Steps, in order")
            } footer: {
                Text("Use Edit to drag steps into a new order. Swipe left to remove one. Up to \(AlarmConfig.maxSteps) steps.")
            }
            Section("Preview") {
                ForEach(Array(config.steps.enumerated()), id: \.element.id) { index, step in
                    Text("\(index + 1). \(step.label)").font(.subheadline)
                }
                Button("Test the whole sequence") { testing = TestPlan(steps: config.steps) }
            }
            Section {
                Picker("Time limit", selection: $config.maxDurationMinutes) {
                    Text("None").tag(0)
                    ForEach([5, 10, 15, 20, 30], id: \.self) { Text("\($0) minutes").tag($0) }
                }
            } footer: {
                Text("If the whole sequence takes longer than this, it starts again. The alarm keeps ringing either way.")
            }
        }
        .wakeForm()
        .navigationTitle("Challenge plan")
        .toolbar { EditButton() }
        .sheet(isPresented: $adding) {
            ChallengeLibraryView { kind in config.steps.append(ChallengeStep(kind: kind)) }
        }
        .fullScreenCover(item: $testing) { plan in ChallengeTestScreen(steps: plan.steps) }
    }
}

struct StepEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var step: ChallengeStep
    @State private var testing: TestPlan? = nil

    var body: some View {
        Form {
            Section {
                Label(step.kind.title, systemImage: step.kind.symbol).font(.headline)
                Text(step.kind.summary).foregroundStyle(Palette.text2)
            }
            Section("Difficulty") {
                Picker("Difficulty", selection: $step.difficulty) {
                    ForEach(Difficulty.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: step.difficulty) { _, level in step.goal = step.kind.defaultGoal(level) }
            }
            if step.kind.goalRange.count > 1 {
                Section("Goal") {
                    Stepper("\(step.goal) \(step.kind.goalUnit)", value: $step.goal, in: step.kind.goalRange)
                }
            }
            kindOptions
            Section {
                Stepper(step.restSeconds == 0 ? "No rest after this step" : "Rest \(step.restSeconds) s after this step",
                        value: $step.restSeconds, in: 0...60, step: 5)
            }
            Section("What it can and can't check") {
                Text(step.kind.limitation).font(.subheadline)
                if let permission = step.kind.permission {
                    Label("Uses: \(permission). WakeUp asks the first time it's needed.", systemImage: "lock.shield")
                        .font(.footnote).foregroundStyle(Palette.text2)
                }
            }
            Section {
                Button("Test this step") { testing = TestPlan(steps: [step]) }
            }
        }
        .wakeForm()
        .navigationTitle(step.kind.title)
        .fullScreenCover(item: $testing) { plan in ChallengeTestScreen(steps: plan.steps) }
    }

    @ViewBuilder private var kindOptions: some View {
        switch step.kind {
        case .memory:
            Section("Show") {
                Picker("Sequence of", selection: $step.memoryStyle) {
                    ForEach(MemoryStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        case .findItem:
            Section {
                Picker("Mode", selection: $step.findMode) {
                    ForEach(FindMode.allCases) { Text($0.title).tag($0) }
                }
                NavigationLink("Item library") { ItemLibraryView() }
            } footer: {
                Text(step.findMode.explanation)
            }
        case .qrDestination:
            Section {
                Picker("Destination", selection: $step.destinationID) {
                    Text("First available").tag(UUID?.none)
                    ForEach(model.data.destinations) { Text($0.name).tag(Optional($0.id)) }
                }
                NavigationLink("Manage QR destinations") { QRDestinationsView() }
            } footer: {
                Text(model.data.destinations.isEmpty
                     ? "You haven't made a QR destination yet. Without one, this step becomes a backup math challenge."
                     : "Print the code and put it somewhere you have to walk to, like the bathroom mirror.")
            }
        case .squats, .pushups:
            Section {
                Toggle("Camera counting (experimental)", isOn: $step.cameraCounting)
            } footer: {
                Text("Pick a number you can do comfortably. Tapping to count always works, and a low-movement alternative is always offered.")
            }
        default:
            EmptyView()
        }
    }
}

/// Lets someone try challenges without any alarm being set.
struct ChallengeTestScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @StateObject private var runner: ChallengeRunner

    init(steps: [ChallengeStep]) {
        _runner = StateObject(wrappedValue: ChallengeRunner(steps: steps, isTest: true))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Banner(text: "Test mode. No alarm is set and nothing is recorded.", symbol: "testtube.2")
                    Card {
                        if runner.finished {
                            VStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(Palette.good)
                                Headline(text: "Done!", size: .title)
                                Text("That's how completing it works when your alarm rings.").foregroundStyle(Palette.text2)
                                Button("Try again") { runner.restart() }.buttonStyle(SecondaryButtonStyle())
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            ChallengeRunnerView(runner: runner)
                        }
                    }
                }
                .padding(16)
            }
            .background(AppBackground())
            .navigationTitle("Test challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }
    }
}

/// All challenges as tiles. With `onPick`, each tile can be added to the plan.
struct ChallengeLibraryView: View {
    var onPick: ((ChallengeKind) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var testing: TestPlan? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(ChallengeCategory.allCases) { category in
                        Kicker(text: category.title)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                            ForEach(ChallengeKind.allCases.filter { $0.category == category }) { kind in
                                ChallengeTile(kind: kind, onAdd: onPick.map { pick in { pick(kind); dismiss() } }) {
                                    testing = TestPlan(steps: [ChallengeStep(kind: kind)])
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(AppBackground())
            .navigationTitle(onPick == nil ? "Challenges" : "Add a step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(onPick == nil ? "Done" : "Cancel") { dismiss() } } }
            .fullScreenCover(item: $testing) { plan in ChallengeTestScreen(steps: plan.steps) }
        }
    }
}

struct ChallengeTile: View {
    @Environment(\.theme) private var theme
    let kind: ChallengeKind
    var onAdd: (() -> Void)?
    var selected = false
    let onTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: kind.symbol)
                .font(.title2)
                .foregroundStyle(selected ? theme.accentInk : theme.accent)
                .frame(width: 46, height: 46)
                .background(selected ? theme.accent : theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            Text(kind.title).font(.headline).foregroundStyle(Palette.text1)
            Text(kind.summary).font(.footnote).foregroundStyle(Palette.text2).fixedSize(horizontal: false, vertical: true)
            Text("Default: Easy · \(kind.defaultGoal(.easy)) \(kind.goalUnit)").font(.caption).foregroundStyle(Palette.text3)
            if let permission = kind.permission {
                Label(permission, systemImage: "camera").font(.caption).foregroundStyle(Palette.text3)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if let onAdd {
                    Button("Add", action: onAdd).font(.subheadline.weight(.semibold)).buttonStyle(.borderedProminent)
                }
                Button("Test", action: onTest).font(.subheadline.weight(.semibold)).buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(Palette.sheet, in: RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.radius, style: .continuous)
            .strokeBorder(selected ? theme.accent : Palette.line, lineWidth: selected ? 2 : 1))
        .accessibilityElement(children: .contain)
    }
}
