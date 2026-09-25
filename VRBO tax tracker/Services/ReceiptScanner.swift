//
//  ReceiptScanner.swift
//  VRBO tax tracker
//
//  Reads a photographed receipt with Vision and pulls out the total, the date
//  and the merchant. Text recognition happens on device — a receipt never
//  leaves the phone.
//

import CoreGraphics
import Foundation
import ImageIO
import Vision

public struct ScannedReceipt: Sendable {
    public nonisolated var recognizedText: String
    public nonisolated var lines: [String]
    public nonisolated var suggestedTotal: Decimal?
    public nonisolated var suggestedDate: Date?
    public nonisolated var suggestedVendor: String?
    public nonisolated var suggestedCategory: ExpenseCategory?
    public nonisolated var confidence: Double

    public nonisolated var hasUsableResult: Bool {
        suggestedTotal != nil || suggestedVendor != nil
    }
}

public enum ReceiptScannerError: LocalizedError {
    case imageUnreadable
    case noTextFound

    public nonisolated var errorDescription: String? {
        switch self {
        case .imageUnreadable: "That image could not be read. Try a sharper, better-lit photo."
        case .noTextFound: "No text was found on the receipt. Try again with the whole receipt in frame."
        }
    }
}

public enum ReceiptScanner {

    public nonisolated static func scan(imageData: Data) async throws -> ScannedReceipt {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ReceiptScannerError.imageUnreadable
        }
        return try await scan(cgImage: cgImage)
    }

    public nonisolated static func scan(cgImage: CGImage) async throws -> ScannedReceipt {
        let observations = try await recognizeText(in: cgImage)
        guard !observations.isEmpty else { throw ReceiptScannerError.noTextFound }

        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let averageConfidence = observations
            .compactMap { $0.topCandidates(1).first?.confidence }
            .map(Double.init)
            .reduce(0, +) / Double(max(1, observations.count))

        let text = lines.joined(separator: "\n")
        let vendor = guessVendor(from: lines)

        return ScannedReceipt(
            recognizedText: text,
            lines: lines,
            suggestedTotal: guessTotal(from: lines),
            suggestedDate: guessDate(from: lines),
            suggestedVendor: vendor,
            suggestedCategory: vendor.flatMap { CategoryGuesser.guess(vendor: $0) },
            confidence: averageConfidence
        )
    }

    private static func recognizeText(in cgImage: CGImage) async throws -> [VNRecognizedTextObservation] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: request.results as? [VNRecognizedTextObservation] ?? [])
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Extraction

    private static let totalKeywords = ["total", "amount due", "balance due", "grand total", "charged", "you paid"]
    private static let ignoreKeywords = ["subtotal", "sub total", "tax", "tip", "change", "cash", "savings", "discount"]

    /// Prefers a line that names itself as the total; falls back to the largest
    /// money-looking value on the receipt.
    nonisolated static func guessTotal(from lines: [String]) -> Decimal? {
        var labelled: [Decimal] = []
        var allAmounts: [Decimal] = []

        for line in lines {
            let lower = line.lowercased()
            let amounts = currencyValues(in: line)
            allAmounts.append(contentsOf: amounts)

            guard !amounts.isEmpty else { continue }
            let isIgnored = ignoreKeywords.contains { lower.contains($0) }
                && !totalKeywords.contains { lower.hasPrefix($0) }
            guard !isIgnored else { continue }
            if totalKeywords.contains(where: { lower.contains($0) }) {
                labelled.append(contentsOf: amounts)
            }
        }

        if let best = labelled.max() { return best }
        return allAmounts.max()
    }

    nonisolated static func currencyValues(in line: String) -> [Decimal] {
        var results: [Decimal] = []
        let pattern = #"[$€£]?\s?\d{1,3}(?:[,\d]{0,12})?[.,]\d{2}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        for match in regex.matches(in: line, range: range) {
            guard let matchRange = Range(match.range, in: line) else { continue }
            if let value = CSVParser.decimal(String(line[matchRange])), value > 0, value < 1_000_000 {
                results.append(value)
            }
        }
        return results
    }

    nonisolated static func guessDate(from lines: [String]) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        for line in lines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = detector?.firstMatch(in: line, range: range), let date = match.date {
                // Receipts are not dated years out; reject an obvious misread.
                let year = DateMath.year(of: date)
                if year >= 2000 && year <= DateMath.currentYear + 1 { return date }
            }
        }
        return nil
    }

    /// The merchant name is almost always in the first couple of lines and
    /// carries no digits.
    nonisolated static func guessVendor(from lines: [String]) -> String? {
        for line in lines.prefix(6) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 3, trimmed.count <= 40 else { continue }
            let digitCount = trimmed.filter(\.isNumber).count
            guard digitCount <= 1 else { continue }
            let letters = trimmed.filter(\.isLetter).count
            guard letters >= 3 else { continue }
            return trimmed.capitalized(with: Locale.current)
        }
        return nil
    }
}
