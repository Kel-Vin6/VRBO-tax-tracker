//
//  PersonalUseEntry.swift
//  VRBO tax tracker
//

import Foundation
import SwiftData

@Model
public final class PersonalUseEntry {

    public var id: UUID = UUID()
    public var startDate: Date = Date()
    public var endDate: Date = Date()
    public var kindRaw: String = PersonalUseKind.owner.rawValue
    public var occupantName: String = ""
    public var notes: String = ""
    /// Rent actually collected from a family member or friend, if any. Used to
    /// show how far below market the stay was.
    public var rentCollected: Decimal = 0
    public var createdAt: Date = Date()

    public var property: Property?

    public init(
        startDate: Date = Date(),
        endDate: Date = Date(),
        kind: PersonalUseKind = .owner,
        property: Property? = nil
    ) {
        self.id = UUID()
        self.startDate = startDate
        self.endDate = endDate
        self.kindRaw = kind.rawValue
        self.property = property
        self.createdAt = Date()
    }

    public var kind: PersonalUseKind {
        get { PersonalUseKind(rawValue: kindRaw) ?? .owner }
        set { kindRaw = newValue.rawValue }
    }

    /// Days of use are counted inclusively — arrive Friday, leave Sunday is
    /// three days of use even though it is only two nights.
    public var dayCount: Int { DateMath.inclusiveDays(from: startDate, to: endDate) }

    public func dayCount(inYear year: Int) -> Int {
        DateMath.days(from: startDate, to: endDate, inYear: year)
    }

    public var countsAsPersonalUse: Bool { kind.countsAsPersonalUse }

    public var dateRangeLabel: String {
        dayCount <= 1
            ? Fmt.shortDate(startDate)
            : "\(Fmt.dayMonth(startDate)) – \(Fmt.dayMonth(endDate))"
    }
}
