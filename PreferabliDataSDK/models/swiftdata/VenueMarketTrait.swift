//
//  VenueMarketTrait.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 2/25/26.
//


import Foundation
import SwiftData

/// Join row for Venue <-> MarketTrait, storing per-venue ordering (and optional market scoping).
@Model
public final class VenueMarketTrait {

    /// Stable unique key (since API join row has no id).
    /// Format: "venue:<vid>|market:<mid-or-nil>|trait:<tid>"
    @Attribute(.unique) public var key: String

    /// Order as returned by VenueMarketTraitDTO
    public var order: Int?

    /// Denormalized ids (useful for filtering without relationship predicates).
    public var venue_id: Int
    public var trait_id: Int
    public var market_id: Int?

    // MARK: - Relationships

    @Relationship(deleteRule: .nullify) public var venue: Venue
    @Relationship(deleteRule: .nullify, inverse: \MarketTrait.venue_market_traits) public var trait: MarketTrait

    public init(key: String, venue: Venue, trait: MarketTrait, market_id: Int?) {
        self.key = key
        self.venue = venue
        self.venue_id = venue.id
        self.trait = trait
        self.trait_id = trait.id
        self.market_id = market_id
    }

    public static func makeKey(venueID: Int, marketID: Int?, traitID: Int) -> String {
        "venue:\(venueID)|market:\(marketID.map(String.init) ?? "nil")|trait:\(traitID)"
    }

    public static func predicate(forKey key: String) -> Predicate<VenueMarketTrait> {
        #Predicate<VenueMarketTrait> { $0.key == key }
    }
}
