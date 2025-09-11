//
//  Collection.swift (SwiftData @Model merged with legacy helpers)
//  Preferabli
//
//  This file merges the SwiftData model with the original helper methods and
//  documentation comments from the legacy Collection classes (Collection, CollectionVersion,
//  CollectionGroup, CollectionOrder, CollectionTrait, CollectionType).
//
//  Notes:
//  - Numeric ordering/count fields use Int/Int? instead of NSNumber.
//  - IDs are marked @Attribute(.unique) where appropriate to support upserts.
//  - Helpers preserve original semantics and comments; alpha/locale helpers rely on PreferabliTools.
//
//  Generated on demand.
//

import Foundation
import SwiftData

/// A Collection is a selection of ``Product``s, organized into one or more ``CollectionGroup``.  For example, a collection can represent an inventory for a store or just a subset of products, such as selection of products that are currently on sale or a selection of private-label products.
///
/// In general, a collection will be an ``CollectionType/INVENTORY`` or an ``CollectionType/EVENT``.  Events are temporal in nature, such as a tasting events or weekly promotions.  Inventories, whether entire inventories or subsets of an inventory, are meant to change from time to time but are not specifically temporal in nature.
///
/// A Collection may also be a ``CollectionType/CELLAR`` type (e.g., a ``Customer``'s personal cellar) or ``CollectionType/OTHER`` type.
///
/// Collections are structured as follows: a collection has one or more ``CollectionVersion``s. Each version has one or more ``CollectionGroup``s. And each group contains one or more ``CollectionOrder``s, which link directly to a ``Tag`` and thus by reference a ``Product``.
@Model
public final class Collection: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date?
    public var updated_at: Date?
    public var channel_id: Int?
    public var sort_channel_id: Int?
    public var code: String?
    public var desc: String?
    public var end_date: Date?
    public var auto_wili: Bool?
    public var has_image: Bool?
    public var is_pinned: Bool?
    public var display_time: Bool?
    public var is_browsable: Bool?
    public var is_my_cellar: Bool?
    public var lbs_order: Int?
    public var product_count: Int?
    public var name: String?
    public var badge_method: String?
    public var currency: String?
    public var timezone: String?
    public var published: Bool?
    public var archived: Bool?
    public var display_price: Bool?
    public var display_quantity: Bool?
    public var display_bin: Bool?
    public var has_predict_order: Bool?
    public var is_randomized: Bool?
    public var display_group_headings: Bool?
    public var is_blind: Bool?
    public var start_date: Date?
    public var venue_id: Int?
    public var sort_channel_name: String?
    public var location_based_recs: Bool?

    // MARK: - Relationships
    @Relationship(deleteRule: .nullify) public var primary_image: Media?
    @Relationship(deleteRule: .nullify) public var venue: Venue?
    @Relationship(deleteRule: .nullify, inverse: \CollectionVersion.collection) public var versions: [CollectionVersion] = []
    @Relationship(deleteRule: .nullify, inverse: \CollectionTrait.collection) public var traits: [CollectionTrait] = []
    @Relationship(deleteRule: .nullify) public var user_collections: [UserCollection] = []

    // MARK: - Init
    public init(id: Int) { self.id = id }

    public init(
        channel_id: Int? = nil,
        sort_channel_id: Int? = nil,
        code: String? = nil,
        desc: String? = nil,
        end_date: Date? = nil,
        updated_at: Date? = nil,
        auto_wili: Bool? = nil,
        has_image: Bool? = nil,
        is_pinned: Bool? = nil,
        display_time: Bool? = nil,
        is_browsable: Bool? = nil,
        is_my_cellar: Bool? = nil,
        lbs_order: Int? = nil,
        product_count: Int? = nil,
        id: Int,
        name: String? = nil,
        badge_method: String? = nil,
        currency: String? = nil,
        timezone: String? = nil,
        published: Bool? = nil,
        archived: Bool? = nil,
        display_price: Bool? = nil,
        display_quantity: Bool? = nil,
        display_bin: Bool? = nil,
        has_predict_order: Bool? = nil,
        is_randomized: Bool? = nil,
        display_group_headings: Bool? = nil,
        is_blind: Bool? = nil,
        start_date: Date? = nil,
        created_at: Date? = nil,
        venue_id: Int? = nil,
        sort_channel_name: String? = nil,
        order: Int? = nil,
        location_based_recs: Bool? = nil,
        primary_image: Media? = nil,
        venue: Venue? = nil,
        versions: [CollectionVersion] = [],
        traits: [CollectionTrait] = [],
        user_collections: [UserCollection] = []
    ) {
        self.channel_id = channel_id
        self.sort_channel_id = sort_channel_id
        self.code = code
        self.desc = desc
        self.end_date = end_date
        self.updated_at = updated_at
        self.auto_wili = auto_wili
        self.has_image = has_image
        self.is_pinned = is_pinned
        self.display_time = display_time
        self.is_browsable = is_browsable
        self.is_my_cellar = is_my_cellar
        self.lbs_order = lbs_order
        self.product_count = product_count
        self.id = id
        self.name = name
        self.badge_method = badge_method
        self.currency = currency
        self.timezone = timezone
        self.published = published
        self.archived = archived
        self.display_price = display_price
        self.display_quantity = display_quantity
        self.display_bin = display_bin
        self.has_predict_order = has_predict_order
        self.is_randomized = is_randomized
        self.display_group_headings = display_group_headings
        self.is_blind = is_blind
        self.start_date = start_date
        self.created_at = created_at
        self.venue_id = venue_id
        self.sort_channel_name = sort_channel_name
        self.location_based_recs = location_based_recs
        self.primary_image = primary_image
        self.venue = venue
        self.versions = versions
        self.traits = traits
        self.user_collections = user_collections
    }

    // MARK: - Legacy helpers (ported)

    /// Get the collection's image.
    /// - Parameters:
    ///   - width: returns an image with the specified width in pixels.
    ///   - height: returns an image with the specified height in pixels.
    ///   - quality: returns an image with the specified quality. Scales from 0 - 100.
    /// - Returns: the URL of the requested image.
    public func getImage(width : Float, height : Float, quality : Int = 80) -> URL? {
        return PreferabliTools.getImageUrl(image: primary_image?.path, width: width, height: height, quality: quality)
    }

    /// Get the start date of the collection. Start dates are useful for collections of type Event.
    /// - Returns: the start date - or nil if it does not exist.
    public func getStartDate() -> Date? {
        return start_date
    }

    /// Get the last updated date of the collection.
    /// - Returns: the updated at date.
    public func getUpdatedDate() -> Date? {
        return updated_at
    }

    /// Get the end date of the collection. End dates are useful for collection of type Event.
    /// - Returns: the end date - or nil if it does not exist.
    public func getExpirationDate() -> Date? {
        return end_date
    }

    /// This helper method filters an array of collections to those of type Inventory.
    /// - Parameter collections: array of collections of different types.
    /// - Returns: array of collection of type Inventory.
    static public func filterToInventories(collections : [Collection]) -> [Collection] {
        return collections.filter { $0.isInventory() }
    }

    /// Sort collections by their updated at date.
    /// - Parameters:
    ///   - collections: array of collections to be sorted.
    ///   - comparison_result: can be ascending or descending. Defaults to *descending*.
    /// - Returns: a sorted array of collections.
    static public func sortCollectionsByLastUpdated(collections : [Collection], comparison_result: ComparisonResult = .orderedDescending) -> [Collection] {
        return collections.sorted {
            let d1 = $0.getUpdatedDate() ?? Date()
            let d2 = $1.getUpdatedDate() ?? Date()
            if d1 == d2 {
                return String.alphaSortIgnoreThe(x: $0.name, y: $1.name)
            }
            return (d1.compare(d2) == comparison_result)
        }
    }

    /// Sort collections alphabetically.
    /// - Parameters:
    ///   - collections: array of collections to be sorted.
    ///   - comparison_result: can be ascending or descending. Defaults to *ascending*.
    /// - Returns: a sorted array of collections.
    static public func sortCollectionsAlpha(collections : [Collection], comparison_result: ComparisonResult = .orderedAscending) -> [Collection] {
        return collections.sorted {
            return String.alphaSortIgnoreThe(x: $0.name, y: $1.name, comparisonResult: comparison_result)
        }
    }

    /// Filter collections by search.
    /// - Parameters:
    ///   - collections: array of collections to be filtered.
    ///   - search_text: string that contains the search term.
    /// - Returns: a filtered array of collections.
    static public func filterCollections(collections : [Collection], search_text : String) -> [Collection] {
        if search_text.isEmptyOrWhitespace() { return collections }
        let terms = search_text.components(separatedBy: " ")
        return collections.filter { coll in
            for t in terms {
                if coll.filterCollection(search_term: t) { continue } else { return false }
            }
            return true
        }
    }

    internal func filterCollection(search_term : String) -> Bool {
        if search_term.isEmptyOrWhitespace() { return true }
        if name?.containsIgnoreCase(search_term) ?? false { return true }
        if sort_channel_name?.containsIgnoreCase(search_term) ?? false { return true }
        if venue?.display_name?.containsIgnoreCase(search_term) ?? false { return true }
        return false
    }

    /// Collection Type of a specific collection.  In general, a Collection will be an ``CollectionType/INVENTORY`` or an ``CollectionType/EVENT``.  Events are temporal in nature, such as a tasting events or weekly promotions.  Inventories, whether entire inventories or subsets of an inventory, are meant to change from time to time but are not specifically temporal in nature.
    public var type : CollectionType {
        return CollectionType.getCollectionTypeBasedOffCollection(collection: self)
    }

    /// Lets us know if a collection is of the type ``CollectionType/INVENTORY``.
    /// - Returns: true if an inventory.
    public func isInventory() -> Bool {
        for trait in traits {
            if trait.id == 86 { return true }
        }
        return false
    }

    /// Lets us know if a collection is of the type ``CollectionType/EVENT``.
    /// - Returns: true if an event.
    public func isEvent() -> Bool {
        for trait in traits {
            if trait.id == 84 || trait.id == 88 || trait.id == 90 {
                return true
            }
        }
        return false
    }
}

// MARK: - CollectionType
/// The type of a ``Collection``.
public enum CollectionType {
    case EVENT
    case INVENTORY
    case CELLAR
    case OTHER

    static internal func getCollectionTypeBasedOffCollection(collection : Collection) -> CollectionType {
        if (collection.is_my_cellar ?? false) {
            return .CELLAR
        } else if (collection.isEvent()) {
            return .EVENT
        } else if (collection.isInventory()) {
            return .INVENTORY
        }
        return .OTHER
    }
}
