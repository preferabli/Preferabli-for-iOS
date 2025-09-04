// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

@Model
public final class UserCollection: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date?
    public var updated_at: Date?
    var collection_id: Int?
    var relationship_type: String?
    var is_pinned: Bool?
    var is_admin: Bool?
    var is_editor: Bool?
    var is_viewer: Bool?
    var archived_at: Date?

    @Relationship(deleteRule: .nullify) var collection: Collection?

    public init(id: Int) { self.id = id }

    init(collection_id: Int? = nil, id: Int, relationship_type: String? = nil, is_pinned: Bool? = nil, is_admin: Bool? = nil, is_editor: Bool? = nil, is_viewer: Bool? = nil, archived_at: Date? = nil, created_at: Date? = nil, updated_at: Date? = nil, collection: Collection? = nil) {
        self.collection_id = collection_id
        self.id = id
        self.relationship_type = relationship_type
        self.is_pinned = is_pinned
        self.is_admin = is_admin
        self.is_editor = is_editor
        self.is_viewer = is_viewer
        self.archived_at = archived_at
        self.created_at = created_at
        self.updated_at = updated_at
        self.collection = collection
    }
}
