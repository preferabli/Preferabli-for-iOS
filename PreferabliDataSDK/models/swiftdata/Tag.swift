//
//  Tag.swift (SwiftData @Model merged with legacy helpers)
//  Preferabli
//
//  NOTE: This file merges the SwiftData model with the original helper
//  methods and documentation comments from the non-CoreData Tag class.
//  Persisted properties come from the SwiftData generator; helpers/comments
//  are preserved verbatim where possible.
//
//  Differences vs legacy:
//  - Persisted numeric fields use `Int` instead of `NSNumber`.
//  - API helpers that require `NSNumber` keep NSNumber parameters.
//

import Foundation
import SwiftData

/// Chronicles a user's interaction with a ``Product``. Is one of a type ``TagType``.
@Model
public final class Tag: HasIntID, HasTimestamps, HasTombstone {
    
    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    public var collection_id: Int
    public var comment: String?
    public var location: String?
    public var badge: String?
    public var tagged_in_collection_id: Int?
    public var tagged_in_channel_id: Int?
    public var tagged_in_channel_name: String?
    public var type: String?
    public var user_id: Int?
    public var value: String?
    public var bin: String?
    public var variant_id: Int
    public var product_id: Int
    public var quantity: Int?
    public var format_ml: Int?
    public var price: Decimal?
    public var customer_id: Int?
    
    // relationships
    @Relationship(deleteRule: .nullify) public var variant: Variant {
        didSet {
            updateSearchableContent()
        }
    }
    @Relationship(deleteRule: .cascade) public var orderings: [CollectionOrder] = []
    
    // local only
    public var isTombstoned: Bool = false
    public var searchableContent: String = ""
    
    // MARK: - Init (SwiftData)
    public init(id: Int, collection_id: Int, variant: Variant) {
        self.id = id
        self.collection_id = collection_id
        self.variant = variant
        self.variant_id = variant.id
        self.product_id = variant.product.id
        updateSearchableContent()
    }
    
    internal func updateSearchableContent() {
        let product = variant.product
        
        let name = product.name ?? ""
        let brand = product.brand ?? ""
        let grape = product.grape ?? ""
        let region = product.region ?? ""
        let category = product.category ?? ""
        let subcategory = product.subcategory ?? ""
        let type = product.type ?? ""
        let year = String(variant.year)

        self.searchableContent = "\(name) \(brand) \(grape) \(region) \(category) \(subcategory) \(type) \(year)".lowercased()
    }
    
    // Lets us know is the Tag is a Rating or not
    public func isRating() -> Bool {
        return tag_type == .RATING
    }
    
    // Lets us know is the Tag is a Wishlist or not
    public func isWishlist() -> Bool {
        return tag_type == .WISHLIST
    }
    
    public static func predicate(forID id: Int) -> Predicate<Tag> {
        #Predicate<Tag> { $0.id == id }
    }
    
    /// The type of the tag.
    public var tag_type : TagType? {
        return TagType.getTagTypeBasedOffDatabaseName(value: type)
    }
    
    /// The rating level of the tag. Only for tags of type ``TagType/RATING``.
    public var rating_level : RatingLevel? {
        return RatingLevel.getRatingLevelBasedOffTagValue(value: value)
    }
    
    /// Sort tags by date.
    /// - Parameter tags: an array of tags to be sorted.
    /// - Returns: a sorted array of tags.
    static public func sortTagsByDate(tags : [Tag], comparisonResult : ComparisonResult = .orderedDescending) -> [Tag] {
        return tags.sorted { $0.getCreatedAt().compare($1.getCreatedAt()) == comparisonResult }
    }
    
    /// Gets the formmated version of ``price``.
    /// - Parameter currency_code: code of the currency you would like to use for formatting.
    /// - Returns: a currency formatted price.
    public func getPrice(currency_code: String = (Locale.current.currencySymbol ?? "USD")) -> String {
        let formatter = NumberFormatter()
        formatter.locale = PreferabliTools.getLocaleForCurrencyCode(currencyCode: currency_code)
        formatter.numberStyle = .currency
        formatter.currencyCode = currency_code
        guard let price = price else { return "" }
        let number = NSDecimalNumber(decimal: price)
        return formatter.string(from: number) ?? ""
    }
    
