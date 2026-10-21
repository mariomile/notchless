import SwiftUI

final class NotchModel: ObservableObject {
    @Published var isOpen = false
    @Published var extras: [MenuExtra] = []
    @Published var trusted = true
    @Published var hoveredID: String?
    var notch = CGSize(width: 200, height: 32)
    var onSelect: (MenuExtra) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    var hidden: [MenuExtra] { extras.filter(\.isHidden) }
    var visible: [MenuExtra] { extras.filter { !$0.isHidden } }

    enum Metric {
        static let tileWidth: CGFloat = 64
        static let tileHeight: CGFloat = 74
        static let spacing: CGFloat = 10
        static let padding: CGFloat = 22
        static let header: CGFloat = 24
        static let caption: CGFloat = 36
        static let ear: CGFloat = 14
    }

    var columns: Int { min(max(hidden.count, visible.count, 4), 9) }

    private func sectionHeight(_ count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let rows = CGFloat((count + columns - 1) / columns)
        return Metric.header + rows * Metric.tileHeight + (rows - 1) * Metric.spacing
    }

    /// Size of the expanded notch, ears included.
    var openSize: CGSize {
        let grid = CGFloat(columns) * Metric.tileWidth + CGFloat(columns - 1) * Metric.spacing
        let width = max(grid + Metric.padding * 2, notch.width + 260) + Metric.ear * 2
        let body: CGFloat
        if !trusted {
            body = 168
        } else if extras.isEmpty {
            body = 72
        } else {
            let gap: CGFloat = hidden.isEmpty || visible.isEmpty ? 0 : 14
            body = 10 + sectionHeight(hidden.count) + gap + sectionHeight(visible.count) + Metric.caption
        }
        return CGSize(width: width, height: notch.height + body)
    }

    var closedSize: CGSize { CGSize(width: notch.width + 12, height: notch.height) }
}

// MARK: - Shape

/// The notch silhouette: flared "ears" at the top that melt into the menu bar, round bottom corners.
struct NotchShape: Shape {
    var top: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set { top = newValue.first; bottom = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let b = min(bottom, (r.height - top) * 0.9, (r.width - top * 2) / 2)
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + top, y: r.minY + top), control: CGPoint(x: r.minX + top, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + top, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.minX + top + b, y: r.maxY), control: CGPoint(x: r.minX + top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top - b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - top, y: r.maxY - b), control: CGPoint(x: r.maxX - top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top, y: r.minY + top))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - top, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Root

struct NotchRoot: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        let size = model.isOpen ? model.openSize : model.closedSize
        let shape = NotchShape(top: model.isOpen ? NotchModel.Metric.ear : 6, bottom: model.isOpen ? 32 : 10)

        content
            .frame(width: model.openSize.width - NotchModel.Metric.ear * 2, height: model.openSize.height, alignment: .top)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .clipShape(shape)
            .overlay(
                shape.stroke(LinearGradient(colors: [.clear, .white.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    .opacity(model.isOpen ? 1 : 0)
            )
            .background(
                shape.fill(Color.black)
                    .shadow(color: .black.opacity(model.isOpen ? 0.55 : 0), radius: 28, y: 14)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The panel is larger than the notch; a click on its empty part counts as clicking away.
            .background(Color.black.opacity(0.001).onTapGesture { model.onDismiss() })
        .animation(.spring(response: model.isOpen ? 0.46 : 0.32, dampingFraction: model.isOpen ? 0.74 : 0.92), value: model.isOpen)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.openSize)
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            earLabels
            if !model.trusted {
                PermissionCard()
            } else if model.extras.isEmpty {
                ProgressView().controlSize(.small).tint(.white).frame(height: 60)
            } else {
                grids
            }
        }
        .padding(.horizontal, NotchModel.Metric.padding)
        .environment(\.colorScheme, .dark)
    }

    private var earLabels: some View {
        HStack {
            Label("\(model.hidden.count) hidden", systemImage: "eye.slash.fill")
            Spacer(minLength: model.notch.width + 24)
            Text("\(model.extras.count) items")
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.45))
        .labelStyle(.titleAndIcon)
        .frame(height: model.notch.height)
        .opacity(model.isOpen && model.trusted && !model.extras.isEmpty ? 1 : 0)
        .animation(.easeOut(duration: model.isOpen ? 0.3 : 0.08).delay(model.isOpen ? 0.12 : 0), value: model.isOpen)
    }

    private var grids: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.hidden.isEmpty {
                section("Behind the notch", model.hidden, offset: 0)
            }
            if !model.visible.isEmpty {
                section("In the menu bar", model.visible, offset: model.hidden.count)
            }
            caption
        }
        .padding(.top, 10)
    }

    private func section(_ title: String, _ extras: [MenuExtra], offset: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.32))
                .frame(height: NotchModel.Metric.header, alignment: .top)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(NotchModel.Metric.tileWidth), spacing: NotchModel.Metric.spacing), count: model.columns),
                      alignment: .leading, spacing: NotchModel.Metric.spacing) {
                ForEach(Array(extras.enumerated()), id: \.element.id) { index, extra in
                    Tile(extra: extra, index: index + offset, model: model)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var caption: some View {
        let hovered = model.extras.first { $0.id == model.hoveredID }
        return Text(hovered?.detail ?? "Click an item to open it  ·  esc to close")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(hovered == nil ? 0.28 : 0.7))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .id(hovered?.id ?? "idle")
            .transition(.opacity.combined(with: .offset(y: 3)))
            .animation(.easeOut(duration: 0.15), value: model.hoveredID)
            .opacity(model.isOpen ? 1 : 0)
    }
}

