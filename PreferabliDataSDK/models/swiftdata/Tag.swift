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
public final class Tag: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date?
    public var updated_at: Date?
    public var collection_id: Int?
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
    public var variant_id: Int?
    public var product_id: Int?
    public var quantity: Int?
    public var format_ml: Int?
    public var price: Decimal?
    public var customer_id: Int?

    @Relationship(deleteRule: .nullify) public var variant: Variant?
    @Relationship(deleteRule: .nullify) public var orderings: [CollectionOrder] = []

    // MARK: - Init (SwiftData)
    public init(id: Int) { self.id = id }

    public init(
        collection_id: Int? = nil,
        comment: String? = nil,
        created_at: Date? = nil,
        id: Int,
        location: String? = nil,
        badge: String? = nil,
        tagged_in_collection_id: Int? = nil,
        tagged_in_channel_id: Int? = nil,
        tagged_in_channel_name: String? = nil,
        type: String? = nil,
        updated_at: Date? = nil,
        user_id: Int? = nil,
        value: String? = nil,
        bin: String? = nil,
        variant_id: Int? = nil,
        product_id: Int? = nil,
        quantity: Int? = nil,
        format_ml: Int? = nil,
        price: Decimal? = nil,
        customer_id: Int? = nil,
        temp_image_id: Int? = nil,
        variant: Variant? = nil,
        orderings: [CollectionOrder] = []
    ) {
        self.collection_id = collection_id
        self.comment = comment
        self.created_at = created_at
        self.id = id
        self.location = location
        self.badge = badge
        self.tagged_in_collection_id = tagged_in_collection_id
        self.tagged_in_channel_id = tagged_in_channel_id
        self.tagged_in_channel_name = tagged_in_channel_name
        self.type = type
        self.updated_at = updated_at
        self.user_id = user_id
        self.value = value
        self.bin = bin
        self.variant_id = variant_id
        self.product_id = product_id
        self.quantity = quantity
        self.format_ml = format_ml
        self.price = price
        self.customer_id = customer_id
        self.variant = variant
        self.orderings = orderings
    }
    
    // Lets us know is the Tag is a Rating or not
    public func isRating() -> Bool {
        return tag_type == .RATING
    }

    /// The type of the tag.
    public var tag_type : TagType {
        return TagType.getTagTypeBasedOffDatabaseName(value: type)
    }

    /// The rating level of the tag. Only for tags of type ``TagType/RATING``.
    public var rating_level : RatingLevel {
        return RatingLevel.getRatingLevelBasedOffTagValue(value: value)
    }

    /// Sort tags by date.
    /// - Parameter tags: an array of tags to be sorted.
    /// - Returns: a sorted array of tags.
    static public func sortTagsByDate(tags : [Tag]) -> [Tag] {
        return tags.sorted { $0.getCreatedAt().compare($1.getCreatedAt()) == .orderedDescending }
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
}

// MARK: - API action passthroughs (unchanged semantics)
//extension Tag {
//    /// See ``Preferabli/deleteTag(tag_id:onCompletion:onFailure:)``.
//    public func delete(onCompletion : @escaping (Int) -> ()  = {_ in }, onFailure : @escaping (PreferabliException) -> () = {_ in }) {
//        Preferabli.main.deleteTag(tag_id: id, onCompletion: onCompletion, onFailure: onFailure)
//    }
//
//    /// See ``Preferabli/editTag(tag_id:tag_type:year:rating:location:notes:price:quantity:format_ml:onCompletion:onFailure:)``.
//    public func edit(year : Int, rating : RatingLevel = .NONE, location : String? = nil, notes : String? = nil, price : Decimal? = nil, quantity : Int? = nil, format_ml : Int? = nil, onCompletion : @escaping (Int) -> () = {_ in }, onFailure : @escaping (PreferabliException) -> () = {_ in }) {
//        Preferabli.main.editTag(tag_id: id, tag_type: tag_type, year: year, rating: rating, location: location, notes: notes, price: price, quantity: quantity, format_ml: format_ml, onCompletion: onCompletion, onFailure: onFailure)
//    }
//}

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
    /// Not a valid rating.
    case NONE

    static internal func getRatingLevelBasedOffTagValue(value : String?) -> RatingLevel {
        if let value {
            switch value {
            case "0":
                return .NONE
            case "1":
                return .DISLIKE
            case "2":
                return .SOSO
            case "3":
                return .LIKE
            case "4":
                return .LOVE
            default:
                return .NONE
            }
        }
        return .NONE
    }

    internal func getValue() -> String {
        switch self {
        case .LOVE:    return "4"
        case .LIKE:    return "3"
        case .SOSO:    return "2"
        case .DISLIKE: return "1"
        case .NONE:    return "0"
        }
    }

    public func compare(_ other: RatingLevel) -> ComparisonResult {
        return self.getValue().caseInsensitiveCompare(other.getValue())
    }
}

/// Type of a ``Tag``. Tags may can contain different information depending on it's type.
public enum TagType {
    case RATING
    case CELLAR
    case PURCHASE
    case WISHLIST
    case OTHER

    static internal func getTagTypeBasedOffDatabaseName(value : String?) -> TagType {
        if let value {
            switch value {
            case "rating":    return .RATING
            case "collection":return .CELLAR
            case "purchase":  return .PURCHASE
            case "wishlist":  return .WISHLIST
            default:          return .OTHER
            }
        }
        return .OTHER
    }

    internal func getDatabaseName() -> String {
        switch self {
        case .RATING:   return "rating"
        case .CELLAR:   return "collection"
        case .PURCHASE: return "purchase"
        case .WISHLIST: return "wishlist"
        case .OTHER:    return "other"
        }
    }

    public func compare(_ other: TagType) -> ComparisonResult {
        return self.getDatabaseName().caseInsensitiveCompare(other.getDatabaseName())
    }
}
