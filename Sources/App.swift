import SwiftUI
import AVFoundation
import UserNotifications
import CoreMotion
import ARKit

let sounds = ["beep", "siren", "buzzer", "chirp"]

@main
struct WakeUpApp: App {
    @StateObject var alarm = Alarm()
    var body: some Scene { WindowGroup { if alarm.ringing != nil { Challenge().environmentObject(alarm) } else { Setup().environmentObject(alarm) } } }
}

struct AlarmItem: Codable, Identifiable {
    var id = UUID()
    var hour: Int
    var minute: Int
    var sound: String
    var enabled = true
    var next: Date?
}

final class Alarm: ObservableObject {
    @Published var alarms: [AlarmItem] = [] { didSet { UserDefaults.standard.set(try? JSONEncoder().encode(alarms), forKey: "alarms") } }
    @Published var ringing: UUID?
    private var player: AVAudioPlayer?
    private var timer: Timer?

    init() {
        if let d = UserDefaults.standard.data(forKey: "alarms"), let a = try? JSONDecoder().decode([AlarmItem].self, from: d) { alarms = a }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in self?.player?.play() }
        refresh()
    }

    static func nextDate(_ a: AlarmItem) -> Date {
        Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: a.hour, minute: a.minute), matchingPolicy: .nextTime) ?? Date()
    }

    func add(_ time: Date, sound: String) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        var a = AlarmItem(hour: c.hour ?? 7, minute: c.minute ?? 0, sound: sound)
        a.next = Self.nextDate(a)
        alarms.append(a)
        alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        refresh()
    }

    func toggle(_ id: UUID) {
        guard let i = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[i].enabled.toggle()
        alarms[i].next = alarms[i].enabled ? Self.nextDate(alarms[i]) : nil
        refresh()
    }

    func setSound(_ id: UUID, _ sound: String) {
        guard let i = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[i].sound = sound
        refresh()
    }

    func delete(at offsets: IndexSet) { alarms.remove(atOffsets: offsets); refresh() }

    func preview(_ sound: String) {
        play(sound)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.ringing == nil else { return }
            self.player?.stop()
            if self.alarms.contains(where: { $0.enabled }) { self.play("silence") }
        }
    }

    private func play(_ name: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: name == "silence" ? [.mixWithOthers] : [])
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1; player?.volume = 1; player?.play()
    }

    // Backup notifications in case the app gets killed, then silent audio keeps the app alive so it can ring at full volume.
    private func refresh() {
        let nc = UNUserNotificationCenter.current()
        nc.removeAllPendingNotificationRequests()
        let active = alarms.filter { $0.enabled && ($0.next ?? .distantPast) > Date() }
        let per = active.isEmpty ? 0 : min(30, 60 / active.count)
        for a in active {
            for i in 0..<per {
                let n = UNMutableNotificationContent()
                n.title = "WAKE UP"; n.body = "Open the app and prove you're awake."
                n.sound = UNNotificationSound(named: UNNotificationSoundName("\(a.sound).wav"))
                let trig = UNTimeIntervalNotificationTrigger(timeInterval: a.next!.timeIntervalSinceNow + Double(i * 20), repeats: false)
                nc.add(UNNotificationRequest(identifier: "\(a.id)-\(i)", content: n, trigger: trig))
            }
        }
        timer?.invalidate()
        guard alarms.contains(where: { $0.enabled }) else {
            if ringing == nil { player?.stop(); try? AVAudioSession.sharedInstance().setActive(false) }
            return
        }
        if ringing == nil { play("silence") }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        if ringing == nil, let a = alarms.first(where: { $0.enabled && ($0.next ?? .distantFuture) <= Date() }) {
            ringing = a.id
            play(a.sound)
        }
        if ringing != nil { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
    }

    func stop() {
        if let i = alarms.firstIndex(where: { $0.id == ringing }) { alarms[i].next = Self.nextDate(alarms[i]) }
        ringing = nil
        player?.stop()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        refresh()
    }
}

