//
//  MarketDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 2/4/26.
//

import Foundation

public struct MarketDTO: Decodable, Sendable {
    public let id: Int
    public let name: String?
    public let image_url: String?
    public let description: String?
    public let top_level_order: Int?
    public let created_at: Date?
    public let updated_at: Date?
    public let country_code: String?
    public let display_appellations: Bool?
    public let latitude: Double?
    public let longitude: Double?
    public let default_span_delta: Double?
    public let submarkets: [MarketDTO]?
    public let market_trait_associations: [MarketTraitAssociationDTO]?
}

public struct MarketTraitAssociationDTO: Decodable, Sendable {
    public let id: Int
    public let order: Int?
    public let market_trait: MarketTraitDTO?
    public let is_filter_option: Bool?
    public let created_at: Date?
    public let updated_at: Date?
}

public struct MarketTraitDTO: Decodable, Sendable {
    public let id: Int
    public let type: String?
    public let name: String?
    public let icon_url: String?
    public let created_at: Date?
    public let updated_at: Date?
}
