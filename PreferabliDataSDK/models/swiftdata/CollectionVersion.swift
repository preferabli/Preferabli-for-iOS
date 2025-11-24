// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// A version of a ``Collection``. For the most part, collections will only have one version.
@Model
public final class CollectionVersion: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    public var name: String?
    public var order: Int?
    @Relationship(deleteRule: .nullify) public var collection: Collection?
    @Relationship(deleteRule: .cascade, inverse: \CollectionGroup.version) public var groups: [CollectionGroup] = []

    public init(id: Int) { self.id = id }

    public init(id: Int, name: String? = nil, order: Int? = nil, collection: Collection? = nil, groups: [CollectionGroup] = []) {
        self.id = id
        self.name = name
        self.order = order
        self.collection = collection
        self.groups = groups
    }
    
    public static func predicate(forID id: Int) -> Predicate<CollectionVersion> {
        #Predicate<CollectionVersion> { $0.id == id }
    }
}
