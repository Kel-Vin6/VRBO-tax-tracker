//
//  PlatformSupport.swift
//  VRBO tax tracker
//
//  The app ships for iPhone, iPad, Mac and Vision Pro from one target, so the
//  handful of genuinely platform-specific affordances live behind these
//  modifiers rather than scattered `#if` blocks through the views.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

public extension View {

    /// A decimal keypad on touch platforms, a no-op elsewhere.
    @ViewBuilder
    func decimalKeyboard() -> some View {
        #if os(iOS) || os(visionOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    @ViewBuilder
    func numberKeyboard() -> some View {
        #if os(iOS) || os(visionOS)
        self.keyboardType(.numberPad)
        #else
        self
        #endif
    }

    @ViewBuilder
    func emailKeyboard() -> some View {
        #if os(iOS) || os(visionOS)
        self.keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }

    /// Grouped list styling on touch platforms; the Mac gets its own default.
    @ViewBuilder
    func platformFormStyle() -> some View {
        #if os(macOS)
        self.formStyle(.grouped)
        #else
        self
        #endif
    }

    /// Inline navigation titles read better in the dense screens of this app.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS) || os(visionOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Inset-grouped lists on touch platforms, the Mac's own inset list there.
    @ViewBuilder
    func platformListStyle() -> some View {
        #if os(macOS)
        self.listStyle(.inset)
        #else
        self.listStyle(.insetGrouped)
        #endif
    }

    @ViewBuilder
    func hidesKeyboardOnScroll() -> some View {
        #if os(iOS)
        self.scrollDismissesKeyboard(.interactively)
        #else
        self
        #endif
    }
}

public enum Haptics {

    public enum Kind {
        case success, warning, error, selection, impact
    }

    /// Feedback where the platform supports it, silence where it does not.
    public static func play(_ kind: Kind) {
        #if os(iOS)
        switch kind {
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .impact:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        #endif
    }
}

/// Screen-size classes the layouts branch on.
public enum LayoutWidth {
    public static func columns(for width: CGFloat) -> Int {
        switch width {
        case ..<540: 1
        case 540..<900: 2
        case 900..<1300: 3
        default: 4
        }
    }
}
