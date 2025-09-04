//
//  Product.swift (SwiftData @Model merged with legacy helpers)
//  Preferabli
//
//  NOTE: This file merges the SwiftData model with the original helper
//  methods and documentation comments from the non-CoreData Product class.
//  Where legacy code used NSNumber, we use Swift Int where applicable.
//

import Foundation
import CoreGraphics
import SwiftData

/// Represents a product  (e.g., wines, beers, spirits) within the Preferabli SDK. A product may have one or more ``Variant``s stored as ``variants``.  A variant can have one or more ``Tag``s which are used to associate a product with a user's interaction (e.g., rating) or with a particular ``Collection``.
///
/// With respect to a ``Customer``, a product return may also include ``PreferenceData`` which identifies the customer's affinity for the product. See ``getPreferabliScore(force_refresh:onCompletion:onFailure:)``.
///
/// To see how a product is mapped to your own object(s), see ``Variant/merchant_links``. To see a user's interaction with the product, see ``Variant/tags``.
@Model
public final class Product: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date?
    public var updated_at: Date?
    public var brand: String?
    public var decant: Bool?
    public var grape: String?
    public var brand_lat: Int?
    public var brand_lon: Int?
    public var show_year_dropdown: Bool?
    public var name: String?
    public var region: String?
    public var type: String?
    public var category: String?
    public var subcategory: String?
    public var brand_id: Int?
    public var producthash: String?

    @Relationship(deleteRule: .nullify) public var primaryImage: Media?
    @Relationship(deleteRule: .nullify) public var variants: [Variant] = []

    public init(id: Int) { self.id = id }

    /// The ``RatingLevel`` of the most recent rating of a specific product for the current user.
    var rating_level : RatingLevel {
        if let mostRecentRating = most_recent_rating {
            return RatingLevel.getRatingLevelBasedOffTagValue(value: mostRecentRating.value)
        }
        return RatingLevel.NONE
    }

    /// The first instance within the product of tag type ``TagType/WISHLIST`` for the current user.
    var wishlist_tag : Tag? {
        for variant in variants {
            for tag in variant.tags {
                if (tag.tag_type == .WISHLIST) {
                    return tag
                }
            }
        }
        return nil
    }

    /// All of the product tags of type ``TagType/PURCHASE`` for the current user.
    var purchase_tags: Set<Tag> {
        var purchaseTags = Set<Tag>()
        for variant in variants {
            for tag in variant.tags {
                if (tag.tag_type == .PURCHASE) {
                    purchaseTags.insert(tag)
                }
            }
        }
        return purchaseTags
    }

    /// All of the product tags of type ``TagType/CELLAR`` for the current user.
    ///
    /// > Note: In legacy code this referenced `CoreData_UserCollection` to filter by `relationship_type == "mycellar"`.
    /// SwiftData equivalent should query user collections in a `ModelContext` and then filter tags by those collection ids.
    /// See `cellar_tags(in:)` below for a context-aware variant.
    var cellar_tags: Set<Tag> {
        var cellarTags = Set<Tag>()
        for variant in variants {
            for tag in variant.tags {
                if (tag.tag_type == .CELLAR) {
                    cellarTags.insert(tag)
                }
            }
        }
        return cellarTags
    }

    /// Context-aware variant that matches legacy "mycellar" behavior.
    /// - Parameter ctx: SwiftData context to query the user's collections.
    /// - Returns: Tags of type ``TagType/CELLAR`` that belong to collections whose `relationship_type` is `mycellar`.
    func cellar_tags(in ctx: ModelContext) throws -> Set<Tag> {
        // Fetch user collections with relationship_type == "mycellar"
        let myCellar = try ctx.fetch(FetchDescriptor<UserCollection>(
            predicate: #Predicate { $0.relationship_type == "mycellar" }
        ))
        let ids = Set(myCellar.map { $0.collection_id })
        var result = Set<Tag>()
        for v in variants {
            for t in v.tags {
                if t.tag_type == .CELLAR, let cid = t.collection_id, ids.contains(cid) {
                    result.insert(t)
                }
            }
        }
        return result
    }

    /// The most recent product tags of type ``TagType/PURCHASE`` for the current user.
    var most_recent_purchase: Tag? {
        var date = Date(timeIntervalSince1970: 0)
        var mostRecentPurchase : Tag?
        for tag in purchase_tags {
            let compareToDate = tag.created_at ?? Date(timeIntervalSince1970: 0)
            if (date < compareToDate) {
                date = compareToDate
                mostRecentPurchase = tag
            }
        }
        return mostRecentPurchase
    }

    /// Identifies if the current user has purchased a specific product.
    /// - Returns: true if it was purchased.
    public func wasPurchased() -> Bool {
        return purchase_tags.count != 0
    }

    /// Identifies if the current user has added a specific product to their wishlist.
    /// - Returns: true if it was wishlisted.
    public func isOnWishlist() -> Bool {
        return wishlist_tag != nil
    }

    /// Identifies if the current user added a specific product to a cellar collection.
    /// - Returns: true if the product is in the user's cellar.
    public func isInCellar() -> Bool {
        return cellar_tags.count != 0
    }

    /// All of the product tags of type ``TagType/RATING`` for the current user.
    var ratings_tags: Set<Tag> {
        var ratingsTags = Set<Tag>()
        for variant in variants {
            for tag in variant.tags where tag.tag_type == .RATING {
                ratingsTags.insert(tag)
            }
        }
        return ratingsTags
    }

    /// The most recent product tags of type ``TagType/RATING`` for the current user.
    var most_recent_rating: Tag? {
        var date = Date(timeIntervalSince1970: 0)
        var mostRecentRating : Tag?
        for tag in ratings_tags {
            let compareToDate = tag.created_at ?? Date(timeIntervalSince1970: 0)
            if (date < compareToDate) {
                date = compareToDate
                mostRecentRating = tag
            }
        }
        return mostRecentRating
    }

    /// Identifies if a product is still being curated.
    /// - Returns: true if the product has not been curated.
    public func isBeingIdentified() -> Bool {
        return brand?.lowercased().contains("identified") ?? true
    }

    /// Get the product's image.
    /// - Parameters:
    ///   - width: returns an image with the specified width in pixels.
    ///   - height: returns an image with the specified height in pixels.
    ///   - quality: returns an image with the specified quality. Scales from 0 - 100.
    /// - Returns: the URL of the requested image.
    public func getImage(width : CGFloat, height : CGFloat, quality : Int = 80) -> URL? {
        if (primaryImage == nil || PreferabliTools.isNullOrWhitespace(string: primaryImage?.path) || primaryImage?.path?.contains("placeholder") == true) {
            for variant in variants {
                if (variant.primary_image == nil || PreferabliTools.isNullOrWhitespace(string: variant.primary_image?.path) || variant.primary_image?.path?.contains("placeholder") == true) {
                    continue
                }
                return variant.getImage(width: width, height: height, quality: quality)
            }
        }
        return PreferabliTools.getImageUrl(image: primaryImage?.path, width: width, height: height, quality: quality)
    }

    /// The type of a product (e.g., Red). Only for wines.
    var product_type: ProductType {
        return ProductType.getProductTypeFromString(value: type)
    }

    /// The category of a product.
    var product_category: ProductCategory {
        return ProductCategory.getProductCategoryFromString(value: category)
    }

    /// Gets the price range of the most recent ``Variant``.
    /// - Returns: price range represented by dollar signs in a string.
    ///
    /// Prices represent Retail | Restaurant
    /// - $ = Less than $12 | < $30
    /// - $$ = $12 to $19.99 | $30 - $45
    /// - $$$ = $20 to $49.99 | $45 - $110
    /// - $$$$ = $50 to $74.99 | $110 - $160
    /// - $$$$$ = $75 and up | > $160
    public func getPrice() -> String {
        return Product.getPrice(num_dollar_signs: most_recent_variant.num_dollar_signs ?? 1)
    }

    static internal func getPrice(num_dollar_signs : Int) -> String {
        var dollarSigns = ""
        for _ in 0..<num_dollar_signs {
            dollarSigns += "$"
        }
        return dollarSigns
    }

    /// The most recent ``Variant`` for a product.
    public var most_recent_variant: Variant {
        var mostRecentYear : Int? = -2
        var mostRecentVariant : Variant?
        for variant in variants {
            if (((variant.year ?? 0) > (mostRecentYear ?? 0)) && variant.id > 0) {
                mostRecentYear = variant.year
                mostRecentVariant = variant
            }
        }

        if (mostRecentVariant == nil) {
            // We should always have a variant. Create one if it doesn't exist.
            mostRecentVariant = Variant(year: Variant.CURRENT_VARIANT_YEAR, product: self)
            variants.append(mostRecentVariant!)
        }

        return mostRecentVariant!
    }

    /// Gets a ``Variant`` of a product by its id.
    /// - Parameter id: a variant id.
    /// - Returns: the corresponding variant. Returns *nil* if this product does not contain the variant.
    public func getVariantWithId(id : Int) -> Variant? {
        for variant in variants {
            if (variant.id == id) {
                return variant
            }
        }
        return nil
    }

    /// Get a ``Variant`` of a product by its year.
    /// - Parameter year: a variant year.
    /// - Returns: the corresponding variant. Returns *nil* if this product does not contain the variant.
    public func getVariantWithYear(year : Int) -> Variant? {
        for variant in variants {
            if (variant.year == year) {
                return variant
            }
        }
        return nil
    }

    /// Filters products by a user's search.
    /// - Parameters:
    ///   - products: an array of products to be filtered.
    ///   - search_text: user's search query.
    /// - Returns: an array of filtered products.
    static public func filterProducts(products : [Product], search_text : String) -> [Product] {
        var filteredWines = [Product]()
        if (search_text.isEmptyOrWhitespace()) {
            filteredWines = products
        } else {
            let searchTerms = search_text.components(separatedBy: " ")
            filteredWines = products.filter {
                for searchTerm in searchTerms {
                    if ($0.filterProduct(search_term: searchTerm)) {
                        continue
                    } else {
                        return false
                    }
                }
                return true
            }
        }
        return filteredWines
    }

    internal func filterProduct(search_term : String) -> Bool {
        if (search_term.isEmptyOrWhitespace()) {
            return true
        } else if (name?.containsIgnoreCase(search_term) ?? false) {
            return true
        } else if (grape?.containsIgnoreCase(search_term) ?? false) {
            return true
        } else if (region?.containsIgnoreCase(search_term) ?? false) {
            return true
        } else if (brand?.containsIgnoreCase(search_term) ?? false) {
            return true
        } else if (type?.containsIgnoreCase(search_term) ?? false) {
            return true
        } else {
            for tag in ratings_tags {
                if (tag.comment?.containsIgnoreCase(search_term) ?? false) {
                    return true
                } else if (tag.location?.containsIgnoreCase(search_term) ?? false) {
                    return true
                }
            }
        }
        return false
    }
}

