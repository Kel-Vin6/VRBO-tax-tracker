//
//  Formatting.swift
//  VRBO tax tracker
//

import Foundation
import SwiftUI

public enum Fmt {

    /// Used where a figure is formatted outside a view that knows the user's
    /// chosen currency, such as an explanatory string built by an engine.
    public nonisolated static var defaultCurrencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    public nonisolated static func currency(
        _ value: Decimal,
        code: String = Fmt.defaultCurrencyCode,
        hideCents: Bool = false
    ) -> String {
        if hideCents {
            return value.rounded(0).formatted(.currency(code: code).precision(.fractionLength(0)))
        }
        return value.formatted(.currency(code: code))
    }

    /// Compact money for dense tiles: $12.4K, $1.2M.
    public nonisolated static func compactCurrency(
        _ value: Decimal,
        code: String = Fmt.defaultCurrencyCode
    ) -> String {
        let symbol = currencySymbol(for: code)
        let magnitude = abs(value.doubleValue)
        let sign = value < 0 ? "-" : ""
        switch magnitude {
        case 1_000_000...:
            return "\(sign)\(symbol)\((magnitude / 1_000_000).formatted(.number.precision(.fractionLength(0...1))))M"
        case 10_000...:
            return "\(sign)\(symbol)\((magnitude / 1_000).formatted(.number.precision(.fractionLength(0...1))))K"
        default:
            return currency(value, code: code, hideCents: magnitude >= 1000)
        }
    }

    public nonisolated static func currencySymbol(for code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }

    public nonisolated static func percent(_ value: Double, fractionDigits: Int = 1) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0...fractionDigits)))
    }

    public nonisolated static func ratioPercent(_ ratio: Double, fractionDigits: Int = 1) -> String {
        ratio.formatted(.percent.precision(.fractionLength(0...fractionDigits)))
    }

    public nonisolated static func number(_ value: Double, fractionDigits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...fractionDigits)))
    }

    public nonisolated static func miles(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) mi"
    }

    public nonisolated static func hours(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) h"
    }

    public nonisolated static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    public nonisolated static func mediumDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).day().year())
    }

    public nonisolated static func dayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    public nonisolated static func fileStamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    /// ISO-8601 calendar date, used in every CSV the app writes.
    public nonisolated static func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }
}

public extension Color {
    nonisolated init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}

/// The palette a user picks from when colour-coding a property.
public enum PropertyPalette {
    public nonisolated static let hexes: [String] = [
        "2E7D8F", "3A7D5D", "B4703A", "8B5E9B",
        "C05B4D", "4A6FA5", "7A8B3F", "9B6B4A",
        "5C6B8A", "A34A6B"
    ]

    public nonisolated static func color(for hex: String) -> Color {
        Color(hex: hex) ?? .accentColor
    }

    public nonisolated static func hex(forIndex index: Int) -> String {
        hexes[abs(index) % hexes.count]
    }
}
