//
//  ReservationDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/14/25.
//

import Foundation

public struct ReservationDTO: Decodable, Sendable {
    public let id: Int
    public let created_at: Date?
    public let updated_at: Date?
    public let region: String?
    public let date: Date?
    public let title: String?
    public let timeString: String?
    public let imageURLString: String?
}
