//
//  MarketTrait.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 2/4/26.
//


import SwiftData
import Foundation

@Model
public final class MarketTrait: HasIntID, HasTimestamps {

    @Attribute(.unique) public var id: Int

    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var type: String?
    public var name: String?
    public var order: Int?
    
    public var icon_url: String?
    
    @Relationship(deleteRule: .cascade) public var market_trait_associations: [MarketTraitAssociation]?
    @Relationship(deleteRule: .cascade) public var venue_market_traits: [VenueMarketTrait]?
    @Relationship(deleteRule: .cascade) public var itinerary_market_traits: [ItineraryMarketTrait]?

    public init(id: Int) {
        self.id = id
    }

    public static func predicate(forID id: Int) -> Predicate<MarketTrait> {
        #Predicate<MarketTrait> { $0.id == id }
    }
}