    public func getFormat() -> ServingFormat {
        return ServingFormat.getServingFormatFromML(value: format_ml)
    }
    
    public func hasPrice() -> Bool {
        return price != nil && price != 0
    }
    
    public func hasFormat() -> Bool {
        return format_ml != nil && format_ml != 0
    }
}

/// The size of a ServingFormat as identified by a ``Tag``.
public enum ServingFormat : String, CaseIterable, Identifiable {
    
    public var id: String { rawValue }

    case GLASS
    case HALF_BOTTLE
    case BOTTLE
    case LARGE_FORMAT
    case NONE
    
    static public func getServingFormatFromML(value : Int?) -> ServingFormat {
        guard let value = value, value != 0 else {
            return .NONE
        }
        
        if (value < 350) {
            return .GLASS
        } else if (value >= 350 && value < 600) {
            return .HALF_BOTTLE
        } else if (value >= 600 && value < 1000) {
            return .BOTTLE
        } else {
            return .LARGE_FORMAT
        }
    }
    
    public func getFormatML() -> Int? {
        switch self {
        case .GLASS:       return 150
        case .HALF_BOTTLE:  return 375
        case .BOTTLE:      return 750
        case .LARGE_FORMAT: return 1500
        case .NONE:        return nil
        }
    }
}

/// The degree of appeal for a product as identified by a ``Tag``.
public enum RatingLevel {
    /// A user loved the product.
    case LOVE
    /// A user liked the product.
    case LIKE
    /// A user did not find the product to be appealing, but not as far as a dislike.  We like to say, "I'd drink it but only if I wasn't paying for it."
    case SOSO
    /// A user disliked the product.
    case DISLIKE
    
    static internal func getRatingLevelBasedOffTagValue(value : String?) -> RatingLevel? {
        if let value {
            switch value {
            case "1":
                return .DISLIKE
            case "2":
                return .SOSO
            case "3":
                return .LIKE
            case "4":
                return .LOVE
            default:
                return nil
            }
        }
        return nil
    }
    
    internal func getValue() -> String {
        switch self {
        case .LOVE:    return "4"
        case .LIKE:    return "3"
        case .SOSO:    return "2"
        case .DISLIKE: return "1"
        }
    }
    
    public func getRank() -> Int {
        switch self {
        case .LOVE:    return 4
        case .LIKE:    return 3
        case .SOSO:    return 2
        case .DISLIKE: return 1
        }
    }
    
    public func compare(_ other: RatingLevel) -> ComparisonResult {
        return self.getValue().caseInsensitiveCompare(other.getValue())
    }
}

/// Type of a ``Tag``. Tags may can contain different information depending on it's type.
public enum TagType: Sendable {
    case RATING
    case COLLECTION
    case PURCHASE
    case WISHLIST
    case SKIPPED
    
    static internal func getTagTypeBasedOffDatabaseName(value : String?) -> TagType? {
        if let value {
            switch value {
            case "rating":    return .RATING
            case "collection":return .COLLECTION
            case "purchase":  return .PURCHASE
            case "wishlist":  return .WISHLIST
            case "skipped":  return .SKIPPED
            default: return nil
            }
        }
        
        return nil
    }
    
    public func getDatabaseName() -> String {
        switch self {
        case .RATING:   return "rating"
        case .COLLECTION:   return "collection"
        case .PURCHASE: return "purchase"
        case .WISHLIST: return "wishlist"
        case .SKIPPED: return "skipped"
        }
    }
    
    public func compare(_ other: TagType) -> ComparisonResult {
        return self.getDatabaseName().caseInsensitiveCompare(other.getDatabaseName())
    }
}
