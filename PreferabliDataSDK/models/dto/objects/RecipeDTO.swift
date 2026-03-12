//
//  RecipeDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 3/9/26.
//

import Foundation

public struct RecipeDTO: Decodable, Sendable {
    public let id: Int
    public let merchant_recipe_id: String?
    public let url: String?
    public let primary_image_url: String?
    public let description: String?
    public let name: String?
    public let recipe_groups: [RecipeGroupDTO]?
    public let created_at: Date?
    public let updated_at: Date?
}

public struct RecipeGroupDTO: Decodable, Sendable {
    public let id: Int
    public let order: Int?
    public let internal_notes: String?
    public let type: String?
    public let icon_svg_url: String?
    public let primary_image: MediaDTO?
    public let name: String?
    public let created_at: Date?
    public let updated_at: Date?
}
