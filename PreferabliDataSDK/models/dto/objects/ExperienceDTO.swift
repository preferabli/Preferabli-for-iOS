//
//  ExperienceDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 1/26/26.
//

import Foundation

public struct ExperienceDTO: Decodable, Sendable {
    public let id: Int
    public let booking_link: String?
    public let booking_terms: String?
    public let brand_id: Int?
    public let preferabli_venue_id: Int?
    public let cuvee_experience: Bool?
    public let description: String?
    public let discount_code: String?
    public let duration: Int?
    public let experience_type: String?
    public let header_image_url: String?
    public let min_availability_notice_days: Int?
    public let name: String
    public let number_of_wines_poured: Int?
    public let order: Int?
    public let prepayment_required: Bool?
    public let price: Double?
    public let qualifier: Bool?
    public let qualifier_text: String?
    public let qualifier_title: String?
    public let reservation_api: String?
    public let reservation_notice: String?
    public let reservation_options: String?
    public let reservation_type: String?
    public let show_upgrade: Bool?
    public let stripe_product_id: String?
    public let terms_and_conditions: String?
    public let unit_label: String?
    public let upgrade_experience_id: Int?
    public let visible: Bool?
    public let wt_nft_id: Int?
    public let badge_title: String?
    public let badge_subtitle: String?
    public let badge_color: String?
    public let badge_text_color: String?
    public let cancellation_fee: String?
    public let primary_inventory_id: Int?
    public let reservations_provider: String?
    public let preferabli_image_url: String?

    public let experience_benefits: [ExperienceBenefitDTO]?
    public let operation_hours_normal: [ExperienceOperationHoursNormalDTO]?
    public let experience_prices: [ExperiencePriceDTO]?
    public let experience_types: [ExperienceTypeDTO]?

    enum CodingKeys: String, CodingKey {
        case id
        case booking_link
        case booking_terms
        case brand_id
        case preferabli_venue_id
        case cuvee_experience
        case description
        case discount_code
        case duration
        case experience_type
        case header_image_url
        case min_availability_notice_days
        case name
        case number_of_wines_poured
        case order
        case prepayment_required
        case price
        case qualifier
        case qualifier_text
        case qualifier_title
        case reservation_api
        case reservation_notice
        case reservation_options
        case reservation_type
        case show_upgrade
        case stripe_product_id
        case terms_and_conditions
        case unit_label
        case upgrade_experience_id
        case visible
        case wt_nft_id
        case reservations_provider
        case primary_inventory_id
        case cancellation_fee
        case badge_title
        case badge_subtitle
        case badge_color
        case badge_text_color
        case preferabli_image_url
        
        case experience_benefits = "benefits"
        case operation_hours_normal
        case experience_prices = "prices"
        case experience_types
    }
}

public struct ExperienceBenefitDTO: Decodable, Sendable {
    public let id: Int
    public let experience_id: Int?
    public let description: String?
    public let image_url: String?
    public let subtitle: String?
    public let title: String?

    enum CodingKeys: String, CodingKey {
        case id = "experience_benefits_id"
        case experience_id
        case description
        case image_url
        case subtitle
        case title
    }
}

public struct ExperienceOperationHoursNormalDTO: Decodable, Sendable {
    public let id: Int
    public let day_of_week: Int?
    public let end_times: [String]?
    public let experience_id: Int?
    public let increment: Int?
    public let start_times: [String]?
}

public struct ExperiencePriceDTO: Decodable, Sendable {
    public let id: Int
    public let active: Bool?
    public let age_range: String?
    public let experience_economics: String?
    public let experience_id: Int?
    public let experience_tier: String?
    public let guest_increment: Int?
    public let incentive_type_id: Int?
    public let list_price: Double?
    public let max_count: Int?
    public let min_count: Int?
    public let partner_ref: Int?
    public let price: Double?
    public let price_type: String?
    public let stripe_product_price_id: String?

    enum CodingKeys: String, CodingKey {
        case id = "experience_price_id"
        case active
        case age_range
        case experience_economics
        case experience_id
        case experience_tier
        case guest_increment
        case incentive_type_id
        case list_price
        case max_count
        case min_count
        case partner_ref
        case price
        case price_type
        case stripe_product_price_id
    }
}

public struct ExperienceTypeDTO: Decodable, Sendable {
    public let id: Int
    public let filter_order: Int?
    public let filter_visible: Bool?
    public let highlight: Bool?
    public let home_order: Int?
    public let home_visible: Bool?
    public let icon_url: String?
    public let image_url: String?
    public let market_id: Int?
    public let preferabli_market_trait_id: Int?
    public let name: String?
}
