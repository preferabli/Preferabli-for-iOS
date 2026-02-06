//
//  ExperienceDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 1/26/26.
//

import Foundation

public struct ExperienceDTO: Decodable, Sendable {
    public let id: Int

    public let created_at: Date?
    public let updated_at: Date?

    public let name: String?
    public let description: String?

    public let images: [MediaDTO]?

    public let primary_inventory_id: Int?

    public let reservations_provider: String?
    public let booking_link: String?
    public let discount_code: String?
}
