import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        Form {
            if let message = model.message {
                Section {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(message)
                        Spacer()
                        Button("Dismiss") { model.message = nil }
                    }
                }
            }

            Section {
                Toggle("Tuck away items left of Notchless", isOn: $model.dividerEnabled)
                ForEach(model.extras) { extra in
                    ItemRow(extra: extra, model: model)
                }
                if model.extras.isEmpty {
                    Text(model.trusted ? "Reading your menu bar…" : "Allow Accessibility access to manage your menu bar.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Menu bar items")
            } footer: {
                Text("When on, the Notchless icon widens up to the notch and everything to its left is tucked away into the notch. Switching an item does a quick Cmd-drag across the Notchless icon for you, so the pointer jumps for a moment. You can also Cmd-drag items across it yourself.")
            }

            Section("Opening") {
                Toggle("Open when the pointer rests on the notch", isOn: $model.hoverToOpen)
                Picker("Keyboard shortcut", selection: $model.shortcut) {
                    ForEach(Shortcut.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Panel") {
                Toggle("Also show items already in the menu bar", isOn: $model.showVisible)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $model.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
    }
}

private struct ItemRow: View {
    let extra: MenuExtra
    @ObservedObject var model: NotchModel

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let icon = extra.icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: extra.symbol ?? "circle").font(.system(size: 13, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(extra.name)
                if extra.detail != extra.name {
                    Text(extra.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()

            if model.movingID == extra.id {
                ProgressView().controlSize(.small)
            } else if !extra.canMove {
                Text("Pinned by macOS").font(.caption).foregroundStyle(.secondary)
            } else {
                Toggle("Visible", isOn: Binding(get: { !extra.isHidden }, set: {
                    model.dividerEnabled = true
                    model.onSetHidden(extra, !$0)
                }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(model.movingID != nil)
            }
        }
    }
}
