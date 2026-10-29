import SwiftUI

@main
struct WakeUpApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.audio)
                .environmentObject(model.scheduler)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.becameActive() }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    // Midnight, time-zone and daylight-saving changes: recheck the next ring.
                    Task { await model.reschedule() }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    model.audio.stopPreview()
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        let theme = Theme(prefs: model.data.prefs, systemReduceMotion: systemReduceMotion)
        Group {
            if model.data.onboardingDone {
                HomeView()
            } else {
                OnboardingView()
            }
        }
        .environment(\.theme, theme)
        .tint(theme.accent)
        .preferredColorScheme(model.data.prefs.theme.colorScheme)
        .fullScreenCover(item: $model.ringing) { context in
            RingingView(context: context)
                .environment(\.theme, theme)
                .environmentObject(model)
                .environmentObject(model.audio)
                .environmentObject(model.scheduler)
                .tint(theme.accent)
        }
    }
}
