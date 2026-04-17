//
//  ReservationDTO.swift
//  PreferabliDataSDK
//
//  Created by Nicholas Bortolussi on 4/6/26.
//

import Foundation

public struct ReservationDTO: Decodable, Sendable {
    public let id: Int
    public let customer_slug: String?
    public let date: String?
    public let status: String?
    public let requested_times: [String]?
    public let times_available: [String]?

    public let brand: ReservationBrandDTO?
    public let experience: ReservationExperienceDTO?

    public let concierge_reservation_booking: ReservationBookingDTO?
    public let concierge_reservation_request_guests: [ReservationRequestGuestDTO]?

    enum CodingKeys: String, CodingKey {
        case id
        case customer_slug
        case date
        case status
        case requested_times
        case times_available
        case brand
        case experience
        case concierge_reservation_booking = "ConciergeReservationBooking"
        case concierge_reservation_request_guests = "ConciergeReservationRequestGuests"
    }
}

public struct ReservationBrandDTO: Decodable, Sendable {
    public let id: Int
    public let venue_id: Int?
    public let logo_image_url: String?
    public let name: String?

    enum CodingKeys: String, CodingKey {
        case id
        case venue_id = "preferabli_venue_id"
        case logo_image_url
        case name
    }
}

public struct ReservationExperienceDTO: Decodable, Sendable {
    public let id: Int
    public let header_image_url: String?
    public let name: String?
}

public struct ReservationBookingDTO: Decodable, Sendable {
    public let account_id: String?
    public let booking_confirmation_ref: String?
    public let booking_type: String?
    public let brand_id: Int?
    public let venue_id: Int?
    public let confirmed_time: String?
    public let created_on: String?
    public let updated_on: String?
    public let customer_slug: String?
    public let date: String?
    public let experience: ReservationExperienceDTO?
    public let experience_id: Int?
    public let id: Int?
    public let modification_link: String?
    public let payment_method_id: String?
    public let request_id: Int?
    public let specific_requests: String?
    public let status: String?
}

public struct ReservationRequestGuestDTO: Decodable, Sendable {
    public let experience_price: ReservationExperiencePriceDTO?
    public let concierge_reservation_request: Int?
    public let experience_price_id: Int?
    public let quantity: Int?

    enum CodingKeys: String, CodingKey {
        case experience_price = "ExperiencePrice"
        case concierge_reservation_request
        case experience_price_id
        case quantity
    }
}

public struct ReservationExperiencePriceDTO: Decodable, Sendable {
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
}
