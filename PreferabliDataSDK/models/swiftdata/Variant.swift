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
public final class Variant: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date?
    public var updated_at: Date?
    // MARK: - Constants
    /// Used to represent the most recent variant of a product.
    public static let CURRENT_VARIANT_YEAR: Int = -1
    /// Used to represent a product that does not have variants.
    public static let NON_VARIANT: Int = 0
    
    // MARK: - Persisted properties (SwiftData)
    public var fresh: Bool?
    public var num_dollar_signs: Int?
    public var price: Decimal?
    public var recommendable: Bool?
    public var year: Int?
    
    @Relationship(deleteRule: .nullify) public var primary_image: Media?
    @Relationship(deleteRule: .nullify) public var product: Product?
    @Relationship(deleteRule: .nullify) public var tags: [Tag] = []
    
    // MARK: - Transient / computed
    /// Transient, computed values preserved from legacy object.
    @Transient internal var preference_data: PreferenceData?
    /// Transient: Merchant mappings for integrations (WTB, channel links, etc.).
    @Transient public var merchant_links: [MerchantProductLink]?
    
    // MARK: - Initializers
    public init(id: Int) { self.id = id }
    
    public init(
        created_at: Date? = nil,
        fresh: Bool? = nil,
        id: Int,
        num_dollar_signs: Int? = nil,
        price: Decimal? = nil,
        recommendable: Bool? = nil,
        updated_at: Date? = nil,
        year: Int? = nil,
        primary_image: Media? = nil,
        product: Product? = nil,
        tags: [Tag] = []
    ) {
        self.created_at = created_at
        self.fresh = fresh
        self.id = id
        self.num_dollar_signs = num_dollar_signs
        self.price = price
        self.recommendable = recommendable
        self.updated_at = updated_at
        self.year = year
        self.primary_image = primary_image
        self.product = product
        self.tags = tags
        self.preference_data = nil
        self.merchant_links = nil
    }
    
    /// Convenience initializer used by Product helpers when auto-creating the "most recent" variant.
    public convenience init(year: Int, product: Product) {
        self.init(
            created_at: Date(),
            fresh: false,
            id: Int.random(in: 1...Int.max),
            num_dollar_signs: 0,
            price: 0.0,
            recommendable: false,
            updated_at: Date(),
            year: year,
            primary_image: nil,
            product: product,
            tags: []
        )
    }
    
    // MARK: - Legacy helpers (ported)
    
    public func getYear() -> Int {
        return year ?? Variant.CURRENT_VARIANT_YEAR
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
    var rating_level: RatingLevel {
        if let mr = most_recent_rating {
            // Bridge to NSNumber if needed by the helper
            return RatingLevel.getRatingLevelBasedOffTagValue(value:  mr.value)
        }
        return .NONE
    }
    
    var cellar_tags: Set<Tag> {
        var collectionTags = Set<Tag>()
        for tag in tags {
            if tag.tag_type == .CELLAR {
                collectionTags.insert(tag)
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
        return Product.getPrice(num_dollar_signs: num_dollar_signs ?? 0)
    }
    
    /// All the variant's tags of type ``TagType/PURCHASE`` for the current user.
    var purchase_tags: Set<Tag> {
        var purchaseTags = Set<Tag>()
        for tag in tags {
            if tag.tag_type == .PURCHASE {
                purchaseTags.insert(tag)
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
    public func getImage(width: Float, height: Float, quality: Int = 80) -> URL? {
        if primary_image == nil || primary_image!.path.isEmptyOrWhitespace ||
            (primary_image?.path?.contains("placeholder") ?? false) {
            
            if product?.primaryImage == nil || product!.primaryImage!.path.isEmptyOrWhitespace ||
                (product?.primaryImage?.path?.contains("placeholder") ?? false) {
                return nil
            }
            return product?.getImage(width: width, height: height, quality: quality)
        }
        return PreferabliTools.getImageUrl(image: primary_image?.path, width: width, height: height, quality: quality)
    }
    
    /// All of the variant tags of type ``TagType/RATING`` for the current user.
    var ratings_tags: Set<Tag> {
        var ratingsTags = Set<Tag>()
        for tag in tags {
            if tag.tag_type == .RATING {
                ratingsTags.insert(tag)
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

// MARK: - API action passthroughs (unchanged semantics)
extension Variant {
//    /// See ``Preferabli/whereToBuy(product_id:fulfill_sort:append_nonconforming_results:lock_to_integration:onCompletion:onFailure:)``.
//    public func whereToBuy(
//        fulfill_sort: FulfillSort = FulfillSort.init(),
//        append_nonconforming_results: Bool = true,
//        lock_to_integration: Bool = true,
//        onCompletion: @escaping (WhereToBuy) -> () = {_ in },
//        onFailure: @escaping (PreferabliException) -> () = {_ in }
//    ) {
//        if (product != nil) {
//            var fs = fulfill_sort
//            fs.variant_year = year ?? Variant.CURRENT_VARIANT_YEAR
//            Preferabli.main.whereToBuy(
//                product_id: product!.id,
//                fulfill_sort: fs,
//                append_nonconforming_results: append_nonconforming_results,
//                lock_to_integration: lock_to_integration,
//                onCompletion: onCompletion,
//                onFailure: onFailure
//            )
//        } else {
//            onFailure(PreferabliException.init(type: .BadSwiftData, message: "No product associated with variant."))
//        }
//    }
    
    /// See ``Preferabli/wishlistProduct(product_id:year:location:notes:price:quantity:format_ml:onCompletion:onFailure:)``.
//    public func toggleWishlist(
//        onCompletion: @escaping (Product) -> () = {_ in },
//        onFailure: @escaping (PreferabliException) -> () = {_ in }
//    ) {
//        if let w = wishlist_tag {
//            Preferabli.main.deleteTag(tag_id: w.id, onCompletion: onCompletion, onFailure: onFailure)
//        } else {
//            if (product != nil) {
//                Preferabli.main.wishlistProduct(
//                    product_id: product!.id,
//                    year: getYear(),
//                    onCompletion: onCompletion,
//                    onFailure: onFailure
//                )
//            } else {
//                onFailure(PreferabliException.init(type: .BadSwiftData, message: "No product associated with variant."))
//            }
//        }
//    }
//    
//    /// See ``Preferabli/rateProduct(product_id:year:rating:location:notes:price:quantity:format_ml:onCompletion:onFailure:)``.
//    public func rate(
//        rating: RatingLevel,
//        location: String? = nil,
//        notes: String? = nil,
//        price: Decimal? = nil,
//        quantity: Int? = nil,
//        format_ml: Int? = nil,
//        onCompletion: @escaping (Product) -> () = {_ in },
//        onFailure: @escaping (PreferabliException) -> () = {_ in }
//    ) {
//        if (product != nil) {
//            Preferabli.main.rateProduct(
//                product_id: product!.id,
//                year: getYear(),
//                rating: rating,
//                location: location,
//                notes: notes,
//                price: price,
//                quantity: quantity,
//                format_ml: format_ml,
//                onCompletion: onCompletion,
//                onFailure: onFailure
//            )
//        } else {
//            onFailure(PreferabliException.init(type: .BadSwiftData, message: "No product associated with variant."))
//        }
//    }
    
    /// See ``Preferabli/lttt(product_id:year:collection_id:include_merchant_links:onCompletion:onFailure:)``.
//    public func lttt(
//        collection_id: Int = Preferabli.PRIMARY_INVENTORY_ID,
//        onCompletion: @escaping ([Int]) -> () = {_ in },
//        onFailure: @escaping (PreferabliException) -> () = {_ in }
//    ) {
//        if (product != nil) {
//            Preferabli.main.lttt(
//                product_id: product!.id,
//                year: getYear(),
//                collection_id: collection_id,
//                onCompletion: onCompletion,
//                onFailure: onFailure
//            )
//        } else {
//            onFailure(PreferabliException.init(type: .BadSwiftData, message: "No product associated with variant."))
//        }
//    }
    
//    /// See ``Preferabli/getPreferabliScore(product_id:year:onCompletion:onFailure:)``.
//    public func getPreferabliScore(
//        force_refresh: Bool = false,
//        onCompletion: @escaping (PreferenceData) -> ()  = {_ in },
//        onFailure: @escaping (PreferabliException) -> () = {_ in }
//    ) {
//        if preference_data == nil || force_refresh {
//            if (product != nil) {
//                Preferabli.main.getPreferabliScore(
//                    product_id: product!.id,
//                    year: getYear(),
//                    onCompletion: { pd in
//                        self.preference_data = pd
//                        onCompletion(pd)
//                    },
//                    onFailure: onFailure
//                )
//            } else {
//                onFailure(PreferabliException.init(type: .BadSwiftData, message: "No product associated with variant."))
//            }
//        } else {
//            onCompletion(preference_data!)
//        }
//    }
}
