import SwiftUI

struct WidgetPreviewStage: View {
    @ObservedObject var runtime: AppRuntime
    @State private var position = CGSize.zero
    @State private var widgetSize = CGSize(width: 160, height: 40)
    @GestureState private var drag = CGSize.zero
    init(runtime: AppRuntime) {
        self.runtime = runtime
        if runtime.isPreview && ProcessInfo.processInfo.arguments.contains("--preview-widget-moved") {
            _position = State(initialValue: CGSize(width: 70, height: 18))
        }
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ShellPalette.inset
                Canvas { context, size in
                    for x in stride(from: CGFloat(12), through: size.width, by: 20) {
                        for y in stride(from: CGFloat(12), through: size.height, by: 20) {
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                                         with: .color(ShellPalette.accent.opacity(0.12)))
                        }
                    }
                }.accessibilityHidden(true)
                WidgetView(store: runtime.usage, prefs: runtime.prefs)
                    .background { GeometryReader { proxy in
                        Color.clear.preference(key: WidgetPreviewSize.self, value: proxy.size)
                    } }
                    .onPreferenceChange(WidgetPreviewSize.self) { widgetSize = $0 }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .opacity(runtime.prefs.opacity)
                    .shadow(color: Color.black.opacity(0.12), radius: 10, y: 5)
                    .offset(clamped(CGSize(width: position.width + drag.width, height: position.height + drag.height), in: geometry.size))
                    .gesture(DragGesture().updating($drag) { value, state, _ in
                        if !runtime.prefs.locked { state = value.translation }
                    }.onEnded { value in
                        if !runtime.prefs.locked {
                            position = clamped(CGSize(width: position.width + value.translation.width, height: position.height + value.translation.height), in: geometry.size)
                        }
                    })
                    .help(runtime.prefs.locked ? "Position is locked" : "Try a placement here. Move the floating widget to save its actual position.")
                VStack {
                    HStack {
                        Label("Placement playground", systemImage: "hand.draw")
                        Spacer()
                        ActionButton(title: "Center", symbol: "arrow.counterclockwise") { position = .zero }
                            .accessibilityLabel("Center widget preview")
                    }
                    Spacer()
                    HStack {
                        Text(runtime.prefs.locked ? "Position locked" : "Drag to try a placement")
                        Spacer()
                        Text("\(Int(runtime.prefs.opacity * 100))% opacity").monospacedDigit()
                    }.allowsHitTesting(false)
                }.font(.system(size: 10)).foregroundStyle(ShellPalette.muted).padding(14)
            }
        }.frame(height: 184)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ShellPalette.line).allowsHitTesting(false))
    }
    private func clamped(_ offset: CGSize, in size: CGSize) -> CGSize {
        let x = max(0, size.width / 2 - widgetSize.width / 2 - 16)
        let y = max(0, size.height / 2 - widgetSize.height / 2 - 38)
        return CGSize(width: min(x, max(-x, offset.width)), height: min(y, max(-y, offset.height)))
    }
}

private struct WidgetPreviewSize: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
