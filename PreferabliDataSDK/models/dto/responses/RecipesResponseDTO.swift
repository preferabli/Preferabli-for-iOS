//
//  RecipesResponseDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 3/13/26.
//

import Foundation

struct RecipesResponseDTO: Decodable {
    let title: String?
    let details: String?
    let recipes: [RecipeDTO]
}
