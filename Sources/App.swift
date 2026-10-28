import SwiftUI
import AVFoundation
import UserNotifications
import CoreMotion

@main
struct WakeUpApp: App {
    @StateObject var alarm = Alarm()
    var body: some Scene { WindowGroup { if alarm.ringing { Challenge().environmentObject(alarm) } else { Setup().environmentObject(alarm) } } }
}

final class Alarm: ObservableObject {
    @Published var wakeTime: Date? = UserDefaults.standard.object(forKey: "wake") as? Date
    @Published var ringing = false
    private var player: AVAudioPlayer?
    private var timer: Timer?

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in self?.player?.play() }
        if wakeTime != nil { monitor() }
    }

    func arm(_ picked: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: picked)
        let t = Calendar.current.nextDate(after: Date(), matching: c, matchingPolicy: .nextTime) ?? picked
        wakeTime = t
        UserDefaults.standard.set(t, forKey: "wake")
        let nc = UNUserNotificationCenter.current()
        nc.removeAllPendingNotificationRequests()
        for i in 0..<60 {
            let n = UNMutableNotificationContent()
            n.title = "WAKE UP"; n.body = "Open the app and prove you're awake."
            n.sound = UNNotificationSound(named: UNNotificationSoundName("alarm.wav"))
            let trig = UNTimeIntervalNotificationTrigger(timeInterval: max(1, t.timeIntervalSinceNow + Double(i * 20)), repeats: false)
            nc.add(UNNotificationRequest(identifier: "wake\(i)", content: n, trigger: trig))
        }
        monitor()
    }

    func disarm() { stop() }

    private func play(_ name: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: name == "silence" ? [.mixWithOthers] : [])
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: Bundle.main.url(forResource: name, withExtension: "wav")!)
        player?.numberOfLoops = -1; player?.volume = 1; player?.play()
    }

    // Silent audio keeps the app alive in the background so it can ring at full volume.
    private func monitor() {
        play("silence")
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let w = self.wakeTime else { return }
            if Date() >= w {
                if !self.ringing { self.ringing = true; self.play("alarm") }
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
        }
    }

    func stop() {
        timer?.invalidate(); player?.stop(); ringing = false; wakeTime = nil
        UserDefaults.standard.removeObject(forKey: "wake")
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

struct Setup: View {
    @EnvironmentObject var alarm: Alarm
    @State var time = Date()
    var body: some View {
        VStack(spacing: 20) {
            DatePicker("Wake time", selection: $time, displayedComponents: .hourAndMinute).datePickerStyle(.wheel).labelsHidden()
            Button("Set alarm") { alarm.arm(time) }.font(.title)
            if let w = alarm.wakeTime {
                Text("Set for \(w.formatted(date: .abbreviated, time: .shortened))")
                Text("Don't swipe the app away. Volume up.").font(.caption)
                Button("Cancel", role: .destructive) { alarm.disarm() }
            }
        }.padding()
    }
}

struct Challenge: View {
    @EnvironmentObject var alarm: Alarm
    @State var stage = 0
    @State var solved = 0
    @State var a = Int.random(in: 12...29), b = Int.random(in: 3...9), c = Int.random(in: 10...99)
    @State var answer = ""
    @State var shakes = 0
    @State var phrase = ""
    let motion = CMMotionManager()
    let target = "i am awake and getting up"

    var body: some View {
        VStack(spacing: 20) {
            if stage == 0 {
                Text("Math \(solved + 1)/3").font(.headline)
                Text("\(a) × \(b) + \(c) = ?").font(.largeTitle)
                TextField("Answer", text: $answer).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                Button("Submit") {
                    if Int(answer) == a * b + c { solved += 1; if solved == 3 { stage = 1; startShake() } }
                    answer = ""; a = .random(in: 12...29); b = .random(in: 3...9); c = .random(in: 10...99)
                }
            } else if stage == 1 {
                Text("Shake the phone hard").font(.title)
                Text("\(shakes)/30").font(.largeTitle)
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
                if shakes >= 30 { motion.stopAccelerometerUpdates(); stage = 2 }
            }
        }
    }
}
