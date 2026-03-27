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
public final class Collection: HasIntID, HasTimestamps, HasImage {
    
    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    public var channel_id: Int?
    public var sort_channel_id: Int?
    public var code: String?
    public var desc: String?
    public var end_date: Date?
    public var auto_wili: Bool?
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
    @Relationship(deleteRule: .cascade, inverse: \CollectionVersion.collection) public var versions: [CollectionVersion] = []
    @Relationship(deleteRule: .cascade) public var user_collections: [UserCollection] = []
    
    // MARK: - Init
    public init(id: Int) { self.id = id }

    // MARK: - Legacy helpers (ported)

    /// Get the collection's image.
    /// - Parameters:
    ///   - width: returns an image with the specified width in pixels.
    ///   - height: returns an image with the specified height in pixels.
    ///   - quality: returns an image with the specified quality. Scales from 0 - 100.
    /// - Returns: the URL of the requested image.
    public func getImage(width : Int, height : Int, quality : Int = 80) -> URL? {
        return PreferabliTools.getImageUrl(image: primary_image?.path, width: width, height: height, quality: quality)
    }

    public static func predicate(forID id: Int) -> Predicate<Collection> {
        #Predicate<Collection> { $0.id == id }
    }

    public var has_image : Bool {
        primary_image != nil
    }

    public func getPlaceholderImage() -> String? {
        return nil
    }
}
