import SwiftUI

struct Card<Content: View>: View {
    @Environment(\.theme) private var theme
    var padding: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: theme.gap) { content }
            .padding(padding ?? theme.gap * 1.3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.sheet, in: RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: theme.radius, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
    }
}

struct Kicker: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(Palette.text3)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A large serif heading, like Rye's greetings.
struct Headline: View {
    let text: String
    var size: Font.TextStyle = .largeTitle
    var body: some View {
        Text(text)
            .font(.system(size, design: .serif))
            .foregroundStyle(Palette.text1)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(theme.accentInk)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 12)
            .background(theme.accent.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4),
                        in: RoundedRectangle(cornerRadius: theme.smallRadius + 2, style: .continuous))
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Palette.text1)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 12)
            .background(Palette.raised.opacity(configuration.isPressed ? 0.6 : 1),
                        in: RoundedRectangle(cornerRadius: theme.smallRadius + 2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: theme.smallRadius + 2, style: .continuous).strokeBorder(Palette.line))
            .contentShape(Rectangle())
    }
}

struct Chip: View {
    @Environment(\.theme) private var theme
    let title: String
    var symbol: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .foregroundStyle(selected ? theme.accentInk : Palette.text2)
            .background(selected ? theme.accent : Palette.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Palette.line))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Wraps chips onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct SegmentBar: View {
    @Environment(\.theme) private var theme
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i <= current ? theme.accent : Palette.line).frame(height: 5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(min(current + 1, count)) of \(count)")
    }
}

struct ProgressRing: View {
    @Environment(\.theme) private var theme
    let value: Int
    let total: Int
    var caption: String?

    var body: some View {
        ZStack {
            Circle().stroke(Palette.raised, lineWidth: 14)
            Circle()
                .trim(from: 0, to: total > 0 ? CGFloat(min(value, total)) / CGFloat(total) : 0)
                .stroke(theme.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(theme.animation(.easeOut(duration: 0.25)), value: value)
            VStack(spacing: 2) {
                Text("\(value)").font(.system(size: 54, design: .serif)).foregroundStyle(Palette.text1)
                Text(caption ?? "of \(total)").font(.subheadline).foregroundStyle(Palette.text3)
            }
        }
        .frame(width: 190, height: 190)
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("\(value) of \(total)")
    }
}

/// A button that only fires after being held, used for the emergency stop.
struct HoldButton: View {
    @Environment(\.theme) private var theme
    let title: String
    let seconds: Double
    let action: () -> Void
    @State private var progress: CGFloat = 0

    var body: some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(Palette.text1)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(alignment: .leading) {
                GeometryReader { geo in
                    Palette.bad.opacity(0.35).frame(width: geo.size.width * progress)
                }
            }
            .background(Palette.raised)
            .clipShape(RoundedRectangle(cornerRadius: theme.smallRadius + 2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: theme.smallRadius + 2, style: .continuous).strokeBorder(Palette.bad.opacity(0.5)))
            .onLongPressGesture(minimumDuration: seconds, maximumDistance: 60) {
                Haptics.warning()
                action()
            } onPressingChanged: { pressing in
                withAnimation(pressing ? .linear(duration: seconds) : .easeOut(duration: 0.2)) { progress = pressing ? 1 : 0 }
            }
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityHint("Emergency stop. Activate to stop the alarm without the challenge.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

struct InfoRow: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Palette.text3).frame(width: 22)
            Text(title).foregroundStyle(Palette.text2)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(Palette.text1).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

struct Banner: View {
    @Environment(\.theme) private var theme
    let text: String
    var symbol = "info.circle.fill"
    var tint: Color?
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint ?? theme.accent)
            Text(text).font(.subheadline).foregroundStyle(Palette.text1).frame(maxWidth: .infinity, alignment: .leading)
            if let dismiss {
                Button(action: dismiss) { Image(systemName: "xmark").font(.footnote.weight(.semibold)) }
                    .foregroundStyle(Palette.text3)
                    .accessibilityLabel("Dismiss")
            }
        }
        .padding(14)
        .background((tint ?? theme.accent).opacity(0.12), in: RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous))
    }
}

/// A text field styled to match cards.
struct InputField: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        content
            .font(.title3.weight(.medium))
            .foregroundStyle(Palette.text1)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous).strokeBorder(Palette.line))
    }
}

extension View {
    func inputField() -> some View { modifier(InputField()) }

    /// Lets a Form sit on WakeUp's background instead of the system gray.
    func wakeForm() -> some View {
        scrollContentBackground(.hidden).background(AppBackground())
    }
}
