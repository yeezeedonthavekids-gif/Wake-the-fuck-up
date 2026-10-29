import ARKit
import AVFoundation
import SwiftUI

// MARK: - Find an item

struct FindItemChallengeView: View {
    let step: ChallengeStep
    let onDone: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    @State private var found = 0
    @State private var target: HouseholdItem? = nil
    @State private var scanning = false
    @State private var capturing = false
    @State private var photo: UIImage? = nil
    @State private var labels: [String] = []
    @State private var analyzing = false
    @State private var feedback: String? = nil
    @State private var useBackup = false

    private var pool: [HouseholdItem] {
        let items = model.data.items.filter(\.inRandomPool)
        return items.isEmpty ? model.data.items : items
    }

    var body: some View {
        if pool.isEmpty {
            BackupChallengeView(reason: "Your item library is empty.", onDone: onDone)
        } else if useBackup {
            BackupChallengeView(reason: "The camera isn't available.", onDone: onDone)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            Kicker(text: "Item \(found + 1) of \(step.goal)")
            if let target {
                HStack(spacing: 14) {
                    Image(systemName: target.symbol)
                        .font(.system(size: 34))
                        .foregroundStyle(theme.accent)
                        .frame(width: 64, height: 64)
                        .background(theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading) {
                        Text("Find your").font(.subheadline).foregroundStyle(Palette.text2)
                        Text(target.name).font(.system(.title, design: .serif)).foregroundStyle(Palette.text1)
                    }
                }
                .accessibilityElement(children: .combine)
                if let feedback { Text(feedback).font(.subheadline).foregroundStyle(Palette.warn) }
                switch step.findMode {
                case .randomTarget: manualMode(target)
                case .qrCode: qrMode(target)
                case .photo: photoMode(target)
                }
            }
        }
        .onAppear { if target == nil { target = pool.randomElement() } }
        .sheet(isPresented: $scanning) {
            QRScannerSheet { code in
                if code == target?.qrCode { success() } else { feedback = "That's a different code. Find the one on your \(target?.name.lowercased() ?? "item")." }
            } onUnavailable: { useBackup = true }
        }
        .fullScreenCover(isPresented: $capturing) {
            CameraPhotoPicker { image in
                capturing = false
                guard let image else { return }
                photo = image
                analyze(image)
            }
            .ignoresSafeArea()
        }
    }

