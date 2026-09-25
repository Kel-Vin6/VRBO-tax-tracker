//
//  CoreComponents.swift
//  VRBO tax tracker
//

import SwiftUI

// MARK: - Cards

public struct SectionCard<Content: View>: View {
    private let title: String?
    private let subtitle: String?
    private let symbol: String?
    private let content: Content

    public init(
        _ title: String? = nil,
        subtitle: String? = nil,
        symbol: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || subtitle != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if let title {
                            Text(title)
                                .font(.headline)
                        }
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

// MARK: - Stat tile

public struct StatTile: View {
    public var label: String
    public var value: String
    public var caption: String?
    public var symbol: String?
    public var tint: Color
    public var trend: Double?

    public init(
        label: String,
        value: String,
        caption: String? = nil,
        symbol: String? = nil,
        tint: Color = .accentColor,
        trend: Double? = nil
    ) {
        self.label = label
        self.value = value
        self.caption = caption
        self.symbol = symbol
        self.tint = tint
        self.trend = trend
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption)
                        .foregroundStyle(tint)
                }
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())

            if let trend {
                Label(
                    Fmt.percent(abs(trend)),
                    systemImage: trend >= 0 ? "arrow.up.right" : "arrow.down.right"
                )
                .font(.caption2.weight(.medium))
                .foregroundStyle(trend >= 0 ? Color.green : Color.red)
            } else if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardSurface(radius: Theme.tileRadius)
    }
}

// MARK: - Empty state

public struct EmptyStateView: View {
    public var symbol: String
    public var title: String
    public var message: String
    public var actionTitle: String?
    public var action: (() -> Void)?

    public init(
        symbol: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Callout

public struct InfoCallout: View {
    public enum Level {
        case info, success, caution, critical

        var tint: Color {
            switch self {
            case .info: .blue
            case .success: .green
            case .caution: .orange
            case .critical: .red
            }
        }

        var symbol: String {
            switch self {
            case .info: "info.circle.fill"
            case .success: "checkmark.circle.fill"
            case .caution: "exclamationmark.triangle.fill"
            case .critical: "exclamationmark.octagon.fill"
            }
        }
    }

    public var level: Level
    public var title: String?
    public var message: String

    public init(level: Level = .info, title: String? = nil, message: String) {
        self.level = level
        self.title = title
        self.message = message
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: level.symbol)
                .foregroundStyle(level.tint)
                .font(.subheadline)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(level.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Progress ring

public struct ProgressRing: View {
    public var progress: Double
    public var lineWidth: CGFloat
    public var tint: Color
    public var label: String?
    public var caption: String?

    public init(
        progress: Double,
        lineWidth: CGFloat = 12,
        tint: Color = .accentColor,
        label: String? = nil,
        caption: String? = nil
    ) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.tint = tint
        self.label = label
        self.caption = caption
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: progress)
            VStack(spacing: 1) {
                if let label {
                    Text(label)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Key/value row

public struct DetailRow: View {
    public var label: String
    public var value: String
    public var caption: String?
    public var isEmphasised: Bool
    public var valueColor: Color?

    public init(
        _ label: String,
        value: String,
        caption: String? = nil,
        isEmphasised: Bool = false,
        valueColor: Color? = nil
    ) {
        self.label = label
        self.value = value
        self.caption = caption
        self.isEmphasised = isEmphasised
        self.valueColor = valueColor
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(isEmphasised ? .subheadline.weight(.semibold) : .subheadline)
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .font(isEmphasised ? .subheadline.weight(.bold) : .subheadline)
                .monospacedDigit()
                .foregroundStyle(valueColor ?? (isEmphasised ? Color.primary : Color.secondary))
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Chips

public struct TagChip: View {
    public var text: String
    public var symbol: String?
    public var tint: Color

    public init(_ text: String, symbol: String? = nil, tint: Color = .secondary) {
        self.text = text
        self.symbol = symbol
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

public struct PropertyBadge: View {
    public var name: String
    public var monogram: String
    public var color: Color
    public var showsName: Bool

    public init(name: String, monogram: String, color: Color, showsName: Bool = true) {
        self.name = name
        self.monogram = monogram
        self.color = color
        self.showsName = showsName
    }

    public var body: some View {
        HStack(spacing: 8) {
            Text(monogram.isEmpty ? "•" : monogram)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            if showsName {
                Text(name)
                    .font(.subheadline)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Disclaimer

public struct TaxDisclaimer: View {
    public var compact: Bool

    public init(compact: Bool = false) { self.compact = compact }

    public var body: some View {
        Text("These figures are an estimate to help you plan and to hand a complete file to your accountant. They are not tax advice and not a filed return.")
            .font(compact ? .caption2 : .footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
