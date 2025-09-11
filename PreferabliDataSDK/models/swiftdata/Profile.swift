// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// A user's preference profile represents appealing and unappealing ``ProfileStyle``s for a particular user.
@Model
public final class Profile: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date?
    public var updated_at: Date?
    public var user_id: Int?
    public var customer_id: Int?
    
    /// A score that represents how developed a profile is.
    internal var score: Int?
    
    // Relationships
    @Relationship(deleteRule: .nullify) public var profile_styles: [ProfileStyle] = []

    public init(id: Int) { self.id = id }

    init(id: Int, user_id: Int? = nil, customer_id: Int? = nil, score: Int? = nil, profile_styles: [ProfileStyle] = []) {
        self.id = id
        self.user_id = user_id
        self.customer_id = customer_id
        self.score = score
        self.profile_styles = profile_styles
    }
}
