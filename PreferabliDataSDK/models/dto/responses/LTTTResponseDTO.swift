//
//  LtttResponseDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/14/25.
//

import Foundation

struct LTTTResponseDTO: Decodable {
    struct Item: Decodable {
        let product: ProductDTO
        let formatted_predict_rating: Int?
    }
    let results: [Item]
}
