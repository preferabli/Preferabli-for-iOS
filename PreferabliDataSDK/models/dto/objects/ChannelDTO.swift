//
//  ChannelDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 1/16/26.
//

import Foundation

public struct ChannelVenueDTO: Decodable, Sendable {
    public let id: Int
    public let venue: VenueDTO?
    public let is_primary: Bool?
    public let archived: Bool?
}

public struct ChannelDTO: Decodable, Sendable {
    public let id: Int

    public let featured_collection_id: Int?
    public let primary_inventory_id: Int?
    public let account_id: Int?

    public let primary_image: MediaDTO?

    public let default_display_vintages: Bool?
    public let primary_questionnaire_id: Int?

    public let venues: [VenueDTO]?
    public let primary_venues: [VenueDTO]?

    public let name: String?
    public let description: String?
    public let order: Int?

    public let default_downweight_previous_recs_duration: Int?
    public let default_curation_batch_id: Int?
    public let default_curation_questions_batch_id: Int?

    public let campaign_require_lookups: Bool?
    public let campaign_default_from_email: String?
    public let campaign_default_from_name: String?

    public let max_number_of_venues: Int?
    public let channel_venues: [ChannelVenueDTO]?

    public let currency_exchange_multiplier_from_foreign_to_usd: Double?

    public let is_retailer: Bool?
    public let display_variant_details: Bool?
    public let is_producer: Bool?
    public let is_restaurant: Bool?
    public let is_hospitality: Bool?
    public let is_event: Bool?

    public let search_weight: Int?
    public let is_verified: Bool?
    public let archived: Bool?

    public let published: Bool?

    public let has_download_pdf: Bool?
    public let has_download_csv: Bool?
    public let has_download_xlsx: Bool?

    public let images: [MediaDTO]?

    public let default_badge_method: String?
    public let default_display_variants: Bool?
    public let default_display_price: Bool?
    public let default_display_quantity: Bool?
    public let default_display_bin: Bool?

    public let default_timezone: String?
    public let default_currency: String?

    public let num_dollar_signs_cutoff_1: Int?
    public let num_dollar_signs_cutoff_2: Int?
    public let num_dollar_signs_cutoff_3: Int?
    public let num_dollar_signs_cutoff_4: Int?
    public let num_dollar_signs_cutoff_5: Int?

    public let automatically_create_lookups_from_tags: Bool?

    public let created_at: Date?
    public let updated_at: Date?
}
