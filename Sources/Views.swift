import SwiftUI
import CoreMotion
import ARKit

// Rye's warm dark surfaces and serif-over-sans type, with a sunrise amber accent instead of Rye's blue.
enum R {
    static let frame = Color(hex: 0x1c1b19)
    static let sheet = Color(hex: 0x252321)
    static let raised = Color(hex: 0x2d2a28)
    static let line = Color(hex: 0x3a3632)
    static let text1 = Color(hex: 0xeeeded)
    static let text2 = Color(hex: 0xb8b5b2)
    static let text3 = Color(hex: 0x8a8682)
    static let accent = Color(hex: 0xe0a46a)
    static let onAccent = Color(hex: 0x141210)
    static func serif(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif) }
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(R.sheet, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(R.line, lineWidth: 1))
    }
}

struct Kicker: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(R.sans(12, .semibold)).tracking(0.8).foregroundColor(R.text3) }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(R.sans(16, .semibold))
            .foregroundColor(R.onAccent)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(R.accent.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct Field: View {
    let prompt: String
    @Binding var text: String
    var body: some View {
        TextField("", text: $text, prompt: Text(prompt).foregroundColor(R.text3))
            .font(R.sans(20, .medium))
            .foregroundColor(R.text1)
            .padding(.horizontal, 14).frame(height: 52)
            .background(R.raised, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct Ring: View {
    let value: Int
    let total: Int
    var body: some View {
        ZStack {
            Circle().stroke(R.raised, lineWidth: 12)
            Circle().trim(from: 0, to: CGFloat(value) / CGFloat(total))
                .stroke(R.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: value)
            VStack(spacing: 2) {
                Text("\(value)").font(R.serif(56)).foregroundColor(R.text1)
                Text("of \(total)").font(R.sans(14)).foregroundColor(R.text3)
            }
        }
        .frame(width: 200, height: 200)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct Setup: View {
    @EnvironmentObject var alarm: Alarm
    @State var time = Date()
    @State var sound = "beep"
    @State var now = Date()
    let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var greeting: String {
        let h = Calendar.current.component(.hour, from: now)
        return h < 5 ? "Late night." : h < 12 ? "Good morning." : h < 17 ? "Good afternoon." : "Good evening."
    }

    var nextLine: String {
        guard let n = alarm.alarms.filter({ $0.enabled }).compactMap({ $0.next }).min() else { return "No alarms set" }
        let m = max(0, Int(n.timeIntervalSince(now) / 60))
        return "Next alarm in \(m / 60)h \(m % 60)m"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting).font(R.serif(36)).foregroundColor(R.text1)
                    Text(nextLine).font(R.sans(15)).foregroundColor(R.text2)
                }
                .padding(.top, 28)

                Card {
                    Kicker(text: "New alarm")
                    DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                    Text("Sound · tap to hear it").font(R.sans(13)).foregroundColor(R.text3)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(sounds, id: \.self) { s in
                                Button { sound = s; alarm.preview(s) } label: {
                                    Text(s.capitalized)
                                        .font(R.sans(14, .medium))
                                        .padding(.horizontal, 16).frame(height: 34)
                                        .foregroundColor(sound == s ? R.onAccent : R.text2)
                                        .background(sound == s ? R.accent : R.raised, in: Capsule())
                                }
                            }
                        }
                    }
                    Button("Add alarm") { alarm.add(time, sound: sound) }.buttonStyle(PrimaryButton())
                }

                if !alarm.alarms.isEmpty {
                    Kicker(text: "Your alarms").padding(.top, 4)
                    ForEach(alarm.alarms) { AlarmRow(a: $0) }
                }

                Text("Alarms repeat every day. Keep the app open in the background and your volume up.")
                    .font(R.sans(12)).foregroundColor(R.text3)
            }
            .padding(.horizontal, 16).padding(.bottom, 32)
        }
        .background(R.frame.ignoresSafeArea())
        .onReceive(clock) { now = $0 }
    }
}

