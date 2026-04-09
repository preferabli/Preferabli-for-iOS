//
//  Reservation.swift
//  PreferabliDataSDK
//
//  Created by Nicholas Bortolussi on 4/6/26.
//

import Foundation
import SwiftData

@Model
public final class Reservation: HasIntID {
    @Attribute(.unique) public var id: Int

    // MARK: - Top level request fields

    public var customer_slug: String?
    public var date: String?
    public var status: String?
    public var requested_times: [String] = []
    public var times_available: [String] = []

    // MARK: - Brand snapshot

    public var brand_id: Int?
    public var brand_name: String?
    public var brand_logo_image_url: String?

    // MARK: - Experience snapshot

    public var experience_id: Int?
    public var experience_name: String?
    public var experience_header_image_url: String?

    // MARK: - Booking snapshot

    public var booking_id: Int?
    public var booking_account_id: String?
    public var booking_confirmation_ref: String?
    public var booking_type: String?
    public var booking_brand_id: Int?
    public var booking_confirmed_time: String?
    public var booking_created_on: Date?
    public var booking_customer_slug: String?
    public var booking_date: String?
    public var booking_experience_id: Int?
    public var booking_modification_link: String?
    public var booking_payment_method_id: String?
    public var booking_request_id: Int?
    public var booking_specific_requests: String?
    public var booking_status: String?
    public var booking_updated_on: Date?

    // MARK: - Relationships

    @Relationship(deleteRule: .cascade)
    public var request_guests: [ReservationRequestGuest] = []

    public init(id: Int) {
        self.id = id
    }

    public static func predicate(forID id: Int) -> Predicate<Reservation> {
        #Predicate<Reservation> { $0.id == id }
    }
}

@Model
public final class ReservationRequestGuest {
    @Attribute(.unique) public var key: String

    public var reservation_id: Int?
    public var concierge_reservation_request: Int?
    public var experience_price_id: Int?
    public var quantity: Int?

    // MARK: - Price snapshot

    public var price_active: Bool?
    public var price_age_range: String?
    public var price_experience_economics: String?
    public var price_experience_id: Int?
    public var price_experience_tier: String?
    public var price_guest_increment: Int?
    public var price_incentive_type_id: Int?
    public var price_list_price: Double?
    public var price_max_count: Int?
    public var price_min_count: Int?
    public var price_partner_ref: Int?
    public var price_price: Double?
    public var price_price_type: String?
    public var price_stripe_product_price_id: String?

    public init(key: String) {
        self.key = key
    }

    public static func makeKey(
        reservationID: Int,
        experiencePriceID: Int?,
        index: Int
    ) -> String {
        "\(reservationID)_\(experiencePriceID ?? -1)_\(index)"
    }

    public static func predicate(forKey key: String) -> Predicate<ReservationRequestGuest> {
        #Predicate<ReservationRequestGuest> { $0.key == key }
    }
}
