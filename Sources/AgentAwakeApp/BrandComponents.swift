import SwiftUI

/// Branded choices remain native buttons with keyboard focus and selection labels.
struct ChoiceStrip: View {
    let options: [String]
    @Binding var selection: String
    var label: (String) -> String = { $0 }
    var accessibilityTitle: String
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                ChoiceChip(title: label(option), selected: selection == option) { selection = option }
            }
        }.padding(4).background(ShellPalette.inset, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain).accessibilityLabel(accessibilityTitle)
    }
}

private struct ChoiceChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @FocusState private var focused: Bool
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 13).padding(.vertical, 8)
                .foregroundStyle(selected ? ShellPalette.accent : ShellPalette.muted)
                .background(selected ? ShellPalette.surface : hovered ? ShellPalette.surface.opacity(0.5) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).focused($focused).onHover { hovered = $0 }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? ShellPalette.accent : .clear, lineWidth: 2).padding(-2).allowsHitTesting(false))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct QuickSwitchTile: View {
    let title: String
    let detail: String
    let symbol: String
    @Binding var value: Bool
    var body: some View {
        Toggle(title, isOn: $value).toggleStyle(TileToggleStyle(detail: detail, symbol: symbol))
    }
}

private struct TileToggleStyle: ToggleStyle {
    let detail: String
    let symbol: String
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReducedMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    @State private var hovered = false
    @FocusState private var focused: Bool
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                    .foregroundStyle(configuration.isOn ? ShellPalette.accent : ShellPalette.muted)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    configuration.label.font(.system(size: 11, weight: .semibold))
                    Text(detail).font(.system(size: 10)).foregroundStyle(ShellPalette.muted).lineLimit(2)
                }
                Spacer(minLength: 4)
                Text(configuration.isOn ? "On" : "Off")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(configuration.isOn ? ShellPalette.accent : ShellPalette.muted)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(configuration.isOn ? ShellPalette.tint : ShellPalette.inset, in: RoundedRectangle(cornerRadius: 6))
            }.padding(16).frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                .contentShape(Rectangle())
                .background(hovered ? ShellPalette.inset.opacity(0.5) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).focused($focused).onHover { hovered = $0 }
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(focused ? ShellPalette.accent : .clear, lineWidth: 2).allowsHitTesting(false))
            .offset(y: hovered && !reduceMotion ? -2 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7), value: hovered)
            .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}
