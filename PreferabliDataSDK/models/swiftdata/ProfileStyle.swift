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

extension ProfileStyle {

    /// Shared "Sort by Preference" logic.
    /// - Parameters:
    ///   - styles: list to sort
    ///   - topScoreByKind: map of analytics kind -> topScore (higher is better)
    public static func sortByPreference(
        _ styles: [ProfileStyle],
        topScoreByKind: [ProfileProductKind: CGFloat]
    ) -> [ProfileStyle] {

        // LOVE=4, LIKE=3, SOSO=2, DISLIKE=1; nil goes last
        func ratingRank(_ ps: ProfileStyle) -> Int {
            ps.getRatingType()?.getRank() ?? Int.min
        }

        // order_profile ascending; nil goes last
        func orderProfileKey(_ ps: ProfileStyle) -> Int {
            ps.order_profile ?? Int.max
        }

        // Treat nil as 0 per requirements ("order_recommend is not 0")
        func orderRecommendKey(_ ps: ProfileStyle) -> Int {
            ps.order_recommend ?? 0
        }

        // analytics kind topScore descending; nil kind goes last
        func kindTopScore(_ ps: ProfileStyle) -> CGFloat {
            guard let kind = ps.analyticsKind() else { return -CGFloat.greatestFiniteMagnitude }
            return topScoreByKind[kind] ?? 0
        }

        func nameKey(_ ps: ProfileStyle) -> String {
            ps.style?.name ?? ""
        }

        func alphaLess(_ a: ProfileStyle, _ b: ProfileStyle) -> Bool {
            nameKey(a).localizedCaseInsensitiveCompare(nameKey(b)) == .orderedAscending
        }

        func isAppealing(_ ps: ProfileStyle) -> Bool { ps.isAppealing() }
        func isUnappealing(_ ps: ProfileStyle) -> Bool { ps.isUnappealing() }

        return styles.sorted { lhs, rhs in
            let la = isAppealing(lhs)
            let ra = isAppealing(rhs)

            // 0) All appealing styles first
            if la != ra { return la && !ra }

            // ---------
            // Appealing bucket
            // ---------
            if la && ra {
                let loRec = orderRecommendKey(lhs)
                let roRec = orderRecommendKey(rhs)

                let lHasRec = loRec != 0
                let rHasRec = roRec != 0

                // Appealing + order_recommend != 0 should come before appealing + order_recommend == 0
                if lHasRec != rHasRec { return lHasRec && !rHasRec }

                if lHasRec && rHasRec {
                    // 1) sort by order_recommend primarily
                    if loRec != roRec { return loRec < roRec }

                    // 2) tie-break: kind topScore (higher first)
                    let lTop = kindTopScore(lhs)
                    let rTop = kindTopScore(rhs)
                    if lTop != rTop { return lTop > rTop }

                    // 3) stable tie-break: alpha
                    return alphaLess(lhs, rhs)
                } else {
                    // order_recommend == 0 => sort by order_profile
                    let lo = orderProfileKey(lhs)
                    let ro = orderProfileKey(rhs)
                    if lo != ro { return lo < ro }

                    // tie: alpha
                    return alphaLess(lhs, rhs)
                }
            }

            // ---------
            // Unappealing bucket (and any "neither" / nil-rating cases)
            // ---------
            // If one is explicitly unappealing and the other is "unknown", keep unappealing ahead of unknown.
            // (Optional, but tends to behave better than random placement.)
            let lu = isUnappealing(lhs)
            let ru = isUnappealing(rhs)
            if lu != ru { return lu && !ru }

            // 1) rating rank first (SOSO before DISLIKE); unknown goes last
            let lr = ratingRank(lhs)
            let rr = ratingRank(rhs)
            if lr != rr { return lr > rr }

            // 2) next by kind topScore
            let lTop = kindTopScore(lhs)
            let rTop = kindTopScore(rhs)
            if lTop != rTop { return lTop > rTop }

            // 3) next by order_profile
            let lo = orderProfileKey(lhs)
            let ro = orderProfileKey(rhs)
            if lo != ro { return lo < ro }

            // 4) alpha
            return alphaLess(lhs, rhs)
        }
    }
}
