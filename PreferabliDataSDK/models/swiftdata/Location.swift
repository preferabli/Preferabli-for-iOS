// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// A location (must have either a latitude / longitude or a zip code).
@Model
public final class Location: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date?
    public var updated_at: Date?
    var latitude: Int?
    var longitude: Int?
    var zip_code: String?

    public init(id: Int) { self.id = id }

    init(id: Int, latitude: Int? = nil, longitude: Int? = nil, zip_code: String? = nil) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
    }
}
