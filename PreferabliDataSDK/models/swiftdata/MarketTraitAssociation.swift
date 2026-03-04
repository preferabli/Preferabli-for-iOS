//
//  MarketTraitAssociation.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 2/26/26.
//


import SwiftData
import Foundation

@Model
public final class MarketTraitAssociation: HasIntID, HasTimestamps {

    @Attribute(.unique) public var id: Int

    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var order: Int?
    
    @Relationship public var market: Market
    @Relationship(deleteRule: .nullify, inverse: \MarketTrait.market_trait_associations) public var market_trait: MarketTrait

    
    public init(id: Int, market: Market, market_trait: MarketTrait) {
        self.id = id
        self.market = market
        self.market_trait = market_trait
    }

    public static func predicate(forID id: Int) -> Predicate<MarketTraitAssociation> {
        #Predicate<MarketTraitAssociation> { $0.id == id }
    }
}