    private func manualMode(_ item: HouseholdItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Go and get it, then confirm. This trusts you.").font(.subheadline).foregroundStyle(Palette.text2)
            Button("I have my \(item.name.lowercased())", action: success).buttonStyle(PrimaryButtonStyle())
        }
    }

    private func qrMode(_ item: HouseholdItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scan the WakeUp code you stuck on it. Print codes from Settings → Item library.")
                .font(.subheadline).foregroundStyle(Palette.text2)
            Button("Scan the code") { scanning = true }.buttonStyle(PrimaryButtonStyle())
        }
    }

    @ViewBuilder private func photoMode(_ item: HouseholdItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let photo {
                HStack(spacing: 10) {
                    Image(uiImage: photo).resizable().scaledToFill().frame(width: 120, height: 120).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel("Your photo")
                    if let file = item.photoFile, let reference = UIImage(contentsOfFile: model.persistence.photoURL(file).path) {
                        Image(uiImage: reference).resizable().scaledToFill().frame(width: 120, height: 120).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityLabel("Your reference photo")
                    }
                }
                if analyzing {
                    ProgressView("Looking at your photo on this iPhone…")
                } else if ItemRecognizer.matches(labels, item: item) {
                    Banner(text: "Recognized: this looks like a \(item.name.lowercased()).", symbol: "checkmark.seal.fill", tint: Palette.good)
                    Button("Continue", action: success).buttonStyle(PrimaryButtonStyle())
                } else {
                    Text("WakeUp couldn't recognize it\(labels.isEmpty ? "" : " (it saw: \(labels.prefix(3).joined(separator: ", ")))"). Confirm only if it really is your \(item.name.lowercased()).")
                        .font(.subheadline).foregroundStyle(Palette.text2)
                    Button("It's my \(item.name.lowercased())", action: success).buttonStyle(PrimaryButtonStyle())
                    Button("Take another photo") { capturing = true }.buttonStyle(SecondaryButtonStyle())
                }
            } else {
                Text("Take a photo of it. It's checked on this iPhone and never saved.")
                    .font(.subheadline).foregroundStyle(Palette.text2)
                Button("Take a photo") {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Task { if await CameraAccess.request() { capturing = true } else { useBackup = true } }
                    } else {
                        useBackup = true
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private func analyze(_ image: UIImage) {
        analyzing = true
        Task {
            labels = await ItemRecognizer.labels(for: image)
            analyzing = false
        }
    }

    private func success() {
        Haptics.success()
        found += 1
        photo = nil
        labels = []
        feedback = nil
        if found >= step.goal {
            onDone()
        } else {
            let others = pool.filter { $0.id != target?.id }
            target = (others.isEmpty ? pool : others).randomElement()
        }
    }
}

// MARK: - QR destination

struct QRDestinationChallengeView: View {
    let step: ChallengeStep
    let onDone: () -> Void
    @EnvironmentObject private var model: AppModel
    @State private var scanning = false
    @State private var feedback: String? = nil
    @State private var useBackup = false

    private var destination: QRDestination? {
        model.data.destinations.first { $0.id == step.destinationID } ?? model.data.destinations.first
    }

    var body: some View {
        if useBackup {
            BackupChallengeView(reason: "The camera isn't available.", onDone: onDone)
        } else if let destination {
            VStack(alignment: .leading, spacing: 14) {
                Text("Walk to").font(.subheadline).foregroundStyle(Palette.text2)
                Text(destination.name).font(.system(.largeTitle, design: .serif)).foregroundStyle(Palette.text1)
                Text("Scan the WakeUp code you put there. It proves you reached the code, not that you finished your routine.")
                    .font(.subheadline).foregroundStyle(Palette.text2)
                if let feedback { Text(feedback).font(.subheadline).foregroundStyle(Palette.warn) }
                Button("Scan the code") { scanning = true }.buttonStyle(PrimaryButtonStyle())
            }
            .sheet(isPresented: $scanning) {
                QRScannerSheet { code in
                    if code == destination.code {
                        Haptics.success()
                        onDone()
                    } else {
                        feedback = "That's a different code. Find the one for \(destination.name)."
                    }
                } onUnavailable: { useBackup = true }
            }
        } else {
            BackupChallengeView(reason: "No QR destination is set up yet (Settings → QR destinations).", onDone: onDone)
        }
    }
}

// MARK: - Squats and push-ups

struct RepChallengeView: View {
    let step: ChallengeStep
    let onDone: () -> Void
    @Environment(\.theme) private var theme
    @State private var reps = 0
    @State private var lastTap = Date.distantPast
    @State private var useCamera = false
    @State private var cameraReady = false
    @State private var counter = RepCounter()
    @State private var seesBody = false
    @State private var seatedAlternative = false

    private var exercise: String { step.kind == .squats ? "squats" : "push-ups" }

    var body: some View {
        if seatedAlternative {
            VStack(alignment: .leading, spacing: 10) {
                Banner(text: "Low-movement alternative: a memory puzzle instead of \(exercise).", symbol: "figure.seated.side")
                MemoryChallengeView(step: memoryStep, onDone: onDone)
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("Do \(step.goal) comfortable \(exercise). Go at your own pace and stop if anything hurts.")
                    .font(.subheadline).foregroundStyle(Palette.text2)
                if useCamera && cameraReady {
                    PoseCameraView { position in
                        seesBody = true
                        if counter.add(position) { add() }
                    } onNoBody: {
                        seesBody = false
                    }
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous))
                    .overlay(alignment: .bottom) {
                        Text(seesBody ? "Counting · \(reps) of \(step.goal)" : "Step back until your shoulders are in view")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(10)
                    }
                    Text("Experimental: counts are estimates from your shoulder position.")
                        .font(.footnote).foregroundStyle(Palette.text3)
                    Button("Count by tapping instead") { useCamera = false }.buttonStyle(SecondaryButtonStyle())
                } else {
                    ProgressRing(value: reps, total: step.goal, caption: "of \(step.goal) reps")
                    Button("+1 rep", action: tapRep)
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityHint("Tap once after each repetition")
                    Text("Tap once after each rep. This trusts you.").font(.footnote).foregroundStyle(Palette.text3)
                    if step.cameraCounting && CameraAccess.hasCamera {
                        Button("Use camera counting (experimental)") { enableCamera() }.buttonStyle(SecondaryButtonStyle())
                    }
                }
                Button("Low-movement alternative") { seatedAlternative = true }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
            .onAppear { if step.cameraCounting { enableCamera() } }
        }
    }

    private var memoryStep: ChallengeStep {
        var s = ChallengeStep(kind: .memory, difficulty: step.difficulty)
        s.goal = 5
        return s
    }

    private func enableCamera() {
        Task {
            cameraReady = await CameraAccess.request()
            useCamera = cameraReady
        }
    }

    private func tapRep() {
        // Ignore double taps faster than any real rep.
        guard Date().timeIntervalSince(lastTap) > 0.7 else { return }
        lastTap = Date()
        add()
    }

    private func add() {
        guard reps < step.goal else { return }
        reps += 1
        Haptics.tap()
        if reps >= step.goal {
            Haptics.success()
            onDone()
        }
    }
}

// MARK: - Eyes open

enum EyeTracking {
    static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }
}

