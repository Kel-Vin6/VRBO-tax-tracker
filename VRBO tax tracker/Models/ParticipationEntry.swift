//
//  ParticipationEntry.swift
//  VRBO tax tracker
//

import Foundation
import SwiftData

/// One logged block of work on the rental business. These hours decide whether
/// a short-term rental loss is passive or non-passive, which is often worth
/// more than every deduction on the return combined.
@Model
public final class ParticipationEntry {

    public var id: UUID = UUID()
    public var date: Date = Date()
    public var hours: Double = 0
    public var activityRaw: String = ParticipationActivity.guestCommunication.rawValue
    public var descriptionText: String = ""
    /// Work done by a spouse counts toward the taxpayer's participation.
    public var performedBySpouse: Bool = false
    /// Hours someone you paid also worked on the property, needed for the
    /// "more than anyone else" test.
    public var contractorHoursSameDay: Double = 0
    public var wasTimed: Bool = false
    public var createdAt: Date = Date()
    public var loggedSameDay: Bool = true

    public var property: Property?

    public init(
        date: Date = Date(),
        hours: Double = 0,
        activity: ParticipationActivity = .guestCommunication,
        property: Property? = nil
    ) {
        self.id = UUID()
        self.date = date
        self.hours = hours
        self.activityRaw = activity.rawValue
        self.property = property
        self.createdAt = Date()
    }

    public var activity: ParticipationActivity {
        get { ParticipationActivity(rawValue: activityRaw) ?? .guestCommunication }
        set { activityRaw = newValue.rawValue }
    }

    /// Investor-type hours are excluded from the §469 tests.
    public var countsForMaterialParticipation: Bool { !activity.isInvestorActivity }
    public var countsForQBISafeHarbor: Bool { activity.countsForQBISafeHarbor }

    public var qualifyingHours: Double { countsForMaterialParticipation ? hours : 0 }
}
