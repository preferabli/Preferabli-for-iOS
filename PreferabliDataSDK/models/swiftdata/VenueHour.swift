// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// Represents a ``Venue``s open and close times for a given day. Each day of the week has separate corresponding values.
@Model
public final class VenueHour: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date?
    public var updated_at: Date?
    public var weekday: String?
    public var open_time: String?
    public var close_time: String?
    public var is_closed: Bool?

    public init(id: Int) { self.id = id }

    public init(
        id: Int,
        weekday: String? = nil,
        open_time: String? = nil,
        close_time: String? = nil,
        is_closed: Bool? = nil
    ) {
        self.id = id
        self.weekday = weekday
        self.open_time = open_time
        self.close_time = close_time
        self.is_closed = is_closed
    }

    public var day_of_week : Weekday {
        Weekday.getWeekdayFromString(weekday: weekday)
    }
}
