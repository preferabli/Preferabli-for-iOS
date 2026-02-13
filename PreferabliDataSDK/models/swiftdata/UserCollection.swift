// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

@Model
public final class UserCollection: HasIntID, HasTimestamps {
    
    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    public var collection_id: Int
    public var relationship_type: String?
    public var is_pinned: Bool?
    public var is_admin: Bool?
    public var is_editor: Bool?
    public var is_viewer: Bool?
    public var archived_at: Date?

    // relationships
    @Relationship(inverse: \Collection.user_collections)
    public var collection: Collection
    
    public init(id: Int, collection_id : Int, collection : Collection) {
        self.id = id
        self.collection_id = collection_id
        self.collection = collection
    }

    public static func predicate(forID id: Int) -> Predicate<UserCollection> {
        #Predicate<UserCollection> { $0.id == id }
    }
}
