//
//  SoftTheme.swift
//  Dartify
//
//  The "soft UI" look from the React app (index.css, softTokens.ts, SoftUI.tsx) in SwiftUI.
//

import SwiftUI

extension Color {
    nonisolated init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

enum Soft {
    static let canvas = Color(hex: 0xEDEDEF)
    static let shell = Color(hex: 0xF6F6F7)
    static let slate = Color(hex: 0x1E2530)
    static let slateSoft = Color(hex: 0x6B717C)
    static let subtle = Color(hex: 0x9AA0A9)
    static let track = Color(hex: 0xEBEBEE)
    static let line = Color(hex: 0xE5E5E7)
    static let charcoal = Color(hex: 0x1C1D20)
    static let danger = Color(hex: 0xD6453D)
    static let shadow = Color(red: 20 / 255, green: 24 / 255, blue: 32 / 255)
}

/// Accent palette: a solid colour, an ink (text) and a tint (chip background).
nonisolated enum Accent: CaseIterable {
    case mint, azure, coral, orchid

    var solid: Color {
        switch self {
        case .mint: Color(hex: 0x3FBF8A)
        case .azure: Color(hex: 0x5B7BF2)
        case .coral: Color(hex: 0xF2894A)
        case .orchid: Color(hex: 0xD25AD8)
        }
    }

    var ink: Color {
        switch self {
        case .mint: Color(hex: 0x23865C)
        case .azure: Color(hex: 0x4863DB)
        case .coral: Color(hex: 0xDB6A30)
        case .orchid: Color(hex: 0xB743BE)
        }
    }

    var tint: Color {
        switch self {
        case .mint: Color(hex: 0xE2F5EC)
        case .azure: Color(hex: 0xE8EDFE)
        case .coral: Color(hex: 0xFDEEE4)
        case .orchid: Color(hex: 0xF8E7FA)
        }
    }

    /// Player seat colours in throw order (P1–P4).
    static func slot(_ index: Int) -> Accent { allCases[index % allCases.count] }

    /// Stable colour for a name, for players shown outside a match.
    static func forName(_ name: String) -> Accent {
        var h: Int32 = 0
        for scalar in name.unicodeScalars { h = h &* 31 &+ Int32(truncatingIfNeeded: scalar.value) }
        return allCases[Int(h.magnitude) % allCases.count]
    }
}

// MARK: - Surfaces
//
// Shadows always go on the background shape, never on the whole view: `.shadow` on a container blurs
// everything inside it (every card, icon and glyph), which is expensive and makes animations stutter.

extension View {
    /// Light grey rounded container that groups cards (`.soft-shell`).
    func softShell() -> some View {
        background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Soft.shell)
                .stroke(.white.opacity(0.9), lineWidth: 1)
                .softShadow(near: 0.04, far: 0.12, radius: 24, y: 18)
        }
    }

    /// White card (`.soft-card`).
    func softCard(cornerRadius: CGFloat = 24) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.white)
                .softShadow(near: 0.04, far: 0.10, radius: 14, y: 8)
        }
    }

    /// Floating white control, e.g. round icon buttons (`.soft-float`).
    func softFloat<S: Shape>(_ shape: S) -> some View {
        background {
            shape.fill(.white).softShadow(near: 0.06, far: 0.14, radius: 10, y: 6)
        }
    }

    /// The two-layer shadow used throughout: a tight contact shadow plus a soft drop shadow.
    /// Apply it to a background shape only.
    func softShadow(near: Double, far: Double, radius: CGFloat, y: CGFloat) -> some View {
        shadow(color: Soft.shadow.opacity(near), radius: 1, y: 1)
            .shadow(color: Soft.shadow.opacity(far), radius: radius, y: y)
    }

    /// Tight negative letter spacing used for display text (`.tracking-display`).
    func displayTracking() -> some View {
        tracking(-0.4)
    }
}

// MARK: - Buttons

/// Shrinks slightly while pressed (`.soft-press`).
struct SoftPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// Charcoal pill button (`.soft-primary`), greyed out when disabled.
struct SoftPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 58
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: height)
            .background {
                Capsule()
                    .fill(isEnabled ? Soft.charcoal : Color(hex: 0xC9CBD0))
                    .shadow(color: Soft.shadow.opacity(isEnabled ? 0.35 : 0), radius: 12, y: 8)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// White floating pill button (`.soft-float` + `.soft-press`).
struct SoftSecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Soft.slate)
            .frame(maxWidth: .infinity, minHeight: height)
            .softFloat(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// Round white icon button, e.g. back / close.
struct SoftIconButton: View {
    let systemImage: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(Soft.slate)
                .frame(width: size, height: size)
                .softFloat(Circle())
        }
        .buttonStyle(SoftPressStyle())
    }
}

// MARK: - Components

/// Grey icon + grey title heading a shell (`ShellTitle`).
struct ShellTitle<Trailing: View>: View {
    let systemImage: String
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Label {
                Text(title).font(.system(size: 21, weight: .semibold)).displayTracking()
            } icon: {
                Image(systemName: systemImage).font(.system(size: 18, weight: .semibold))
            }
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Soft.slateSoft)
            Spacer()
            trailing
        }
    }
}

extension ShellTitle where Trailing == EmptyView {
    init(systemImage: String, title: String) {
        self.init(systemImage: systemImage, title: title) { EmptyView() }
    }
}

/// Tinted pill (`Badge`).
struct SoftBadge: View {
    let accent: Accent
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(accent.ink)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(accent.tint, in: Capsule())
    }
}

/// Initial on a pastel disc (`Avatar`).
struct SoftAvatar: View {
    let name: String
    var size: CGFloat = 32
    var accent: Accent?

    var body: some View {
        let a = accent ?? Accent.forName(name)
        Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(a.ink)
            .frame(width: size, height: size)
            .background(a.tint, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }
}

/// Sliding white thumb on a grey track (`Segmented`).
struct SoftSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var compact = false
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.system(size: compact ? 13 : 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(selected ? Soft.slate : Soft.subtle)
                        .frame(maxWidth: .infinity, minHeight: compact ? 28 : 40)
                        .background {
                            if selected {
                                Capsule().fill(.white)
                                    .shadow(color: Soft.shadow.opacity(0.12), radius: 6, y: 3)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Soft.track, in: Capsule())
    }
}

/// iOS-style switch row with a label and description (`ToggleRow`).
struct SoftToggleRow: View {
    let label: String
    var description: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn.animation(.spring(response: 0.38, dampingFraction: 0.85))) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isOn ? Soft.slate : Soft.slateSoft)
                if let description {
                    Text(description).font(.system(size: 13)).foregroundStyle(Soft.subtle)
                }
            }
        }
        .tint(Accent.mint.ink)
        .padding(.vertical, 8)
    }
}

/// Tinted icon chip, big coloured number and a small label (`StatTile`).
struct StatTile: View {
    let systemImage: String
    let accent: Accent
    let value: String?
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent.ink)
                .frame(width: 36, height: 36)
                .background(accent.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(value ?? "–")
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()
                .displayTracking()
                .foregroundStyle(value == nil ? Soft.subtle : accent.ink)
                .padding(.top, 12)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Soft.subtle)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}
