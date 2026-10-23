//
//  ItineraryDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 7/15/26.
//

import Foundation

public struct ItineraryDTO: Decodable, Sendable {
    public let id: Int
    public let primary_image: MediaDTO?
    public let curator_personality: PersonalityDTO?
    public let curator_personality_description: String?
    public let images: [MediaDTO]?
    public let name: String?
    public let type: String?
    public let section_title_justification: String?
    public let section_title_size: Double?
    public let description: String?
    public let badge_title: String?
    public let badge_icon: String?
    public let badge_color_hex_primary: String?
    public let badge_color_hex_secondary: String?
    public let badge_text_color_hex: String?
    public let badge_gradient_css: String?
    public let color_hex_primary: String?
    public let text_color_hex: String?
    public let itinerary_items: [ItineraryItemDTO]?
    public let market_trait_associations: [ItineraryMarketTraitDTO]?
    public let highlights: [ItineraryHighlightDTO]?
    public let duration_minutes_low: Int?
    public let duration_minutes_high: Int?
    public let distance_display: Int?
    public let distance_unit: String?
    public let `public`: Bool?
    public let created_at: Date?
    public let updated_at: Date?
    public let market_id: Int?
}

public struct ItineraryItemDTO: Decodable, Sendable {
    public let id: Int
    public let time: String?
    public let name: String?
    public let description: String?
    public let type: String?
    public let order: Int?
    public let optional: Bool?
    public let hide_details: Bool?
    public let item_associations: [ItineraryItemAssociationDTO]?
    public let created_at: Date?
    public let updated_at: Date?
}

/// Supports either an embedded `market_trait` object or only `market_trait_id`.
/// The association `id` is optional because some join payloads do not provide one.
public struct ItineraryMarketTraitDTO: Decodable, Sendable {
    public let id: Int?
    public let market_trait_id: Int?
    public let market_trait: MarketTraitDTO?
    public let order: Int?
    public let created_at: Date?
    public let updated_at: Date?
}

/// An itinerary or guide content block with optional embedded destinations, media, or CTA content.
public struct ItineraryItemAssociationDTO: Decodable, Sendable {
    public let id: Int
    public let highlights: [ItineraryHighlightDTO]?
    public let venue: VenueDTO?
    public let experience: ExperienceDTO?
    public let primary_media: MediaDTO?
    public let itinerary: ItineraryDTO?
    public let cta_page: CTAPageDTO?
    public let description: String?
    public let local_tip_title: String?
    public let local_tip: String?
    public let button_title: String?
    public let button_deeplink_url: String?
    public let button_icon: String?
    public let item_association_children: [ItineraryItemAssociationDTO]?
    public let order: Int?
    public let created_at: Date?
    public let updated_at: Date?
}

public struct ItineraryHighlightDTO: Decodable, Sendable {
    public let id: Int
    public let icon_url: String?
    public let order: Int?
    public let name: String?
    public let description: String?
    public let type: String?
}