// MARK: - API action passthroughs (unchanged semantics)
extension Product {
//    /// See ``Preferabli/whereToBuy(product_id:fulfill_sort:append_nonconforming_results:lock_to_integration:onCompletion:onFailure:)``.
//    public func whereToBuy(fulfill_sort : FulfillSort = FulfillSort.init(), append_nonconforming_results : Bool = true, lock_to_integration : Bool = true,  onCompletion: @escaping (WhereToBuy) -> () = {_ in }, onFailure: @escaping (PreferabliException) -> () = {_ in }) {
//        most_recent_variant.whereToBuy(fulfill_sort: fulfill_sort, append_nonconforming_results: append_nonconforming_results, lock_to_integration: lock_to_integration, onCompletion: onCompletion, onFailure: onFailure)
//    }
//
//    /// See ``Preferabli/wishlistProduct(product_id:year:location:notes:price:quantity:format_ml:onCompletion:onFailure:)``.
//    public func toggleWishlist(onCompletion : @escaping (Product) -> ()  = {_ in }, onFailure : @escaping (PreferabliException) -> () = {_ in }) {
//        let tag = wishlist_tag
//        var variant = most_recent_variant
//        if (tag?.variant != nil) {
//            variant = tag!.variant!
//        }
//        variant.toggleWishlist(onCompletion: onCompletion, onFailure: onFailure)
//    }
//
//    /// See ``Preferabli/rateProduct(product_id:year:rating:location:notes:price:quantity:format_ml:onCompletion:onFailure:)``.
//    public func rate(rating : RatingLevel, location : String? = nil, notes : String? = nil, price : Decimal? = nil, quantity : Int? = nil, format_ml : Int? = nil, onCompletion : @escaping (Product) -> () = {_ in }, onFailure : @escaping (PreferabliException) -> () = {_ in }) {
//        most_recent_variant.rate(rating: rating, location: location, notes: notes, price: price, quantity: quantity, format_ml: format_ml, onCompletion: onCompletion, onFailure: onFailure)
//    }
//
//    /// See ``Preferabli/lttt(product_id:year:collection_id:include_merchant_links:onCompletion:onFailure:)``.
//    public func lttt(collection_id : Int = Preferabli.PRIMARY_INVENTORY_ID, onCompletion: @escaping ([Int]) -> () = {_ in }, onFailure: @escaping (PreferabliException) -> () = {_ in }) {
//        most_recent_variant.lttt(collection_id: collection_id, onCompletion: onCompletion, onFailure: onFailure)
//    }
//
//    /// See ``Preferabli/getPreferabliScore(product_id:year:onCompletion:onFailure:)``.
//    public func getPreferabliScore(force_refresh : Bool = false, onCompletion : @escaping (PreferenceData) -> ()  = {_ in }, onFailure : @escaping (PreferabliException) -> () = {_ in }) {
//        most_recent_variant.getPreferabliScore(force_refresh: force_refresh, onCompletion: onCompletion, onFailure: onFailure)
//    }
}

