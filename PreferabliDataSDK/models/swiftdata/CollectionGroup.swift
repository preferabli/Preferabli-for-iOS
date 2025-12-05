// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// Products in a Collection are organized into one or more groups.  A CollectionGroup object sits within a ``CollectionVersion``.  Each CollectionGroup has an ``order`` representing its display order within a Collection.  Products that are tagged as belonging to a Collection are ordered within the applicable CollectionGroup with ``orderings``.
@Model
public final class CollectionGroup: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    public var name: String?
    public var order: Int?
    public var orderings_count: Int?
    
    // relationships
    @Relationship(deleteRule: .cascade, inverse: \CollectionOrder.group) public var orderings: [CollectionOrder] = []
    @Relationship(deleteRule: .nullify) public var version: CollectionVersion
    
    public init(id: Int, version : CollectionVersion) {
        self.id = id
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
    
    public static func predicate(forID id: Int) -> Predicate<CollectionGroup> {
        #Predicate<CollectionGroup> { $0.id == id }
    }
}
