// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

@Model
public final class UserCollection: HasIntID, HasTimestamps {
    
    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    var collection_id: Int?
    var relationship_type: String?
    var is_pinned: Bool?
    var is_admin: Bool?
    var is_editor: Bool?
    var is_viewer: Bool?
    var archived_at: Date?

    // relationships
    @Relationship(deleteRule: .nullify, inverse: \Collection.user_collections) var collection: Collection?
    
    public init(id: Int) { self.id = id }

    public static func predicate(forID id: Int) -> Predicate<UserCollection> {
        #Predicate<UserCollection> { $0.id == id }
    }
}
