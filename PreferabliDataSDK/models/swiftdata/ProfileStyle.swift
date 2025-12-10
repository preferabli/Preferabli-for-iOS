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
    public var style_id: Int
    public var recommend: Bool?
    public var refine: Bool?
    public var keywords: String?
    
    @Relationship(deleteRule: .nullify, inverse: \Style.profile_styles) public var style: Style?
    @Relationship(deleteRule: .nullify) public var profile: Profile?

    public init(id: Int, style_id : Int) {
        self.id = id
        self.style_id = style_id
    }
    
    public static func predicate(forID id: Int) -> Predicate<ProfileStyle> {
        #Predicate<ProfileStyle> { $0.id == id }
    }
    
    public func isUnappealing() -> Bool {
       return getRatingType() == RatingLevel.DISLIKE || getRatingType() == RatingLevel.SOSO
   }
   
    public func isAppealing() -> Bool {
       return getRatingType() == RatingLevel.LOVE || getRatingType() == RatingLevel.LIKE
   }
    
    public func getRatingType() -> RatingLevel? {
        guard let rating else { return nil }
        return RatingLevel.getRatingLevelBasedOffTagValue(value: String(rating))
    }
}

extension ProfileStyle {
    /// Derives the analytics "kind" for this preference style
    /// from its associated Style's product type or category.
    ///
    /// Returns nil if we can't confidently classify it.
    public func analyticsKind() -> ProfileProductKind? {
        guard let style = style else {
            return nil
        }

        // 1️⃣ Try wine type first (red/white/rose/sparkling/fortified)
        if let wineType = style.getProductType() {
            switch wineType {
            case .RED:       return .red
            case .WHITE:     return .white
            case .ROSE:      return .rose
            case .SPARKLING: return .sparkling
            case .FORTIFIED: return .fortified
            }
        }

        // 2️⃣ Fallback: use product category (spirits, beer, cheese, etc)
        if let cat = style.getProductCategory() {
            switch cat {
            case .WHISKEY: return .whiskey
            case .MEZCAL:  return .mezcal
            case .BEER:    return .beer        // includes RTD conceptually
            case .WINE:
                // If we got here and still don't have wineType, just treat as red.
                return .red
            case .CHEESE:  return .cheese
            case .VODKA:   return .vodka
            case .GIN:     return .gin
            case .RUM:     return .rum
            case .SAKE:    return .sake
            case .COCKTAIL:return .cocktail
            }
        }

        // 3️⃣ No mapping found
        return nil
    }
}
