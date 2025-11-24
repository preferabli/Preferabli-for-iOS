// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

@Model
public final class ProfileStyle: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    public var conflict: Bool?
    public var order_profile: Int?
    public var order_recommend: Int?
    public var rating: Int?
    public var strength: Int?
    public var style_id: Int?
    public var recommend: Bool?
    public var refine: Bool?
    public var keywords: String?
    
    @Relationship(deleteRule: .nullify, inverse: \Style.profile_styles) public var style: Style?
    @Relationship(deleteRule: .nullify) public var profile: Profile?

    public init(id: Int) { self.id = id }
    
    public static func predicate(forID id: Int) -> Predicate<ProfileStyle> {
        #Predicate<ProfileStyle> { $0.id == id }
    }
}
