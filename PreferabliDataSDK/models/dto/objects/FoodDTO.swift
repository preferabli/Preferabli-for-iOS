//
//  FoodDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/14/25.
//

import Foundation

public struct FoodDTO: Decodable, Sendable {
    public let id: Int
    public let name: String?
    public let keywords: String?
    public let created_at: Date?
    public let updated_at: Date?
}

public struct FoodCategoryDTO: Decodable, Sendable {
    public let id: Int
    public let created_at: Date?
    public let updated_at: Date?
    public let name: String?
    public let icon_url: String?
}
