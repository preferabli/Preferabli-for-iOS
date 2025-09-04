// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// A trait descriptor for a ``Collection``.
@Model
public final class CollectionTrait: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date?
    public var updated_at: Date?
    public var name: String?
    public var order: Int?
    public var restrict_to_ring_it: Bool?
    @Relationship(deleteRule: .nullify) public var collection: Collection?

    public init(id: Int) { self.id = id }

    public init(id: Int, name: String? = nil, order: Int? = nil, restrict_to_ring_it: Bool? = nil, collection: Collection? = nil) {
        self.id = id
        self.name = name
        self.order = order
        self.restrict_to_ring_it = restrict_to_ring_it
        self.collection = collection
    }
}