// MARK: - Tile

struct Tile: View {
    let extra: MenuExtra
    let index: Int
    @ObservedObject var model: NotchModel

    private var hovered: Bool { model.hoveredID == extra.id }

    var body: some View {
        Button { model.onSelect(extra) } label: {
            VStack(spacing: 7) {
                TileFace(extra: extra, hovered: hovered)
                Text(extra.name)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(hovered ? 0.95 : extra.isHidden ? 0.62 : 0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: NotchModel.Metric.tileWidth)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { inside in
            if inside { model.hoveredID = extra.id } else if model.hoveredID == extra.id { model.hoveredID = nil }
        }
        // Staggered entrance: tiles bloom out of the notch one after another.
        .opacity(model.isOpen ? 1 : 0)
        .scaleEffect(model.isOpen ? 1 : 0.5, anchor: .top)
        .blur(radius: model.isOpen ? 0 : 8)
        .offset(y: model.isOpen ? 0 : -14)
        .animation(model.isOpen
                   ? .spring(response: 0.5, dampingFraction: 0.7).delay(0.07 + Double(index) * 0.022)
                   : .easeIn(duration: 0.1), value: model.isOpen)
    }
}

struct TileFace: View {
    let extra: MenuExtra
    let hovered: Bool

    var body: some View {
        let tint = Color(nsColor: extra.tint)
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(hovered ? 0.11 : extra.isHidden ? 0.06 : 0.035))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(RadialGradient(colors: [tint.opacity(0.55), .clear], center: .center, startRadius: 2, endRadius: 40))
                .opacity(hovered ? 1 : 0)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(hovered ? 0.18 : 0.06), lineWidth: 0.5)
            if let icon = extra.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 36, height: 36)
                    .shadow(color: tint.opacity(hovered ? 0.6 : 0), radius: 10)
            } else if let symbol = extra.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white.opacity(hovered ? 1 : 0.85))
            }
            if extra.isHidden {
                Circle().fill(Color(red: 1, green: 0.62, blue: 0.2))
                    .frame(width: 5, height: 5)
                    .shadow(color: .orange, radius: 3)
                    .offset(x: 19, y: -19)
            }
        }
        .frame(width: 54, height: 54)
        .scaleEffect(hovered ? 1.07 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.6), value: hovered)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Permission

struct PermissionCard: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("One permission, then you're set")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("Notchless reads your menu bar through Accessibility.\nNothing leaves your Mac.")
                .font(.system(size: 11, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.5))
            Button("Open Accessibility Settings") {
                MenuExtras.requestTrust()
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.15))
            .controlSize(.small)
        }
        .padding(.top, 14)
    }
}
