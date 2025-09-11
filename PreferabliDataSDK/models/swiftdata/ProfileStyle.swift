// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

@Model
public final class ProfileStyle: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date?
    public var updated_at: Date?
    public var conflict: Bool?
    public var order_profile: Int?
    public var order_recommend: Int?
    public var rating: Int?
    public var strength: Int?
    public var style_id: Int?
    public var recommend: Bool?
    public var refine: Bool?
    public var keywords: String?
    
    @Relationship(deleteRule: .nullify) public var style: Style?
    @Relationship(deleteRule: .nullify) public var profile: Profile?

    public init(id: Int) { self.id = id }

    init(conflict: Bool? = nil, id: Int, order_profile: Int? = nil, order_recommend: Int? = nil, rating: Int? = nil, strength: Int? = nil, style_id: Int? = nil, recommend: Bool? = nil, refine: Bool? = nil, keywords: String? = nil, created_at: Date? = nil, updated_at: Date? = nil, style: Style? = nil, profile: Profile? = nil) {
        self.conflict = conflict
        self.id = id
        self.order_profile = order_profile
        self.order_recommend = order_recommend
        self.rating = rating
        self.strength = strength
        self.style_id = style_id
        self.recommend = recommend
        self.refine = refine
        self.keywords = keywords
        self.created_at = created_at
        self.updated_at = updated_at
        self.style = style
        self.profile = profile
    }
}
