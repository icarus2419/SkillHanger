import SwiftUI

struct PackageOptionControls: View {
    let item: CatalogItem
    let selection: PackageSelection
    @ObservedObject var preferences: PackagePreferences
    private var saved: [String: String] { preferences.options(for: selection) }
    private func binding(_ field: PackageOptionField) -> Binding<String> {
        Binding(get: { field.value(in: saved) }, set: { preferences.setOption($0, key: field.id, for: selection) })
    }
    var body: some View {
        ForEach(PackageCustomization.fields(item, options: saved)) { field in
            VStack(alignment: .leading, spacing: 6) {
                if field.choices.isEmpty {
                    Text(field.title).font(.system(size: 12, weight: .medium))
                    TextField(field.placeholder, text: binding(field)).textFieldStyle(.roundedBorder)
                        .accessibilityLabel(field.title)
                } else {
                    SettingRow(title: field.title, symbol: "slider.horizontal.3") {
                        Menu {
                            ForEach(field.choices) { choice in
                                Button { binding(field).wrappedValue = choice.id } label: {
                                    if choice.id == field.value(in: saved) { Label(choice.title, systemImage: "checkmark") }
                                    else { Text(choice.title) }
                                }
                            }
                        } label: {
                            Text(field.choices.first { $0.id == field.value(in: saved) }?.title ?? field.defaultValue)
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary)
                        }.menuStyle(.borderlessButton).fixedSize().frame(width: 205, alignment: .trailing)
                            .accessibilityLabel(field.title)
                    }
                }
                Text(field.detail).font(.system(size: 11)).foregroundStyle(ShellPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if field.id == "session" && !field.value(in: saved).isEmpty && field.value(in: saved).range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) == nil {
                    Text("Use up to 64 letters, numbers, hyphens, or underscores. This name is omitted from the invocation until valid.")
                        .font(.system(size: 11)).foregroundStyle(ShellPalette.danger)
                }
            }
            Divider()
        }
    }
}