struct EyesOpenChallengeView: View {
    let step: ChallengeStep
    let onDone: () -> Void
    @Environment(\.theme) private var theme
    @State private var openSince: Date? = nil
    @State private var seconds = 0
    @State private var allowed: Bool? = nil

    var body: some View {
        if !EyeTracking.isSupported {
            BackupChallengeView(reason: "This iPhone doesn't have a Face ID camera.", onDone: onDone)
        } else if allowed == false {
            BackupChallengeView(reason: "Camera access is off for WakeUp.", onDone: onDone)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("Look at the camera with both eyes open for \(step.goal) seconds. Blinking starts the count again.")
                    .font(.subheadline).foregroundStyle(Palette.text2)
                if allowed == true {
                    EyeCheckView { open in
                        guard open else {
                            openSince = nil
                            seconds = 0
                            return
                        }
                        let start = openSince ?? Date()
                        openSince = start
                        seconds = min(step.goal, Int(Date().timeIntervalSince(start)))
                        if seconds >= step.goal { onDone() }
                    }
                    .frame(height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous))
                    .overlay(alignment: .bottom) {
                        Text("\(seconds) of \(step.goal) s")
                            .font(.headline)
                            .foregroundStyle(theme.accentInk)
                            .padding(.horizontal, 16).frame(minHeight: 36)
                            .background(theme.accent, in: Capsule())
                            .padding(12)
                    }
                    .accessibilityElement()
                    .accessibilityLabel("Eyes open for \(seconds) of \(step.goal) seconds")
                } else {
                    ProgressView()
                }
            }
            .task { allowed = await CameraAccess.request() }
        }
    }
}

/// Front TrueDepth camera: reports whether a face is tracked with both eyes open.
struct EyeCheckView: UIViewRepresentable {
    var onUpdate: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onUpdate) }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session.delegate = context.coordinator
        view.session.run(ARFaceTrackingConfiguration())
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {}

    static func dismantleUIView(_ view: ARSCNView, coordinator: Coordinator) {
        view.session.pause()
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        let onUpdate: (Bool) -> Void
        init(_ onUpdate: @escaping (Bool) -> Void) { self.onUpdate = onUpdate }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
            let left = face.blendShapes[.eyeBlinkLeft]?.floatValue ?? 1
            let right = face.blendShapes[.eyeBlinkRight]?.floatValue ?? 1
            let open = face.isTracked && left < 0.25 && right < 0.25
            DispatchQueue.main.async { self.onUpdate(open) }
        }
    }
}
