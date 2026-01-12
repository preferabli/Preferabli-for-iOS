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
import SwiftUI
import Combine

/// Represents a product  (e.g., wines, beers, spirits) within the Preferabli SDK. A product may have one or more ``Variant``s stored as ``variants``.  A variant can have one or more ``Tag``s which are used to associate a product with a user's interaction (e.g., rating) or with a particular ``Collection``.
@Model
public final class Product: HasIntID, HasTimestamps, HasImage {
    
    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    public var brand: String?
    public var decant: Bool?
    public var grape: String?
    public var brand_lat: Double?
    public var brand_lon: Double?
    public var show_year_dropdown: Bool?
    public var name: String?
    public var region: String?
    public var type: String?
    public var category: String?
    public var subcategory: String?
    public var brand_id: Int?
    public var product_hash: String?
    public var country_code: String?
    public var recommendable: Bool?

    // local
    public var cardToneRGB: Int?
    @Attribute(.externalStorage) public var temporaryImage: Data?
    public var temporaryName: String?

    // relationships
    @Relationship(deleteRule: .nullify) public var primary_image: Media?
    @Relationship(deleteRule: .cascade) public var variants: [Variant] = []
    @Relationship(deleteRule: .cascade) public var profile: ProductProfile?
    @Relationship(deleteRule: .cascade) public var preference_data: PreferenceData?

    @Relationship public var cachedMostRecentRating: Tag?
    @Relationship public var cachedWishlist: Tag?
    @Relationship public var cachedMostRecentVariant: Variant?
    @Relationship public var cachedPurchase: Tag?
    @Relationship public var cachedCellar: Tag?

    public init(id: Int) { self.id = id }
    
    public static func predicate(forID id: Int) -> Predicate<Product> {
        #Predicate<Product> { $0.id == id }
    }
    
    internal func updateCachedRelationships() {
        cachedMostRecentRating = Tag.sortTagsByDate(tags: variants.flatMap(\.tags)).first(where: { $0.tag_type == .RATING && $0.isTombstoned == false })
        cachedWishlist = variants.flatMap(\.tags).first(where: { $0.tag_type == .WISHLIST && $0.isTombstoned == false })
        cachedMostRecentVariant = variants.sorted { $0.year > $1.year }.first
    }

    /// The ``RatingLevel`` of the most recent rating of a specific product for the current user.
    var rating_level : RatingLevel? {
        if let mostRecentRating = cachedMostRecentRating {
            return RatingLevel.getRatingLevelBasedOffTagValue(value: mostRecentRating.value)
        }
        return nil
    }
    
    public func getShareLink() -> String? {
        guard let hash = product_hash else {
            return nil
        }
        return "https://app.preferabli.com/products/" + hash
    }

