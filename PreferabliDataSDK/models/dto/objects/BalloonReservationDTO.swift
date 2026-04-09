//
//  BalloonReservationDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 4/8/26.
//

import Foundation

public struct BalloonReservationDTO: Decodable, Sendable {
    public let id: String
    public let customer_email: String?
    public let customer_name: String?
    public let customer_phone: String?
    public let items: [BalloonReservationItemDTO]?

    enum CodingKeys: String, CodingKey {
        case id
        case customer_email
        case customer_name
        case customer_phone
        case items
    }
}

public struct BalloonReservationItemDTO: Decodable, Sendable {
    public let meeting_point: String?
    public let meeting_point_coordinates: String?
    public let qty: Int?
    public let sku: String?
    public let start_date: Int?

    enum CodingKeys: String, CodingKey {
        case meeting_point
        case meeting_point_coordinates
        case qty
        case sku
        case start_date
    }
}
