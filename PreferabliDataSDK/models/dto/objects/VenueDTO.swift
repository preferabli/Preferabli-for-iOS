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
}
