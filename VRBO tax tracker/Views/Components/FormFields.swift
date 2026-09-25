//
//  FormFields.swift
//  VRBO tax tracker
//
//  The input controls the editors are built from. Money is always a `Decimal`
//  bound to a currency format so what the user types and what the tax engine
//  reads can never drift apart.
//

import SwiftData
import SwiftUI

// MARK: - Money

public struct CurrencyField: View {
    let title: String
    @Binding var amount: Decimal
    var caption: String?
    var isProminent: Bool = false

    @Environment(AppSettings.self) private var settings
    @FocusState private var isFocused: Bool

    public init(
        _ title: String,
        amount: Binding<Decimal>,
        caption: String? = nil,
        isProminent: Bool = false
    ) {
        self.title = title
        self._amount = amount
        self.caption = caption
        self.isProminent = isProminent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(isProminent ? .subheadline.weight(.semibold) : .subheadline)
                Spacer(minLength: 12)
                TextField(
                    title,
                    value: $amount,
                    format: .currency(code: settings.currencyCode)
                )
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .decimalKeyboard()
                .focused($isFocused)
                .font(isProminent ? .body.weight(.semibold) : .body)
                .textFieldStyle(.plain)
            }
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }
}

// MARK: - Percent

public struct PercentField: View {
    let title: String
    @Binding var value: Double
    var caption: String?
    var range: ClosedRange<Double> = 0...100

    public init(
        _ title: String,
        value: Binding<Double>,
        caption: String? = nil,
        range: ClosedRange<Double> = 0...100
    ) {
        self.title = title
        self._value = value
        self.caption = caption
        self.range = range
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline)
                Spacer(minLength: 12)
                TextField(title, value: $value, format: .number.precision(.fractionLength(0...2)))
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .decimalKeyboard()
                    .frame(maxWidth: 80)
                Text("%").foregroundStyle(.secondary)
            }
            if range.upperBound <= 100 {
                Slider(value: $value, in: range, step: 1)
                    .tint(.accentColor)
            }
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Numbers

public struct NumberField: View {
    let title: String
    @Binding var value: Double
    var unit: String?
    var fractionDigits: Int = 1

    public init(_ title: String, value: Binding<Double>, unit: String? = nil, fractionDigits: Int = 1) {
        self.title = title
        self._value = value
        self.unit = unit
        self.fractionDigits = fractionDigits
    }

    public var body: some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer(minLength: 12)
            TextField(
                title,
                value: $value,
                format: .number.precision(.fractionLength(0...fractionDigits))
            )
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .decimalKeyboard()
            .frame(maxWidth: 110)
            if let unit {
                Text(unit).foregroundStyle(.secondary).font(.subheadline)
            }
        }
    }
}

public struct IntegerField: View {
    let title: String
    @Binding var value: Int
    var unit: String?

    public init(_ title: String, value: Binding<Int>, unit: String? = nil) {
        self.title = title
        self._value = value
        self.unit = unit
    }

    public var body: some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer(minLength: 12)
            TextField(title, value: $value, format: .number)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .numberKeyboard()
                .frame(maxWidth: 90)
            if let unit {
                Text(unit).foregroundStyle(.secondary).font(.subheadline)
            }
        }
    }
}

// MARK: - Property picker

public struct PropertyPickerField: View {
    let title: String
    @Binding var selection: Property?
    let properties: [Property]
    var allowsNone: Bool = false
    var noneLabel: String = "None"

    public init(
        _ title: String = "Property",
        selection: Binding<Property?>,
        properties: [Property],
        allowsNone: Bool = false,
        noneLabel: String = "None"
    ) {
        self.title = title
        self._selection = selection
        self.properties = properties
        self.allowsNone = allowsNone
        self.noneLabel = noneLabel
    }

    public var body: some View {
        Picker(title, selection: Binding(
            get: { selection?.id },
            set: { newValue in
                selection = properties.first { $0.id == newValue }
            }
        )) {
            if allowsNone {
                Text(noneLabel).tag(UUID?.none)
            }
            ForEach(properties) { property in
                Label {
                    Text(property.displayName)
                } icon: {
                    Image(systemName: "house.fill")
                        .foregroundStyle(property.color)
                }
                .tag(UUID?.some(property.id))
            }
        }
    }
}

// MARK: - Live summary strip

/// A compact read-out that updates as the user types, so a mistyped figure is
/// obvious before the sheet is dismissed.
public struct LiveSummaryStrip: View {
    public struct Item: Identifiable {
        public var id = UUID()
        public var label: String
        public var value: String
        public var tint: Color

        public init(label: String, value: String, tint: Color = .primary) {
            self.label = label
            self.value = value
            self.tint = tint
        }
    }

    let items: [Item]

    public init(items: [Item]) { self.items = items }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                if index > 0 { Divider().frame(height: 26) }
                VStack(spacing: 2) {
                    Text(item.value)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(item.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text(item.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
    }
}
