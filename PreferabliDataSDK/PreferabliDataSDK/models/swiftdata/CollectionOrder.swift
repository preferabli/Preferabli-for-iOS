// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// The link between a ``Tag`` (which in turn references a ``Product``) and a ``Collection``, including its ordering within the Collection.
@Model
public final class CollectionOrder: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date?
    public var updated_at: Date?
    public var tag_id: Int?
    public var order: Int?
    @Relationship(deleteRule: .nullify) public var group: CollectionGroup?
    @Relationship(deleteRule: .nullify) public var tag: Tag?
    public var group_id: Int?

    public init(id: Int) { self.id = id }

    public init(id: Int, tag_id: Int? = nil, order: Int? = nil, group: CollectionGroup? = nil, tag: Tag? = nil, group_id: Int? = nil) {
        self.id = id
        self.tag_id = tag_id
        self.order = order
        self.group = group
        self.tag = tag
        self.group_id = group_id
    }
}
