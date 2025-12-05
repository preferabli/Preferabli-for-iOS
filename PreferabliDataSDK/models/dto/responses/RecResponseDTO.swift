//
//  RecResponseDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 12/2/25.
//

import Foundation

struct RecResponseDTO: Decodable {
    struct RecResult: Decodable {
        let formatted_predict_rating: Int?
        let variant_id: Int
        let confidence_code: Int?
    }
    let results: [RecResult]
    let message: String?
}
