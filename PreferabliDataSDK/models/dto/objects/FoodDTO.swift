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
    public let food_category_id: Int?
    public let food_category_name: String?
    public let food_category_icon_svg_url: String?
    public let food_category_url: String?
    public let primary_image_url: String?
    public let description: String?
}

public struct FoodCategoryDTO: Decodable, Sendable {
    public let id: Int
    public let created_at: Date?
    public let updated_at: Date?
    public let name: String?
    public let icon_url: String?
    public let icon_svg_url: String?
}
