import Combine
import SwiftUI

/// First-run setup: permission, what stays in the menu bar, how to open Notchless, general options.
/// Choices about items are collected here and applied in one go when the person finishes.
struct OnboardingView: View {
    @ObservedObject var model: NotchModel
    var onFinish: (_ hidden: [String: Bool]) -> Void

    @State private var step: Int
    /// Item id → should be hidden. Starts from what's hidden today.
    @State private var choices: [String: Bool] = [:]
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let steps = 5

    init(model: NotchModel, step: Int = 0, onFinish: @escaping (_ hidden: [String: Bool]) -> Void) {
        self.model = model
        self.onFinish = onFinish
        _step = State(initialValue: step)
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: permission
                    case 2: chooseItems
                    case 3: opening
                    default: finish
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 30)),
                                        removal: .opacity.combined(with: .offset(x: -30))))
                .id(step)
                footer
            }
            .padding(.horizontal, 36)
            .padding(.top, 44)
            .padding(.bottom, 26)
        }
        .frame(width: 640, height: 580)
        .environment(\.colorScheme, .dark)
        .onReceive(poll) { _ in
            guard step == 1, !model.trusted else { return }
            if MenuExtras.isTrusted { model.trusted = true; model.onRefresh() }
        }
        .onChange(of: model.extras.map(\.id)) { seedChoices() }
        .onAppear(perform: seedChoices)
    }

    private func seedChoices() {
        for extra in model.extras where choices[extra.id] == nil { choices[extra.id] = extra.isHidden }
    }

    private func go(_ next: Int) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step = next }
    }

    // MARK: - Chrome

    private var background: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [Color(red: 1, green: 0.45, blue: 0.2).opacity(0.35), .clear],
                           center: .init(x: 0.5, y: 0.05), startRadius: 10, endRadius: 420)
            RadialGradient(colors: [Color(red: 0.55, green: 0.35, blue: 1).opacity(0.22), .clear],
                           center: .init(x: 0.9, y: 1), startRadius: 10, endRadius: 380)
        }
        .ignoresSafeArea()
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<steps, id: \.self) { i in
                    Capsule().fill(.white.opacity(i == step ? 0.9 : 0.2))
                        .frame(width: i == step ? 18 : 6, height: 6)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
            Spacer()
            if step > 0 {
                Button("Back") { go(step - 1) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.trailing, 14)
            }
            primaryButton
        }
    }

    @ViewBuilder private var primaryButton: some View {
        switch step {
        case 0: PrimaryButton(title: "Get started") { go(1) }
        case 1:
            if model.trusted {
                PrimaryButton(title: "Continue") { go(2) }
            } else {
                Button("Skip for now") { go(2) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.6))
            }
        case 4: PrimaryButton(title: "Finish") { onFinish(choices) }
        default: PrimaryButton(title: "Continue") { go(step + 1) }
        }
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(subtitle).font(.system(size: 13, design: .rounded)).foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 28) {
            HeroNotch(icons: model.extras.compactMap(\.icon))
            header("Your whole menu bar, one click away",
                   "The notch hides menu bar items when there's no room.\nNotchless opens the notch and shows every one of them.")
        }
    }

    private var permission: some View {
        VStack(spacing: 22) {
            Image(systemName: model.trusted ? "checkmark.seal.fill" : "lock.open.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(model.trusted
                                 ? AnyShapeStyle(Color.green)
                                 : AnyShapeStyle(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .contentTransition(.symbolEffect(.replace))
            header("Allow Accessibility",
                   "Notchless reads your menu bar items and opens them through Accessibility.\nNothing leaves your Mac.")
            HStack(spacing: 8) {
                Circle().fill(model.trusted ? Color.green : Color.orange).frame(width: 8, height: 8)
                Text(model.trusted ? "Access granted" : "Waiting for access…")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(.white.opacity(0.08), in: Capsule())
            if !model.trusted {
                Button("Open Accessibility Settings") {
                    MenuExtras.requestTrust()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.18))
                Text("Already listed but this doesn't turn green? Select Notchless, remove it with –, then allow it again.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
    }

    private var chooseItems: some View {
        VStack(spacing: 18) {
            header("What stays in the menu bar?",
                   "Lit items stay in the menu bar. Dimmed ones are tucked into the notch, one click away.")
            if model.extras.isEmpty {
                Text(model.trusted ? "Reading your menu bar…" : "Allow Accessibility first to see your items.")
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 12), count: 5), spacing: 14) {
                        ForEach(model.extras) { extra in
                            ChoiceTile(extra: extra, hidden: choices[extra.id] ?? extra.isHidden) {
                                guard extra.canMove else { return }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    choices[extra.id] = !(choices[extra.id] ?? extra.isHidden)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                let hiddenCount = model.extras.filter { choices[$0.id] ?? $0.isHidden }.count
                Text("\(model.extras.count - hiddenCount) in the menu bar  ·  \(hiddenCount) in the notch")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private var opening: some View {
        VStack(spacing: 26) {
            header("How do you want to open it?", "The icon right of the notch always works. Add a shortcut or a hover if you like.")
            VStack(spacing: 12) {
                OptionRow(symbol: "cursorarrow.motionlines", title: "Hover the notch",
                          subtitle: "Rest the pointer on the notch to open Notchless") {
                    Toggle("", isOn: $model.hoverToOpen).toggleStyle(.switch).labelsHidden()
                }
                OptionRow(symbol: "command", title: "Keyboard shortcut", subtitle: "Open from anywhere") {
                    Picker("", selection: $model.shortcut) {
                        ForEach(Shortcut.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            }
            .frame(maxWidth: 460)
        }
    }

    private var finish: some View {
        let changes = model.extras.filter { extra in (choices[extra.id] ?? extra.isHidden) != extra.isHidden }.count
        return VStack(spacing: 26) {
            header("Almost there", "A couple of last details.")
            VStack(spacing: 12) {
                OptionRow(symbol: "power", title: "Launch at login", subtitle: "Start Notchless with your Mac") {
                    Toggle("", isOn: $model.launchAtLogin).toggleStyle(.switch).labelsHidden()
                }
                OptionRow(symbol: "square.grid.2x2", title: "Show every item in the panel",
                          subtitle: "Not only the hidden ones") {
                    Toggle("", isOn: $model.showVisible).toggleStyle(.switch).labelsHidden()
                }
            }
            .frame(maxWidth: 460)
            if changes > 0 {
                Label("Finishing moves \(changes) item\(changes == 1 ? "" : "s") for you. Your pointer will jump for a few seconds, so hands off the mouse.",
                      systemImage: "hand.raised.fill")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: 440)
            }
        }
    }
}

// MARK: - Pieces

/// The notch opening and items blooming out of it, on a loop.
private struct HeroNotch: View {
    let icons: [NSImage]
    @State private var open = false

    var body: some View {
        let shape = NotchShape(top: open ? 12 : 5, bottom: open ? 26 : 9)
        ZStack(alignment: .top) {
            shape.fill(Color.black)
                .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 1))
                .frame(width: open ? 360 : 130, height: open ? 150 : 26)
                .shadow(color: .orange.opacity(open ? 0.35 : 0), radius: 30, y: 10)
            HStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { i in
                    Group {
                        if i < icons.count {
                            Image(nsImage: icons[i]).resizable().interpolation(.high)
                        } else {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(LinearGradient(colors: [[.orange, .purple, .cyan, .pink, .green][i], .white.opacity(0.3)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                    .frame(width: 44, height: 44)
                    .scaleEffect(open ? 1 : 0.4)
                    .opacity(open ? 1 : 0)
                    .blur(radius: open ? 0 : 6)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(open ? 0.15 + Double(i) * 0.06 : 0), value: open)
                }
            }
            .padding(.top, 56)
        }
        .frame(height: 170, alignment: .top)
        .animation(.spring(response: 0.55, dampingFraction: 0.75), value: open)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.6))
                open = true
                try? await Task.sleep(for: .seconds(3.2))
                open = false
            }
        }
    }
}

private struct ChoiceTile: View {
    let extra: MenuExtra
    let hidden: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let icon = extra.icon {
                            Image(nsImage: icon).resizable().interpolation(.high).frame(width: 40, height: 40)
                        } else {
                            Image(systemName: extra.symbol ?? "circle").font(.system(size: 20, weight: .semibold))
                                .frame(width: 40, height: 40)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .background(.white.opacity(hidden ? 0.04 : 0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(hidden ? 0.06 : 0.25), lineWidth: 1))
                    .saturation(hidden ? 0 : 1)
                    .opacity(hidden ? 0.45 : 1)

                    Image(systemName: !extra.canMove ? "lock.fill" : hidden ? "eye.slash.fill" : "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(!extra.canMove ? Color.white.opacity(0.5) : hidden ? Color.orange : Color.green)
                        .background(Circle().fill(.black).padding(-2))
                        .offset(x: 5, y: -5)
                }
                Text(extra.name)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(hidden ? 0.45 : 0.9))
                    .lineLimit(1)
            }
            .frame(width: 96)
            .scaleEffect(hovering && extra.canMove ? 1.05 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        .help(extra.canMove ? (hidden ? "Tucked into the notch. Click to keep it in the menu bar." : "In the menu bar. Click to tuck it away.")
                            : "Pinned by macOS")
    }
}

private struct OptionRow<Control: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(subtitle).font(.system(size: 11, design: .rounded)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            control
        }
        .padding(14)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 22).padding(.vertical, 9)
                .background(Color.white, in: Capsule())
        }
        .buttonStyle(PressStyle())
        .keyboardShortcut(.defaultAction)
    }
}