/// The category of a ``Product``.
public enum ProductCategory {
    case WHISKEY
    case MEZCAL
    case BEER
    case WINE
    case NONE

    internal func getCategoryName() -> String {
        switch self {
        case .WHISKEY:
            return "whiskey"
        case .MEZCAL:
            return "tequila"
        case .BEER:
            return "beer"
        case .WINE:
            return "wine"
        case .NONE:
            return ""
        }
    }

    static internal func getProductCategoryFromString(value : String?) -> ProductCategory {
        if let value {
            switch value.lowercased() {
            case "whiskey":
                return .WHISKEY
            case "tequila":
                return .MEZCAL
            case "beer":
                return .BEER
            case "wine":
                return .WINE
            default:
                return .NONE
            }
        }
        return .NONE
    }
}

/// The recognized type of a ``Product``.  At this time, non-wine products use the type ``ProductType/OTHER``.
public enum ProductType {
    case RED
    case WHITE
    case ROSE
    case SPARKLING
    case FORTIFIED
    /// Use other if product is not a wine (e.g., a whiskey, mezcal/tequila, or beer).
    case OTHER

    internal func getTypeName() -> String {
        switch self {
        case .RED:
            return "red"
        case .WHITE:
            return "white"
        case .ROSE:
            return "rosé"
        case .SPARKLING:
            return "sparkling"
        case .FORTIFIED:
            return "fortified"
        case .OTHER:
            return "other"
        }
    }

    static internal func getProductTypeFromString(value : String?) -> ProductType {
        if let value {
            switch value.lowercased() {
            case "red":
                return .RED
            case "white":
                return .WHITE
            case "rosé":
                return .ROSE
            case "fortified":
                return .FORTIFIED
            case "sparkling":
                return .SPARKLING
            default:
                return .OTHER
            }
        }
        return .OTHER
    }

    /// Is a specific product a wine?
    /// - Returns: true if the product type corresponds to a wine.
    public func isWine() -> Bool {
        return self == .RED || self == .WHITE || self == .ROSE || self == .SPARKLING || self == .FORTIFIED
    }
}
