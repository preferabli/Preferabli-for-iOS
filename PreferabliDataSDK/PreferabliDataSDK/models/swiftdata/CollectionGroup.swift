// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// Products in a Collection are organized into one or more groups.  A CollectionGroup object sits within a ``CollectionVersion``.  Each CollectionGroup has an ``order`` representing its display order within a Collection.  Products that are tagged as belonging to a Collection are ordered within the applicable CollectionGroup with ``orderings``.
@Model
public final class CollectionGroup: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date?
    public var updated_at: Date?
    public var name: String?
    public var order: Int?
    public var orderings_count: Int?
    @Relationship(deleteRule: .nullify) public var orderings: [CollectionOrder] = []
    @Relationship(deleteRule: .nullify) public var version: CollectionVersion?
    
    public init(id: Int) { self.id = id }

    public init(id: Int, name: String? = nil, order: Int? = nil, orderings_count: Int? = nil, orderings: [CollectionOrder] = [], version: CollectionVersion? = nil) {
        self.id = id
        self.name = name
        self.order = order
        self.orderings_count = orderings_count
        self.orderings = orderings
        self.version = version
    }

    /// Sort groups by their order.
    /// - Parameter groups: an array of groups to be sorted.
    /// - Returns: a sorted array of groups.
    static public func sortGroups(groups: [CollectionGroup]) -> [CollectionGroup] {
        return groups.sorted {
            ($0.order ?? Int.max) < ($1.order ?? Int.max)
        }
    }
}
