//
//  LocationDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/14/25.
//

import Foundation

public struct LocationDTO: Decodable, Sendable {
    public let id: Int
    public let created_at: Date?
    public let updated_at: Date?
    public let latitude: Double?
    public let longitude: Double?
    public let zip_code: String?
}
