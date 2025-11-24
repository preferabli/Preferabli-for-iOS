// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// A location (must have either a latitude / longitude or a zip code).
@Model
public final class Location: HasIntID, HasTimestamps {
    
    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    public var latitude: Double?
    public var longitude: Double?
    public var zip_code: String?

    public init(id: Int) { self.id = id }

    init(id: Int, latitude: Double? = nil, longitude: Double? = nil, zip_code: String? = nil) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
    }
    
    public static func predicate(forID id: Int) -> Predicate<Location> {
        #Predicate<Location> { $0.id == id }
    }
}
