import AppKit
import SwiftUI
import UsageCore

extension UsageCore.Provider {
    var appName: String { self == .claude ? "Claude" : "Codex" }
}

enum ShellPalette {
    // One burgundy family: crimson controls, warm neutral surfaces, unchanged brand rail.
    static let accent = adaptive(light: (0.62, 0.19, 0.27), dark: (0.84, 0.55, 0.60))
    static let brandHighlight = Color(red: 0.98, green: 0.47, blue: 0.53)
    static let button = Color(red: 0.48, green: 0.16, blue: 0.22)
    static let warning = adaptive(light: (0.60, 0.31, 0.06), dark: (0.96, 0.70, 0.36))
    static let danger = adaptive(light: (0.70, 0.18, 0.16), dark: (0.98, 0.48, 0.43))
    static let destructiveFill = Color(red: 0.72, green: 0.16, blue: 0.21)
    static let sidebar = Color(red: 0.14, green: 0.075, blue: 0.10)
    static let tint = adaptive(light: (0.968, 0.920, 0.925), dark: (0.225, 0.165, 0.18))
    static let canvas = adaptive(light: (0.970, 0.962, 0.958), dark: (0.105, 0.095, 0.099))
    static let surface = adaptive(light: (0.998, 0.992, 0.989), dark: (0.16, 0.145, 0.15))
    static let inset = adaptive(light: (0.94, 0.927, 0.927), dark: (0.125, 0.112, 0.117))
    static let line = Color.primary.opacity(0.10)
    static let muted = adaptive(light: (0.41, 0.37, 0.38), dark: (0.70, 0.65, 0.66))
    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(calibratedRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}

enum BrandAssets {
    // SwiftPM's generated lookup expects a sibling bundle for command-line
    // executables. Packaged macOS resources live inside Contents/Resources.
    static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("SkillHanger_AgentAwakeApp.bundle"),
           let packaged = Bundle(url: url) { return packaged }
        return .module
    }()
    static let logo: NSImage = {
        guard let url = bundle.url(forResource: "SkillHangerLogo", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing bundled SkillHanger logo")
        }
        return image
    }()
}

struct BrandMark: View {
    var size: CGFloat = 28
    var body: some View {
        Image(nsImage: BrandAssets.logo)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct AgentBadge: View {
    var claude: Bool
    var size: CGFloat = 36
    var body: some View {
        Image(systemName: claude ? "asterisk" : "hexagon")
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(claude ? Palette.claude : ShellPalette.accent)
            .frame(width: size, height: size)
            .background((claude ? Palette.claude : ShellPalette.accent).opacity(0.075),
                        in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}

struct Surface<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ShellPalette.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ShellPalette.line, lineWidth: 1).allowsHitTesting(false))
    }
}

struct SectionHeading: View {
    let title: String
    var detail: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 16, weight: .semibold)).accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail).font(.system(size: 12)).foregroundStyle(ShellPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct StatusPill: View {
    var text: String
    var symbol: String = "circle.fill"
    var color: Color = ShellPalette.accent
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .foregroundStyle(color)
            .background(color.opacity(0.10), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    var symbol: String?
    @ViewBuilder var control: () -> Control
    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 14))
                    .foregroundStyle(ShellPalette.accent).frame(width: 30, height: 30)
                    .background(ShellPalette.tint, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(ShellPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control().fixedSize()
        }
        .padding(.vertical, 13)
    }
}

struct SwitchRow: View {
    var title: String
    var detail: String?
    var symbol: String?
    @Binding var value: Bool
    var body: some View {
        SettingRow(title: title, detail: detail, symbol: symbol) {
            Toggle(title, isOn: $value).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .accessibilityLabel(title)
        }
    }
}

struct ProductButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReducedMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(prominent ? ShellPalette.button : ShellPalette.surface,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : hovered ? 0.045 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(prominent ? Color.white.opacity(0.08) : ShellPalette.line))
            .clipShape(RoundedRectangle(cornerRadius: 10)).contentShape(RoundedRectangle(cornerRadius: 10))
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.96 : hovered && enabled ? 1.025 : 1)
            .opacity(enabled ? 1 : 0.45)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ActionButton: View {
    let title: String
    let symbol: String
    var prominent = false
    let action: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: action) { Label(title, systemImage: symbol) }
            .buttonStyle(ProductButtonStyle(prominent: prominent))
            .focused($focused)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(focused ? ShellPalette.accent : .clear, lineWidth: 2).padding(-2).allowsHitTesting(false))
            .help(title)
    }
}

struct EmptyPanel: View {
    var title: String
    var detail: String
    var symbol: String = "tray"
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 25, weight: .light))
                .foregroundStyle(ShellPalette.accent)
                .frame(width: 52, height: 52).background(ShellPalette.inset, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            Text(title).font(.system(size: 16, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(ShellPalette.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                ActionButton(title: actionTitle, symbol: "arrow.right", prominent: true, action: action).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
    }
}

private struct ForcedReducedMotion: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var forceReducedMotion: Bool {
        get { self[ForcedReducedMotion.self] }
        set { self[ForcedReducedMotion.self] = newValue }
    }
}
