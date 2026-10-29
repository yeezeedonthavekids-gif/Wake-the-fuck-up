import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    /// A color that switches with light and dark appearance.
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

/// Warm neutral surfaces in the spirit of Rye, tuned for mornings.
enum Palette {
    static let frame = Color.dynamic(0xF4F1EC, 0x1A1917)
    static let sheet = Color.dynamic(0xFFFFFF, 0x242220)
    static let raised = Color.dynamic(0xF5F2EE, 0x2E2B28)
    static let line = Color.dynamic(0xE6E1DA, 0x3A3632)
    static let text1 = Color.dynamic(0x1E1A16, 0xF0EEEC)
    static let text2 = Color.dynamic(0x57514A, 0xBAB6B2)
    static let text3 = Color.dynamic(0x857F78, 0x8E8A86)
    static let good = Color.dynamic(0x2F7D4F, 0x72C493)
    static let warn = Color.dynamic(0xA8650F, 0xE6B45F)
    static let bad = Color.dynamic(0xB3372B, 0xEC7B70)
    static let ringBase = Color(uiColor: UIColor(hex: 0x14110F))
}

extension AccentChoice {
    var color: Color {
        switch self {
        case .sunrise: .dynamic(0xD2741F, 0xEBA45E)
        case .coral: .dynamic(0xD4553F, 0xF08C7A)
        case .rose: .dynamic(0xC2416F, 0xEB86A9)
        case .lavender: .dynamic(0x6F5CC7, 0xA99CF0)
        case .ocean: .dynamic(0x2370B5, 0x6EAAE3)
        case .mint: .dynamic(0x16876F, 0x5CCDB4)
        case .forest: .dynamic(0x3A7D47, 0x7DC28A)
        case .graphite: .dynamic(0x4A4642, 0xC9C4BE)
        }
    }
}

extension ThemeMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct Theme {
    var accent = AccentChoice.sunrise.color
    var radius: CGFloat = 18
    var gap: CGFloat = 14
    var reduceMotion = false
    var background = BackgroundChoice.dawn
    var gradients = true

    init() {}

    init(prefs: Preferences, systemReduceMotion: Bool) {
        accent = prefs.accent.color
        radius = prefs.shape == .rounded ? 20 : 11
        gap = prefs.density == .comfortable ? 14 : 10
        switch prefs.motion {
        case .system: reduceMotion = systemReduceMotion
        case .reduced: reduceMotion = true
        case .full: reduceMotion = false
        }
        background = prefs.background
        gradients = prefs.gradientsEnabled
    }

    /// Text and icons placed on the accent color.
    var accentInk: Color { .dynamic(0xFFFFFF, 0x171310) }
    var smallRadius: CGFloat { max(radius - 6, 8) }

    func animation(_ animation: Animation = .spring(response: 0.35, dampingFraction: 0.86)) -> Animation? {
        reduceMotion ? nil : animation
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme()
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// The app's background: the warm base color plus an optional soft accent wash.
struct AppBackground: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Palette.frame
            if theme.gradients { wash }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private var wash: some View {
        switch theme.background {
        case .plain:
            EmptyView()
        case .dawn:
            LinearGradient(colors: [theme.accent.opacity(0.20), .clear], startPoint: .top, endPoint: .center)
        case .dusk:
            LinearGradient(colors: [.clear, theme.accent.opacity(0.18)], startPoint: .center, endPoint: .bottom)
        case .glow:
            RadialGradient(colors: [theme.accent.opacity(0.24), .clear], center: .topTrailing, startRadius: 10, endRadius: 460)
        case .mist:
            LinearGradient(colors: [theme.accent.opacity(0.10), .clear, theme.accent.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
