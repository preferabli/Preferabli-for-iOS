//
//  Channel.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 1/16/26.
//

import Foundation
import SwiftData

@Model
public final class Channel: HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int

    // MARK: - Timestamps
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    // MARK: - Core fields
    public var account_id: Int?
    public var name: String?
    public var description_text: String? // maps JSON key "description"
    public var order: Int?
    public var archived: Bool?
    public var published: Bool?

    // MARK: - Flags / display settings
    public var default_display_vintages: Bool?
    public var default_display_variants: Bool?
    public var default_display_variant_details: Bool?
    public var default_display_price: Bool?
    public var default_display_quantity: Bool?
    public var default_display_bin: Bool?
    public var default_downweight_previous_recs_duration: Int?

    // MARK: - Download flags
    public var has_download_pdf: Bool?
    public var has_download_csv: Bool?
    public var has_download_xlsx: Bool?

    // MARK: - Channel classification flags (from JSON)
    public var is_retailer: Bool?
    public var is_producer: Bool?
    public var is_restaurant: Bool?
    public var is_hospitality: Bool?
    public var is_event: Bool?
    public var is_verified: Bool?

    // MARK: - Defaults
    public var default_timezone: String?
    public var default_currency: String?
    public var default_badge_method: String?

    // MARK: - Misc numeric cutoffs
    public var num_dollar_signs_cutoff_1: Int?
    public var num_dollar_signs_cutoff_2: Int?
    public var num_dollar_signs_cutoff_3: Int?
    public var num_dollar_signs_cutoff_4: Int?
    public var num_dollar_signs_cutoff_5: Int?

    // MARK: - Foreign exchange
    public var currency_exchange_multiplier_from_foreign_to_usd: Double?

    // MARK: - Optional IDs
    public var featured_collection_id: Int?
    public var primary_inventory_id: Int?
    public var primary_questionnaire_id: Int?
    public var default_curation_batch_id: Int?
    public var default_curation_questions_batch_id: Int?
    public var max_number_of_venues: Int?

    // MARK: - Relationships
    /// JSON: primary_image { id, user_id, type, path }
    /// Use Media if you already map those image objects to Media.
    @Relationship(deleteRule: .nullify)
    public var primary_image: Media?

    /// JSON: images: [ { ... } ]
    @Relationship(deleteRule: .cascade)
    public var images: [Media] = []

    /// JSON: channel_venues: [ { id, venue, is_primary, archived } ]
    /// Join model (below) so you can preserve is_primary/archived per edge.
    @Relationship(deleteRule: .cascade, inverse: \ChannelVenue.channel)
    public var channel_venues: [ChannelVenue] = []


    // NOTE: available_collection_traits in your JSON looks like a different shape than Trait.
    // If you already have a SwiftData model for these, wire it up here.
    // Otherwise keep it DTO-only for now, or add a model later.

    // MARK: - Init
    public init(id: Int) {
        self.id = id
    }

    public init(
        id: Int,
        account_id: Int? = nil,
        name: String? = nil,
        description_text: String? = nil,
        order: Int? = nil,
        archived: Bool? = nil,
        published: Bool? = nil,
        default_display_vintages: Bool? = nil,
        default_display_variants: Bool? = nil,
        default_display_variant_details: Bool? = nil,
        default_display_price: Bool? = nil,
        default_display_quantity: Bool? = nil,
        default_display_bin: Bool? = nil,
        default_downweight_previous_recs_duration: Int? = nil,
        has_download_pdf: Bool? = nil,
        has_download_csv: Bool? = nil,
        has_download_xlsx: Bool? = nil,
        is_retailer: Bool? = nil,
        is_producer: Bool? = nil,
        is_restaurant: Bool? = nil,
        is_hospitality: Bool? = nil,
        is_event: Bool? = nil,
        is_verified: Bool? = nil,
        default_timezone: String? = nil,
        default_currency: String? = nil,
        default_badge_method: String? = nil,
        num_dollar_signs_cutoff_1: Int? = nil,
        num_dollar_signs_cutoff_2: Int? = nil,
        num_dollar_signs_cutoff_3: Int? = nil,
        num_dollar_signs_cutoff_4: Int? = nil,
        num_dollar_signs_cutoff_5: Int? = nil,
        currency_exchange_multiplier_from_foreign_to_usd: Double? = nil,
        featured_collection_id: Int? = nil,
        primary_inventory_id: Int? = nil,
        primary_questionnaire_id: Int? = nil,
        default_curation_batch_id: Int? = nil,
        default_curation_questions_batch_id: Int? = nil,
        max_number_of_venues: Int? = nil,
        primary_image: Media? = nil,
        images: [Media] = [],
        venues: [Venue] = [],
        primary_venues: [Venue] = [],
        channel_venues: [ChannelVenue] = [],
    ) {
        self.id = id
        self.account_id = account_id
        self.name = name
        self.description_text = description_text
        self.order = order
        self.archived = archived
        self.published = published

        self.default_display_vintages = default_display_vintages
        self.default_display_variants = default_display_variants
        self.default_display_variant_details = default_display_variant_details
        self.default_display_price = default_display_price
        self.default_display_quantity = default_display_quantity
        self.default_display_bin = default_display_bin
        self.default_downweight_previous_recs_duration = default_downweight_previous_recs_duration

        self.has_download_pdf = has_download_pdf
        self.has_download_csv = has_download_csv
        self.has_download_xlsx = has_download_xlsx

        self.is_retailer = is_retailer
        self.is_producer = is_producer
        self.is_restaurant = is_restaurant
        self.is_hospitality = is_hospitality
        self.is_event = is_event
        self.is_verified = is_verified

        self.default_timezone = default_timezone
        self.default_currency = default_currency
        self.default_badge_method = default_badge_method

        self.num_dollar_signs_cutoff_1 = num_dollar_signs_cutoff_1
        self.num_dollar_signs_cutoff_2 = num_dollar_signs_cutoff_2
        self.num_dollar_signs_cutoff_3 = num_dollar_signs_cutoff_3
        self.num_dollar_signs_cutoff_4 = num_dollar_signs_cutoff_4
        self.num_dollar_signs_cutoff_5 = num_dollar_signs_cutoff_5

        self.currency_exchange_multiplier_from_foreign_to_usd = currency_exchange_multiplier_from_foreign_to_usd

        self.featured_collection_id = featured_collection_id
        self.primary_inventory_id = primary_inventory_id
        self.primary_questionnaire_id = primary_questionnaire_id
        self.default_curation_batch_id = default_curation_batch_id
        self.default_curation_questions_batch_id = default_curation_questions_batch_id
        self.max_number_of_venues = max_number_of_venues

        self.primary_image = primary_image
        self.images = images
        self.channel_venues = channel_venues
    }

    // MARK: - Helpers
    public static func predicate(forID id: Int) -> Predicate<Channel> {
        #Predicate<Channel> { $0.id == id }
    }
}

/// Join model for JSON "channel_venues"
@Model
public final class ChannelVenue: HasIntID {
    public static func predicate(forID id: Int) -> Predicate<ChannelVenue> {
        #Predicate<ChannelVenue> { $0.id == id }
    }
    
    @Attribute(.unique) public var id: Int

    @Relationship(deleteRule: .nullify)
    public var channel: Channel?

    @Relationship(deleteRule: .nullify)
    public var venue: Venue?

    public var is_primary: Bool?
    public var archived: Bool?

    public init(id: Int) {
        self.id = id
    }

    public init(
        id: Int,
        channel: Channel? = nil,
        venue: Venue? = nil,
        is_primary: Bool? = nil,
        archived: Bool? = nil
    ) {
        self.id = id
        self.channel = channel
        self.venue = venue
        self.is_primary = is_primary
        self.archived = archived
    }
}
