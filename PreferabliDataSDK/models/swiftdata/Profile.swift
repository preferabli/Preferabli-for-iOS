// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// A user's preference profile represents appealing and unappealing ``ProfileStyle``s for a particular user.
@Model
public final class Profile: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    public var user_id: Int?
    public var customer_id: Int?
    
    /// A score that represents how developed a profile is.
    internal var score: Int?
    internal var score_red: Int?
    internal var score_white: Int?
    internal var score_rose: Int?
    internal var score_sparkling: Int?
    internal var score_fortified: Int?
    internal var score_whiskey: Int?
    internal var score_tequila: Int?
    internal var score_vodka: Int?
    internal var score_gin: Int?
    internal var score_rum: Int?
    internal var score_sake: Int?
    internal var score_cocktail: Int?
    internal var score_beer: Int?
    internal var score_cheese: Int?
    
    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \ProfileStyle.profile) public var profile_styles: [ProfileStyle] = []
    public init(id: Int) { self.id = id }
    
    public static func predicate(forID id: Int) -> Predicate<Profile> {
        #Predicate<Profile> { $0.id == id }
    }
}