struct AlarmRow: View {
    @EnvironmentObject var alarm: Alarm
    let a: AlarmItem
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(Calendar.current.date(from: DateComponents(hour: a.hour, minute: a.minute)) ?? Date(), style: .time)
                    .font(R.serif(34)).foregroundColor(a.enabled ? R.text1 : R.text3)
                Menu {
                    ForEach(sounds, id: \.self) { s in Button(s.capitalized) { alarm.setSound(a.id, s) } }
                    Button("Delete alarm", role: .destructive) { alarm.remove(a.id) }
                } label: {
                    HStack(spacing: 4) {
                        Text(a.sound.capitalized)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .font(R.sans(13)).foregroundColor(R.text2)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { a.enabled }, set: { _ in alarm.toggle(a.id) })).labelsHidden().tint(R.accent)
        }
        .padding(18)
        .background(R.sheet, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(R.line, lineWidth: 1))
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
    @State var wrong = false
    @State var shakes = 0
    @State var phrase = ""
    @State var openSince: Date?
    @State var openSecs = 0
    @State var motion = CMMotionManager()
    let target = "i am awake and getting up"
    let titles = ["Wake up.", "Shake it.", "Eyes open.", "Say it."]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 6) {
                    ForEach(0..<4) { i in Capsule().fill(i <= stage ? R.accent : R.raised).frame(height: 4) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Kicker(text: "Step \(stage + 1) of 4")
                    Text(titles[stage]).font(R.serif(36)).foregroundColor(R.text1)
                }
                Card { step }
            }
            .padding(.horizontal, 16).padding(.top, 20)
        }
        .background(R.frame.ignoresSafeArea())
    }

    @ViewBuilder var step: some View {
        switch stage {
        case 0:
            Text("Problem \(solved + 1) of 3").font(R.sans(13)).foregroundColor(R.text3)
            Text("\(a) × \(b) + \(c)").font(R.serif(48)).foregroundColor(R.text1)
            Field(prompt: "Answer", text: $answer).keyboardType(.numberPad)
            if wrong { Text("Not quite. Here's a new one.").font(R.sans(13)).foregroundColor(R.accent) }
            Button("Submit") {
                wrong = Int(answer) != a * b + c
                if !wrong { solved += 1; if solved == 3 { stage = 1; startShake() } }
                answer = ""; a = .random(in: 2...9); b = .random(in: 2...9); c = .random(in: 1...20)
            }.buttonStyle(PrimaryButton())
        case 1:
            Text("Shake the phone hard until the ring fills.").font(R.sans(15)).foregroundColor(R.text2)
            Ring(value: shakes, total: 30)
        case 2:
            Text("Look at the camera with both eyes wide open for 10 seconds. Blinking starts it over.")
                .font(R.sans(15)).foregroundColor(R.text2)
            EyeCheck { open in
                guard open else { openSince = nil; openSecs = 0; return }
                let start = openSince ?? Date()
                openSince = start
                openSecs = min(10, Int(Date().timeIntervalSince(start)))
                if openSecs >= 10 { stage = 3 }
            }
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(alignment: .bottom) {
                Text("\(openSecs) of 10 s")
                    .font(R.sans(15, .semibold)).foregroundColor(R.onAccent)
                    .padding(.horizontal, 16).frame(height: 36)
                    .background(R.accent, in: Capsule())
                    .padding(.bottom, 14)
            }
        default:
            Text("Type this to turn the alarm off.").font(R.sans(15)).foregroundColor(R.text2)
            Text("“\(target)”").font(R.serif(24)).italic().foregroundColor(R.text1)
            Field(prompt: "Type it here", text: $phrase)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
            Button("I'm up") {
                if phrase.lowercased().trimmingCharacters(in: .whitespaces) == target { alarm.stop() }
            }.buttonStyle(PrimaryButton())
        }
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
