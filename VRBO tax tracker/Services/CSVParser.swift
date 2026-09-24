//
//  CSVParser.swift
//  VRBO tax tracker
//
//  A correct RFC 4180 parser. Platform payout exports contain quoted commas in
//  listing names and newlines inside address fields, which a split(separator:)
//  approach silently mangles.
//

import Foundation

public struct CSVTable: Sendable {
    public var headers: [String]
    public var rows: [[String]]

    public var isEmpty: Bool { rows.isEmpty }

    public func value(_ row: [String], at index: Int?) -> String {
        guard let index, index >= 0, index < row.count else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Index of the first header matching any of the supplied candidates,
    /// compared case- and punctuation-insensitively.
    public func columnIndex(matching candidates: [String]) -> Int? {
        let normalizedHeaders = headers.map(CSVParser.normalize)
        for candidate in candidates {
            let needle = CSVParser.normalize(candidate)
            if let index = normalizedHeaders.firstIndex(of: needle) { return index }
        }
        for candidate in candidates {
            let needle = CSVParser.normalize(candidate)
            if let index = normalizedHeaders.firstIndex(where: { $0.contains(needle) }) { return index }
        }
        return nil
    }
}

public enum CSVParser {

    public static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    public static func parse(_ text: String, delimiter: Character = ",") -> CSVTable {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() {
            currentRow.append(currentField)
            currentField = ""
        }

        func endRow() {
            endField()
            if currentRow.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                rows.append(currentRow)
            }
            currentRow = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil

            if insideQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            currentField.append("\"")
                        } else {
                            insideQuotes = false
                            pending = next
                        }
                    } else {
                        insideQuotes = false
                    }
                } else {
                    currentField.append(character)
                }
                continue
            }

            switch character {
            case "\"":
                insideQuotes = true
            case delimiter:
                endField()
            case "\n":
                endRow()
            case "\r":
                // Swallow CR; the following LF closes the row.
                if let next = iterator.next() {
                    if next == "\n" {
                        endRow()
                    } else {
                        endRow()
                        pending = next
                    }
                } else {
                    endRow()
                }
            default:
                currentField.append(character)
            }
        }

        if !currentField.isEmpty || !currentRow.isEmpty { endRow() }

        guard let headerRow = rows.first else {
            return CSVTable(headers: [], rows: [])
        }
        return CSVTable(
            headers: headerRow.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
            rows: Array(rows.dropFirst())
        )
    }

    /// Escapes a value for output, quoting only when it has to.
    public static func escape(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\"")
            || value.contains("\n") || value.contains("\r")
        guard needsQuoting else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    public static func line(_ values: [String]) -> String {
        values.map(escape).joined(separator: ",")
    }

    // MARK: Value coercion

    /// Parses money written the many ways a platform export writes it:
    /// "$1,234.56", "(45.00)", "1.234,56 €", "-", "".
    public static func decimal(_ raw: String) -> Decimal? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != "-", text != "—" else { return nil }

        var isNegative = false
        if text.hasPrefix("(") && text.hasSuffix(")") {
            isNegative = true
            text = String(text.dropFirst().dropLast())
        }
        if text.hasPrefix("-") {
            isNegative = true
            text = String(text.dropFirst())
        }

        let allowed = CharacterSet(charactersIn: "0123456789.,")
        text = String(text.unicodeScalars.filter { allowed.contains($0) })
        guard !text.isEmpty else { return nil }

        // Decide which separator is the decimal point.
        let lastComma = text.lastIndex(of: ",")
        let lastDot = text.lastIndex(of: ".")
        if let comma = lastComma, let dot = lastDot {
            if comma > dot {
                text = text.replacingOccurrences(of: ".", with: "")
                text = text.replacingOccurrences(of: ",", with: ".")
            } else {
                text = text.replacingOccurrences(of: ",", with: "")
            }
        } else if let comma = lastComma {
            let decimals = text.distance(from: text.index(after: comma), to: text.endIndex)
            text = decimals == 3
                ? text.replacingOccurrences(of: ",", with: "")
                : text.replacingOccurrences(of: ",", with: ".")
        }

        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return isNegative ? -value : value
    }

    private static let dateFormats = [
        "yyyy-MM-dd",
        "MM/dd/yyyy",
        "M/d/yyyy",
        "dd/MM/yyyy",
        "d/M/yyyy",
        "MM-dd-yyyy",
        "yyyy/MM/dd",
        "MMM d, yyyy",
        "MMMM d, yyyy",
        "d MMM yyyy",
        "yyyy-MM-dd'T'HH:mm:ss",
        "MM/dd/yy"
    ]

    public static func date(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        for format in dateFormats {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: text) { return parsed }
        }
        return ISO8601DateFormatter().date(from: text)
    }

    public static func integer(_ raw: String) -> Int? {
        let digits = raw.filter { $0.isNumber || $0 == "-" }
        return Int(digits)
    }
}