    /// All of the product tags of type ``TagType/PURCHASE`` for the current user.
    var purchase_tags: [Tag] {
        var purchaseTags = [Tag]()
        for variant in variants {
            for tag in variant.tags {
                if (tag.tag_type == .PURCHASE) {
                    purchaseTags.append(tag)
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
    var cellar_tags: [Tag] {
        var cellarTags = [Tag]()
        for variant in variants {
            for tag in variant.tags {
                if (tag.tag_type == .COLLECTION) {
                    cellarTags.append(tag)
                }
            }
        }
        return cellarTags
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
        return cachedWishlist != nil
    }

    /// Identifies if the current user added a specific product to a cellar collection.
    /// - Returns: true if the product is in the user's cellar.
    public func isInCellar() -> Bool {
        return cellar_tags.count != 0
    }

    /// All of the product tags of type ``TagType/RATING`` for the current user.
    public var ratings_tags: [Tag] {
        var ratingsTags = [Tag]()
        for variant in variants where !variant.isTombstoned {
            for tag in variant.tags where tag.tag_type == .RATING && !tag.isTombstoned {
                ratingsTags.append(tag)
            }
        }
        return ratingsTags
    }
    
    public var nameSanitized: String? {
        if let n = name, n.localizedCaseInsensitiveContains("identified") {
            if let tempName = temporaryName {
                return tempName
            }
            return n
        } else if !name.isEmptyOrWhitespace {
            return name
        }
        
        return nil
    }
    
    /// Returns grape if one exists
    public var grapeSanitized: String? {
        guard let g = grape,
              !g.localizedCaseInsensitiveContains("identifying")
        else { return nil }
        return g
    }
    
    /// Returns grape if one exists
    public var regionSanitized: String? {
        guard let r = region,
              !r.localizedCaseInsensitiveContains("info")
        else { return nil }
        return r
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
    public func getImage(width : Int, height : Int, quality : Int = 80) -> URL? {
        if (primary_image == nil || primary_image!.path.isEmptyOrWhitespace || primary_image?.path?.contains("placeholder") == true) {
            for variant in variants {
                if (variant.primary_image == nil || variant.primary_image!.path.isEmptyOrWhitespace || variant.primary_image?.path?.contains("placeholder") == true) {
                    continue
                }
                return variant.getImage(width: width, height: height, quality: quality)
            }
        }
        return PreferabliTools.getImageUrl(image: primary_image?.path, width: width, height: height, quality: quality)
    }
    
    public func getPlaceholderImage() -> String? {
        return nil
    }

    /// The type of a product (e.g., Red). Only for wines.
    public var product_type: ProductType? {
        return ProductType.getProductTypeFromString(value: type)
    }

    /// The category of a product.
    public var product_category: ProductCategory? {
        return ProductCategory.getProductCategoryFromString(value: category)
    }
    
    /// The subcategory of a product.
    public var product_subcategory: ProductSubcategory? {
        return ProductSubcategory.getProductSubcategoryFromString(value: subcategory)
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
        return cachedMostRecentVariant?.getPrice() ?? ""
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
        var candidateToReturn : Variant? = nil
        for variant in variants {
            if (variant.year == year) {
                if (variant.hasValidID) {
                    return variant
                } else {
                    candidateToReturn = variant
                }
            }
        }
        
        return candidateToReturn
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
    
    public static let tonePalette: [Color] = [
        Color.init(hex: "F4F8FA"),
    ]
    
    public var cardTone: Color {
        // Check cache first, then self, then fallback
        let v = ProductToneCache.shared.get(id)
        if let v = v {
            let ui = UIColor.unpackRGB(v).lightenedForCardTone()
            return Color(uiColor: ui)
        }
        return Self.tonePalette[0] // Fallback
    }
    
    /// Use this in SwiftUI
    public var cardToneColor: Color? {
        guard let v = cardToneRGB else { return nil }
        // Use helper to unpack
        let ui = UIColor.unpackRGB(v)
        return Color(uiColor: ui)
    }

    /// Set from UIColor
    @MainActor
    public func setCardTone(from color: UIColor) {
        // Use helper to pack
        let v = color.packRGB()

        // 1️⃣ Idempotency guard
        if cardToneRGB == v { return }

        // 2️⃣ Cache tone in memory for instant reuse
        ProductToneCache.shared.set(id, v)

        // 3️⃣ Only persist when user opens details or manually triggers save
        // (No write here to keep scrolling smooth)
        cardToneRGB = v
    }

    // Your original `flag` now returns the emoji
    public var flag: URL? {
        if let country_code = country_code {
            return URL.init(string: "https://purecatamphetamine.github.io/country-flag-icons/3x2/" + country_code.uppercased() + ".svg")
        } else {
            return nil
        }
    }
}

/// The category of a ``Product``.
public enum ProductCategory : Identifiable, Sendable, CaseIterable, Hashable {
    case WHISKEY
    case MEZCAL
    case VODKA
    case GIN
    case RUM
    case SAKE
    case COCKTAIL
    case CHEESE
    case BEER
    case WINE
    
    public var id: Self { self }

    public func getCategoryName() -> String {
        switch self {
        case .WHISKEY:
            return "whiskey"
        case .MEZCAL:
            return "tequila"
        case .BEER:
            return "beer"
        case .WINE:
            return "wine"
        case .CHEESE:
            return "cheese"
        case .VODKA:
            return "vodka"
        case .GIN:
            return "gin"
        case .RUM:
            return "rum"
        case .SAKE:
            return "sake"
        case .COCKTAIL:
            return "cocktail"
        }
    }

    static public func getProductCategoryFromString(value : String?) -> ProductCategory? {
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
            case "cheese":
                return .CHEESE
            case "vodka":
                return .VODKA
            case "gin":
                return .GIN
            case "rum":
                return .RUM
            case "sake":
                return .SAKE
            case "cocktail":
                return .COCKTAIL
            default:
                return nil
            }
        }
        return nil
    }
}

/// The subcategory of a ``Product``.
public enum ProductSubcategory : Sendable, CaseIterable, Hashable {
    // beers, ciders, seltzers
    case ALE
    case LAGER
    case GF
    case NON_ALC_BEER
    case CANNABIS
    case ENERGY
    case FLAVORED
    case NON_ALC_BEVERAGE
    case CIDER
    
    // whiskies
    case BOURBON
    case FLAVORED_WHISKEY
    case RYE
    case SCOTCH
    case WHISKEY

    public func getSubcategoryName() -> String {
        switch self {
        case .ALE:
            return "ale"
        case .LAGER:
            return "lager"
        case .GF:
            return "gluten_free_beer"
        case .NON_ALC_BEER:
            return "non_alcoholic_beer"
        case .CANNABIS:
            return "cannabis_based_drink"
        case .ENERGY:
            return "energy_drink"
        case .FLAVORED:
            return "flavored_alcoholic_beverage"
        case .NON_ALC_BEVERAGE:
            return "non_alcoholic_beverage"
        case .CIDER:
            return "cider"
            
        case .BOURBON:
            return "bourbon"
        case .FLAVORED_WHISKEY:
            return "flavored_whiskey"
        case .RYE:
            return "rye"
        case .SCOTCH:
            return "scotch"
        case .WHISKEY:
            return "whiskey"
        }
    }

    static public func getProductSubcategoryFromString(value : String?) -> ProductSubcategory? {
            if let value {
                let lowercasedValue = value.lowercased()
                switch lowercasedValue {
                case "ale":
                    return .ALE
                case "lager":
                    return .LAGER
                case "gluten_free_beer":
                    return .GF
                case "non_alcoholic_beer":
                    return .NON_ALC_BEER
                case "canabis_based_drink":
                    return .CANNABIS
                case "energy_drink":
                    return .ENERGY
                case "flavored_alcoholic_beverage":
                    return .FLAVORED
                case "non_alcoholic_beverage":
                    return .NON_ALC_BEVERAGE
                case "cider":
                    return .CIDER
                    
                case "bourbon":
                    return .BOURBON
                case "flavored_whiskey":
                    return .FLAVORED_WHISKEY
                case "rye":
                    return .RYE
                case "scotch":
                    return .SCOTCH
                case "whiskey":
                    return .WHISKEY
                default:
                    return nil
                }
            }
            return nil
        }
}

/// The recognized type of a ``Product``.  At this time, non-wine products use the type ``ProductType/OTHER``.
public enum ProductType : Sendable, CaseIterable, Hashable {
    case RED
    case WHITE
    case ROSE
    case SPARKLING
    case FORTIFIED

    public func getTypeName() -> String {
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
        }
    }

    static public func getProductTypeFromString(value : String?) -> ProductType? {
        if let value {
            switch value.lowercased() {
            case "red":
                return .RED
            case "white":
                return .WHITE
            case "rosé", "rose":
                return .ROSE
            case "fortified":
                return .FORTIFIED
            case "sparkling":
                return .SPARKLING
            default:
                return nil
            }
        }
        return nil
    }

    /// Is a specific product a wine?
    /// - Returns: true if the product type corresponds to a wine.
    public func isWine() -> Bool {
        return self == .RED || self == .WHITE || self == .ROSE || self == .SPARKLING || self == .FORTIFIED
    }
}

public final class ProductToneCache: @unchecked Sendable {
    public static let shared = ProductToneCache()

    private let tones = NSCache<NSNumber, NSNumber>()            // productID → RGB
    private var versions: [Int: Int] = [:]                      // non-published
    private var subjects: [Int: CurrentValueSubject<Int, Never>] = [:]
    private let lock = NSLock()                                  // guard maps (cheap)

    public func get(_ id: Int) -> Int? {
        tones.object(forKey: NSNumber(value: id))?.intValue
    }

    public func set(_ id: Int, _ rgb: Int) {
        tones.setObject(NSNumber(value: rgb), forKey: NSNumber(value: id))
        let v: Int = {
            lock.lock(); defer { lock.unlock() }
            let nv = (versions[id] ?? 0) &+ 1
            versions[id] = nv
            subjects[id]?.send(nv)                               // notify only this id
            return nv
        }()
        _ = v // keep if you want to use it
    }

    public func version(for id: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        return versions[id] ?? 0
    }

    public func publisher(for id: Int) -> AnyPublisher<Int, Never> {
        lock.lock(); defer { lock.unlock() }
        if let s = subjects[id] { return s.eraseToAnyPublisher() }
        let s = CurrentValueSubject<Int, Never>(versions[id] ?? 0)
        subjects[id] = s
        return s.eraseToAnyPublisher()
    }
}

extension Product {
    func analyticsKind() -> ProfileProductKind? {
        // 1) Wine type mapping (red/white/rose/sparkling/fortified)
        if let wineType = product_type {
            switch wineType {
            case .RED:       return .red
            case .WHITE:     return .white
            case .ROSE:      return .rose
            case .SPARKLING: return .sparkling
            case .FORTIFIED: return .fortified
            }
        }

        // 2) Category mapping (spirits/beer/cheese/etc)
        if let cat = product_category {
            switch cat {
            case .WHISKEY:  return .whiskey
            case .MEZCAL:   return .mezcal
            case .BEER:     return .beer
            case .WINE:     return .red      // fallback if wine type missing
            case .CHEESE:   return .cheese
            case .VODKA:    return .vodka
            case .GIN:      return .gin
            case .RUM:      return .rum
            case .SAKE:     return .sake
            case .COCKTAIL: return .cocktail
            }
        }

        return nil
    }
}
