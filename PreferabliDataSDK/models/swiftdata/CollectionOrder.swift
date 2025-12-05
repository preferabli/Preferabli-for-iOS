// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// The link between a ``Tag`` (which in turn references a ``Product``) and a ``Collection``, including its ordering within the Collection.
@Model
public final class CollectionOrder: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    public var tag_id: Int
    public var order: Int
    
    // relationships
    @Relationship(deleteRule: .nullify) public var group: CollectionGroup
    @Relationship(deleteRule: .nullify, inverse: \Tag.orderings) public var tag: Tag
    
    public init(id: Int, tag_id: Int, order : Int, group : CollectionGroup, tag : Tag) {
        self.id = id
        self.tag_id = tag_id
        self.order = order
        self.group = group
        self.tag = tag
    }

    public static func predicate(forID id: Int) -> Predicate<CollectionOrder> {
        #Predicate<CollectionOrder> { $0.id == id }
    }
}
