//
//  Variant.swift (SwiftData @Model merged with legacy helpers)
//  Preferabli
//
//  NOTE: This file merges the SwiftData model with the original helper
//  methods and documentation comments from the non-CoreData Variant class.
//  SwiftData types are used for persistence; legacy API-facing helpers are preserved.
//
//  Key differences from legacy:
//  - `year` and `num_dollar_signs` are `Int` (not NSNumber).
//  - Constants `CURRENT_VARIANT_YEAR` / `NON_VARIANT` are `Int`.
//  - Transient fields `preference_data` and `merchant_links` are marked with `@Transient`.
//  - API calls that require NSNumber bridge via `NSNumber(value:)`.
//

import Foundation
import CoreGraphics
import SwiftData

/// A Variant is a particular representation of a ``Product``.  For example, a specific vintage of a particular wine.
@Model
public final class Variant: HasIntID, HasTimestamps, HasTombstone {
    
    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    // MARK: - Constants
    /// Used to represent the most recent variant of a product.
    public static let CURRENT_VARIANT_YEAR: Int = -1
    /// Used to represent a product that does not have variants.
    public static let NON_VARIANT: Int = 0
    
    // MARK: - Persisted properties (SwiftData)
    public var num_dollar_signs: Int?
    public var price: Decimal?
    public var recommendable: Bool?
    public var year: Int
    
    // relationships
    @Relationship(deleteRule: .nullify) public var primary_image: Media?
    @Relationship(inverse: \Product.variants) public var product: Product
    @Relationship(deleteRule: .cascade, inverse: \Tag.variant) public var tags: [Tag] = []
    
    // local only
    public var isTombstoned: Bool = false
    
    // MARK: - Transient / computed
    /// Transient: Merchant mappings for integrations (WTB, channel links, etc.).
    @Transient public var merchant_links: [MerchantProductLink]?
    
    // MARK: - Initializers
    public init(id: Int, year: Int, product: Product) {
        self.id = id
        self.year = year
        self.product = product
    }
    
    public static func predicate(forID id: Int) -> Predicate<Variant> {
        #Predicate<Variant> { $0.id == id }
    }
    
    var most_recent_rating: Tag? {
        var date = Date(timeIntervalSince1970: 0)
        var mostRecentRating: Tag?
        for tag in ratings_tags {
            let compareToDate = tag.created_at ?? Date(timeIntervalSince1970: 0)
            if (date < compareToDate) {
                date = compareToDate
                mostRecentRating = tag
            }
        }
        return mostRecentRating
    }
    
    /// The ``RatingLevel`` of the most recent rating of a specific variant for the current user.
    var rating_level: RatingLevel? {
        if let mr = most_recent_rating {
            // Bridge to NSNumber if needed by the helper
            return RatingLevel.getRatingLevelBasedOffTagValue(value:  mr.value)
        }
        
        return nil
    }
    
    var cellar_tags: [Tag] {
        var collectionTags = [Tag]()
        for tag in tags {
            if tag.tag_type == .COLLECTION {
                collectionTags.append(tag)
            }
        }
        return collectionTags
    }
    
    /// Gets the general price range of a specific variant.
    /// - Returns: Price range represented by dollar signs in a string.
    ///
    /// Prices represent Retail | Restaurant
    /// - $ = Less than $12 | < $30
    /// - $$ = $12 to $19.99 | $30 - $45
    /// - $$$ = $20 to $49.99 | $45 - $110
    /// - $$$$ = $50 to $74.99 | $110 - $160
    /// - $$$$$ = $75 and up | > $160
    public func getPrice() -> String {
        return PriceTier.init(rawValue: num_dollar_signs ?? 0)?.label ?? ""
    }
    
    /// All the variant's tags of type ``TagType/PURCHASE`` for the current user.
    var purchase_tags: [Tag] {
        var purchaseTags = [Tag]()
        for tag in tags {
            if tag.tag_type == .PURCHASE {
                purchaseTags.append(tag)
            }
        }
        return purchaseTags
    }
    
    /// Get the variant image.
    /// - Parameters:
    ///   - width: returns an image with the specified width in pixels.
    ///   - height: returns an image with the specified height in pixels.
    ///   - quality: returns an image with the specified quality. Scales from 0 - 100.
    /// - Returns: the URL of the requested image.
    public func getImage(width: Int, height: Int, quality: Int = 80) -> URL? {
        if primary_image == nil || primary_image!.path.isEmptyOrWhitespace ||
            (primary_image?.path?.contains("placeholder") ?? false) {
            
            if product.primary_image == nil || product.primary_image!.path.isEmptyOrWhitespace ||
                (product.primary_image?.path?.contains("placeholder") ?? false) {
                return nil
            }
            return product.getImage(width: width, height: height, quality: quality)
        }
        return PreferabliTools.getImageUrl(media: primary_image, width: width, height: height, quality: quality)
    }
    
    /// All of the variant tags of type ``TagType/RATING`` for the current user.
    var ratings_tags: [Tag] {
        var ratingsTags = [Tag]()
        for tag in tags {
            if tag.tag_type == .RATING {
                ratingsTags.append(tag)
            }
        }
        return ratingsTags
    }
    
    /// Get a ``Tag`` by its id.
    /// - Parameter id: id of the ``Tag``.
    /// - Returns: the tag in question or *nil* if it does not exist in this variant.
    public func getTagWithId(id: Int) -> Tag? {
        return tags.first { $0.id == id }
    }
    /// Convenience overload for legacy NSNumber callers.
    public func getTagWithId(id: NSNumber) -> Tag? {
        return getTagWithId(id: id.intValue)
    }
    
    /// Identifies if the current user has added a specific variant to their wishlist.
    /// - Returns: true if it was wishlisted.
    public func isOnWishlist() -> Bool {
        return wishlist_tag != nil
    }
    
    /// The first instance for a variant of tag type ``TagType/WISHLIST`` for the current user.
    var wishlist_tag: Tag? {
        for tag in tags {
            if tag.tag_type == .WISHLIST {
                return tag
            }
        }
        return nil
    }
}

public enum PriceTier: Int, CaseIterable, Hashable, Identifiable, Sendable {
    case one = 1, two = 2, three = 3, four = 4, five = 5
    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .one:  return "$"
        case .two:  return "$$"
        case .three:return "$$$"
        case .four: return "$$$$"
        case .five: return "$$$$$"
        }
    }
}
