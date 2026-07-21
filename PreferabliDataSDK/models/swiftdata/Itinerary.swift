//
//  Itinerary.swift
//  PreferabliDataSDK
//
//  SwiftData models for itinerary payloads.
//

import Foundation
import SwiftData

@Model
public final class Itinerary: HasIntID, HasTimestamps, HasImage {

    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var name: String?

    /// Persisted using the same naming convention as ContentItem and Market.
    public var desc: String?
    
    public var color_hex_primary: String?

    /// Local-only denormalized value. The API does not return the itinerary's Market.
    public var market_id: Int
    
    public var badge_title: String?
    public var badge_icon: String?
    public var badge_color_hex_primary: String?
    public var badge_color_hex_secondary: String?
    public var badge_gradient_css: String?
    public var badge_text_color_hex: String?

    @Relationship(deleteRule: .nullify)
    public var primary_image: Media?

    @Relationship(deleteRule: .nullify)
    public var images: [Media] = []

    @Relationship(deleteRule: .cascade, inverse: \ItineraryItem.itinerary)
    public var itinerary_items: [ItineraryItem] = []

    @Relationship(deleteRule: .cascade, inverse: \ItineraryMarketTrait.itinerary)
    public var market_trait_associations: [ItineraryMarketTrait] = []
    
    @Relationship(deleteRule: .cascade, inverse: \ItineraryHighlight.itinerary)
    public var highlights: [ItineraryHighlight] = []

    /// Assigned locally by the caller while the DTO is being upserted.
    @Relationship(deleteRule: .nullify)
    public var market: Market?
    
    @Relationship(deleteRule: .nullify)
    public var curator_personality: Personality?

    public init(id: Int, market: Market) {
        self.id = id
        self.market_id = market.id
        self.market = market
    }

    public func getImage(width: Int, height: Int, quality: Int = 80) -> URL? {
        (primary_image ?? images.first)?.getImage(
            width: width,
            height: height,
            quality: quality
        )
    }

    public func getPlaceholderImage() -> String? {
        nil
    }

    public static func predicate(forID id: Int) -> Predicate<Itinerary> {
        #Predicate<Itinerary> { $0.id == id }
    }
}

@Model
public final class ItineraryItem: HasIntID, HasTimestamps {

    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var time: String?
    public var name: String?
    public var desc: String?
    public var local_tip: String?
    public var benefit: String?
    public var other_options: String?
    public var type: String?
    public var order: Int?

    public var itinerary_id: Int?

    @Relationship(deleteRule: .nullify)
    public var itinerary: Itinerary?

    @Relationship(deleteRule: .cascade, inverse: \ItineraryItemAssociation.itinerary_item)
    public var item_associations: [ItineraryItemAssociation] = []

    public init(id: Int, itinerary: Itinerary? = nil) {
        self.id = id
        self.itinerary = itinerary
        self.itinerary_id = itinerary?.id
    }

    public static func predicate(forID id: Int) -> Predicate<ItineraryItem> {
        #Predicate<ItineraryItem> { $0.id == id }
    }
}

/// Join row for Itinerary <-> MarketTrait.
///
/// A composite key is used because this relation can be returned without a stable
/// association id, matching the existing VenueMarketTrait approach.
@Model
public final class ItineraryMarketTrait {

    @Attribute(.unique) public var key: String

    /// Populated when the API does include an id for the join row.
    public var remote_id: Int?

    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    public var order: Int?

    public var itinerary_id: Int
    public var market_trait_id: Int

    @Relationship(deleteRule: .nullify)
    public var itinerary: Itinerary

    @Relationship(deleteRule: .nullify, inverse: \MarketTrait.itinerary_market_traits)
    public var market_trait: MarketTrait

    public init(
        key: String,
        itinerary: Itinerary,
        market_trait: MarketTrait
    ) {
        self.key = key
        self.itinerary = itinerary
        self.itinerary_id = itinerary.id
        self.market_trait = market_trait
        self.market_trait_id = market_trait.id
    }

    public static func makeKey(itineraryID: Int, marketTraitID: Int) -> String {
        "itinerary:\(itineraryID)|trait:\(marketTraitID)"
    }

    public static func predicate(forKey key: String) -> Predicate<ItineraryMarketTrait> {
        #Predicate<ItineraryMarketTrait> { $0.key == key }
    }
}

@Model
public final class ItineraryItemAssociation: HasIntID, HasTimestamps {

    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var itinerary_item_id: Int?
    public var venue_id: Int?
    public var experience_id: Int?
    public var order: Int?

    @Relationship(deleteRule: .nullify)
    public var itinerary_item: ItineraryItem?

    @Relationship(deleteRule: .nullify)
    public var venue: Venue?
    
    @Relationship(deleteRule: .nullify)
    public var experience: Experience?

    public init(id: Int, itinerary_item: ItineraryItem? = nil) {
        self.id = id
        self.itinerary_item = itinerary_item
        self.itinerary_item_id = itinerary_item?.id
    }

    public static func predicate(forID id: Int) -> Predicate<ItineraryItemAssociation> {
        #Predicate<ItineraryItemAssociation> { $0.id == id }
    }
}

@Model
public final class ItineraryHighlight: HasIntID, HasTimestamps {

    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var icon_url: String?
    public var order: Int?
    public var name: String?
    public var desc: String?

    @Relationship(deleteRule: .nullify)
    public var itinerary: Itinerary

    public init(id: Int, itinerary: Itinerary) {
        self.id = id
        self.itinerary = itinerary
    }

    public static func predicate(forID id: Int) -> Predicate<ItineraryHighlight> {
        #Predicate<ItineraryHighlight> { $0.id == id }
    }
}
