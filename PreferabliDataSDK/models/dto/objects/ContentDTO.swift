//
//  ContentDTO.swift
//  PreferabliDataSDK
//
//  DTOs for GET /content/:id and GET /personalities/:id.
//

import Foundation

/// `ContentDTO` is a class, not a struct, because the API payload is recursive:
/// content can contain content_children and content_parent.
public final class ContentDTO: Decodable, @unchecked Sendable {
    public let id: Int
    public let content_parent: ContentDTO?
//    public let content_children: [ContentDTO]?
    public let primary_media: MediaDTO?

    public let personality_associations: [ContentPersonalityAssociationDTO]?
    public let variant_associations: [ContentVariantAssociationDTO]?
//    public let channel_associations: [ContentChannelAssociationDTO]?
    public let venue_associations: [ContentVenueAssociationDTO]?
    public let experience_associations: [ContentExperienceAssociationDTO]?
//    public let market_traits_associations: [ContentMarketTraitAssociationDTO]?
    public let products_cache: [ProductDTO]?
    public let venues_cache: [VenueDTO]?

    public let title: String?
    public let description: String?
    public let episode_name: String?
    public let episode_order: Int?
    public let created_at: Date?
    public let updated_at: Date?
}

/// `PersonalityDTO` is also a class because it references content associations,
/// and each association can contain a recursive ContentDTO.
public final class PersonalityDTO: Decodable, @unchecked Sendable {
    public let id: Int
    public let primary_media: MediaDTO?
    public let name: String?
    public let description: String?
    public let badge_title: String?
    public let badge_text_color_hex: String?
    public let badge_gradient_css: String?
    public let created_at: Date?
    public let updated_at: Date?
}

/// Used in both directions:
/// - Content payload: { personality, relationship, order }
/// - Personality payload: { content, relationship, order }
public struct ContentPersonalityAssociationDTO: Decodable, Sendable {
    public let id: Int
    public let content: ContentDTO?
    public let personality: PersonalityDTO?
    public let relationship: String?
    public let order: Int?
    public let created_at: Date?
    public let updated_at: Date?
}

public struct ContentVariantAssociationDTO: Decodable, Sendable {
    public let id: Int
    public let variant_id: Int?
    public let product_id: Int?
    public let order: Int?
    public let created_at: Date?
    public let updated_at: Date?
}

/// The embedded content variant in the sample payload does not include product_id.
/// Keep this separate from the main VariantDTO so decoding content does not require
/// the fuller product/variant payload shape.
public struct ContentVariantReferenceDTO: Decodable, Sendable {
    public let id: Int
    public let price: Decimal?
    public let num_dollar_signs: Int?
    public let primary_image: MediaDTO?
    public let year: Int?
    public let fresh: Bool?
    public let recommendable: Bool?
    public let images: [MediaDTO]?
    public let deleted_on_curation: Bool?
}

public struct ContentChannelAssociationDTO: Decodable, Sendable {
    public let id: Int
    public let channel: ChannelDTO?
    public let order: Int?
    public let created_at: Date?
    public let updated_at: Date?
}

public struct ContentVenueAssociationDTO: Decodable, Sendable {
    public let id: Int
    public let venue_id: Int?
    public let order: Int?
    public let created_at: Date?
    public let updated_at: Date?
}

public struct ContentExperienceAssociationDTO: Decodable, Sendable {
    public let id: Int
    public let experience: ExperienceDTO?
    public let order: Int?
    public let created_at: Date?
    public let updated_at: Date?
}

public struct ContentMarketTraitAssociationDTO: Decodable, Sendable {
    public let id: Int
    public let market_trait: MarketTraitDTO?
    public let order: Int?
    public let created_at: Date?
    public let updated_at: Date?
}
