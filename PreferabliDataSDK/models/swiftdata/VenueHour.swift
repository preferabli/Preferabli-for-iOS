// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// Represents a ``Venue``s open and close times for a given day. Each day of the week has separate corresponding values.
@Model
public final class VenueHour: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    public var weekday: String?
    public var open_time: String?
    public var close_time: String?
    public var is_closed: Bool?
    
    // relationships
    @Relationship(deleteRule: .nullify) public var venue: Venue?

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

    public var day_of_week : Weekday? {
        Weekday.getWeekdayFromString(weekday: weekday)
    }
    
    public static func predicate(forID id: Int) -> Predicate<VenueHour> {
        #Predicate<VenueHour> { $0.id == id }
    }
}


/// Represents a day of the week for use within ``VenueHour``.
public enum Weekday {
    case MONDAY
    case TUESDAY
    case WEDNESDAY
    case THURSDAY
    case FRIDAY
    case SATURDAY
    case SUNDAY

    static internal func getWeekdayFromString(weekday : String?) -> Weekday? {
        if let w = weekday {
            switch w {
            case "monday":    return .MONDAY
            case "tuesday":   return .TUESDAY
            case "wednesday": return .WEDNESDAY
            case "thursday":  return .THURSDAY
            case "friday":    return .FRIDAY
            case "saturday":  return .SATURDAY
            case "sunday":    return .SUNDAY
            default:
                return nil
            }
        }
        return nil
    }

    internal func getStringFromWeekday() -> String {
        switch self {
        case .MONDAY:    return "monday"
        case .TUESDAY:   return "tuesday"
        case .WEDNESDAY: return "wednesday"
        case .THURSDAY:  return "thursday"
        case .FRIDAY:    return "friday"
        case .SATURDAY:  return "saturday"
        case .SUNDAY:    return "sunday"
        }
    }

    public func compare(_ other: Weekday) -> ComparisonResult {
        return self.getStringFromWeekday().caseInsensitiveCompare(other.getStringFromWeekday())
    }
}