struct Setup: View {
    @EnvironmentObject var alarm: Alarm
    @State var time = Date()
    @State var sound = "beep"
    var body: some View {
        NavigationView {
            List {
                Section("New alarm") {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Picker("Sound", selection: $sound) { ForEach(sounds, id: \.self) { Text($0.capitalized) } }
                    Button("Preview sound") { alarm.preview(sound) }
                    Button("Add alarm") { alarm.add(time, sound: sound) }
                }
                Section(footer: Text("Alarms repeat daily. Keep the app open in the background (don't swipe it away) and volume up.")) {
                    ForEach(alarm.alarms) { a in
                        HStack {
                            Text(Calendar.current.date(from: DateComponents(hour: a.hour, minute: a.minute)) ?? Date(), style: .time).font(.title2)
                            Picker("", selection: Binding(get: { a.sound }, set: { alarm.setSound(a.id, $0) })) {
                                ForEach(sounds, id: \.self) { Text($0.capitalized) }
                            }.labelsHidden().pickerStyle(.menu)
                            Spacer()
                            Toggle("", isOn: Binding(get: { a.enabled }, set: { _ in alarm.toggle(a.id) })).labelsHidden()
                        }
                    }.onDelete { alarm.delete(at: $0) }
                }
            }.navigationTitle("Alarms")
        }
    }
}

struct Challenge: View {
    @EnvironmentObject var alarm: Alarm
    @State var stage = 0
    @State var solved = 0
    @State var a = Int.random(in: 2...9)
    @State var b = Int.random(in: 2...9)
    @State var c = Int.random(in: 1...20)
    @State var answer = ""
    @State var shakes = 0
    @State var phrase = ""
    @State var openSince: Date?
    @State var openSecs = 0
    @State var motion = CMMotionManager()
    let target = "i am awake and getting up"

    var body: some View {
        VStack(spacing: 20) {
            if stage == 0 {
                Text("Math \(solved + 1)/3").font(.headline)
                Text("\(a) × \(b) + \(c) = ?").font(.largeTitle)
                TextField("Answer", text: $answer).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                Button("Submit") {
                    if Int(answer) == a * b + c { solved += 1; if solved == 3 { stage = 1; startShake() } }
                    answer = ""; a = .random(in: 2...9); b = .random(in: 2...9); c = .random(in: 1...20)
                }
            } else if stage == 1 {
                Text("Shake the phone hard").font(.title)
                Text("\(shakes)/30").font(.largeTitle)
            } else if stage == 2 {
                Text("Look at the camera, eyes wide open").font(.title2)
                Text("\(openSecs)/10").font(.largeTitle)
                EyeCheck { open in
                    guard open else { openSince = nil; openSecs = 0; return }
                    let start = openSince ?? Date()
                    openSince = start
                    openSecs = min(10, Int(Date().timeIntervalSince(start)))
                    if openSecs >= 10 { stage = 3 }
                }.frame(height: 360).clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                Text("Type: \"\(target)\"")
                TextField("", text: $phrase).textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never)
                Button("I'm up") { if phrase.lowercased().trimmingCharacters(in: .whitespaces) == target { alarm.stop() } }
            }
        }.padding()
    }

    func startShake() {
        var last = Date.distantPast
        motion.accelerometerUpdateInterval = 0.02
        motion.startAccelerometerUpdates(to: .main) { d, _ in
            guard let x = d?.acceleration else { return }
            if sqrt(x.x * x.x + x.y * x.y + x.z * x.z) > 2.2, Date().timeIntervalSince(last) > 0.15 {
                last = Date(); shakes += 1
                if shakes >= 30 { motion.stopAccelerometerUpdates(); stage = ARFaceTrackingConfiguration.isSupported ? 2 : 3 }
            }
        }
    }
}

// Front TrueDepth camera: reports whether a face is tracked with both eyes fully open.
struct EyeCheck: UIViewRepresentable {
    var onUpdate: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onUpdate) }
    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView()
        v.session.delegate = context.coordinator
        v.session.run(ARFaceTrackingConfiguration())
        return v
    }
    func updateUIView(_ v: ARSCNView, context: Context) {}
    static func dismantleUIView(_ v: ARSCNView, coordinator: Coordinator) { v.session.pause() }

    final class Coordinator: NSObject, ARSessionDelegate {
        let onUpdate: (Bool) -> Void
        init(_ f: @escaping (Bool) -> Void) { onUpdate = f }
        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            guard let f = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
            let l = f.blendShapes[.eyeBlinkLeft]?.floatValue ?? 1
            let r = f.blendShapes[.eyeBlinkRight]?.floatValue ?? 1
            let open = f.isTracked && l < 0.2 && r < 0.2
            DispatchQueue.main.async { self.onUpdate(open) }
        }
    }
}
