//
//  KillerViews.swift
//  Dartify
//

import SwiftUI

/// The scary marker for a killer: a skull on a red disc with a slow, menacing pulse.
struct KillerBadge: View {
    var size: CGFloat = 22
    @State private var pulse = false

    var body: some View {
        Text("💀")
            .font(.system(size: size))
            .padding(size * 0.22)
            .background {
                Circle()
                    .fill(Soft.danger.opacity(0.22))
                    .shadow(color: Soft.danger.opacity(pulse ? 0.9 : 0.35), radius: pulse ? size * 0.6 : size * 0.2)
            }
            .scaleEffect(pulse ? 1.1 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            }
            .accessibilityLabel("Killer")
    }
}

/// Three dots showing points towards becoming a killer.
struct KillerPips: View {
    let points: Int
    var size: CGFloat = 7
    var filled: Color = Soft.danger

    var body: some View {
        HStack(spacing: size * 0.6) {
            ForEach(0..<KillerConfig.killerPoints, id: \.self) { i in
                Circle()
                    .fill(i < points ? AnyShapeStyle(filled) : AnyShapeStyle(.tertiary))
                    .frame(width: size, height: size)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: points)
    }
}
