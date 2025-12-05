//
//  GuidedRecResponseDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 12/1/25.
//

import Foundation

struct GuidedRecResponseDTO: Decodable {
    struct GuidedRecType: Decodable {
        let results: [GuidedRecItem]
        
        struct GuidedRecItem: Decodable {
            let formatted_predict_rating: Int?
            let variant_id: Int?
        }
    }
    let types: [GuidedRecType]
}
