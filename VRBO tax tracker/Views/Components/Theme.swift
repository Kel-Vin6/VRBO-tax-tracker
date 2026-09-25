//
//  Theme.swift
//  VRBO tax tracker
//
//  Shared surface colours. Defined in terms of the semantic primary colour so
//  they adapt to light, dark and high-contrast on every platform the app ships
//  for, without per-platform system colour names.
//

import SwiftUI

public enum Theme {

    /// Fill behind a card sitting on the default background.
    public static let cardFill = Color.primary.opacity(0.045)
    /// Fill for a card nested inside another card.
    public static let nestedFill = Color.primary.opacity(0.07)
    /// Hairline border.
    public static let hairline = Color.primary.opacity(0.12)

    public static let cardRadius: CGFloat = 16
    public static let tileRadius: CGFloat = 14

    /// Money colouring used consistently everywhere a figure can go negative.
    public static func amountColor(_ value: Decimal) -> Color {
        if value > 0 { return .primary }
        if value < 0 { return .red }
        return .secondary
    }

    public static func resultColor(_ value: Decimal) -> Color {
        value < 0 ? .red : .green
    }
}

public extension View {
    /// The standard card treatment: subtle fill, continuous corners, hairline.
    func cardSurface(radius: CGFloat = Theme.cardRadius) -> some View {
        self
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            }
    }
}
