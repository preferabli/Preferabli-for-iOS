//
//  MediaDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/14/25.
//

import Foundation

public struct MediaDTO: Decodable, Sendable {
    public let id: Int
    public let path: String?
    public let created_at: Date?
    public let updated_at: Date?
    public let type: String?
}
