//
//  VenueDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/14/25.
//

import Foundation

public struct VenueHourDTO: Decodable, Sendable {
    public let id: Int
    public let weekday: String?
    public let open_time: String?
    public let close_time: String?
    public let is_closed: Bool?
}

public struct DeliveryMethodDTO: Decodable, Sendable {
    public let id: Int
    public let shipping_type: String?
    public let state_abbreviation: String?
    public let state_display_name: String?
    public let country: String?
    public let shipping_cost_note: String?
    public let shipping_speed_note: String?
}

public struct VenueDTO: Decodable, Sendable {
    public let id: Int
    public let address_l1: String?
    public let address_l2: String?
    public let city: String?
    public let country: String?
    public let display_name: String?
    public let lat: Double?
    public let lon: Double?
    public let primary_inventory_id: Int?
    public let featured_collection_id: Int?
    public let is_virtual: Bool?
    public let name: String?
    public let phone: String?
    public let email_address: String?
    public let state: String?
    public let url: String?
    public let url_facebook: String?
    public let url_instagram: String?
    public let url_twitter: String?
    public let url_youtube: String?
    public let zip_code: String?
    public let notes: String?
    public let collections: [CollectionDTO]?
    public let active_delivery_methods: [DeliveryMethodDTO]?
    public let images: [MediaDTO]?
    public let hours: [VenueHourDTO]?
    public let lookups: [MerchantProductLink]?
    public let market_trait_associations: [VenueMarketTraitDTO]?
    public let video: MediaDTO?
    public let video_poster: MediaDTO?
    public let logo: MediaDTO?
    public let primary_image: MediaDTO?
    public let reservations_provider_enabled: Bool?
    public let is_partner: Bool?
    public let market_ids: [Int]?
}

public struct VenueMarketTraitDTO: Decodable, Sendable {
    public let order: Int?
    public let market_trait: MarketTraitDTO?
}


public extension VenueDTO {

    /// Normalized delivery methods derived from `active_delivery_methods`.
    var deliveryMethodTypes: Set<ShippingType> {
        let methods = active_delivery_methods ?? []
        return Set(methods.map { ShippingType.getShippingTypeBasedOffDatabaseName(value: $0.shipping_type) })
    }

    func has(_ type: ShippingType) -> Bool {
        deliveryMethodTypes.contains(type)
    }

    var hasShipping: Bool { has(.SHIPPING) }
    var hasLocalDelivery: Bool { has(.LOCAL_DELIVERY) }
    var hasPickup: Bool { has(.PICKUP) }
    var hasInPerson: Bool { has(.IN_PERSON) }

    /// Convenience: raw database names, if you ever need them.
    var shippingTypeDatabaseNames: Set<String> {
        Set((active_delivery_methods ?? []).compactMap(\.shipping_type))
    }

    // MARK: - Notes (mirrors Venue helpers)

    var shippingSpeedNote: String? {
        active_delivery_methods?
            .first(where: { ShippingType.getShippingTypeBasedOffDatabaseName(value: $0.shipping_type) == .SHIPPING })?
            .shipping_speed_note
    }

    var shippingCostNote: String? {
        active_delivery_methods?
            .first(where: { ShippingType.getShippingTypeBasedOffDatabaseName(value: $0.shipping_type) == .SHIPPING })?
            .shipping_cost_note
    }
    
    public func getCityState() -> String {
        if (city.isEmptyOrWhitespace && state.isEmptyOrWhitespace) {
            return ""
        } else if (city.isEmptyOrWhitespace) {
            return state ?? ""
        } else if (state.isEmptyOrWhitespace) {
            return city ?? ""
        } else {
            return (city ?? "") + ", " + (state ?? "")
        }
    }
}
