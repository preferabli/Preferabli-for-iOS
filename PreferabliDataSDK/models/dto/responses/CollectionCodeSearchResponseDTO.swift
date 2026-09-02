//
//  CollectionCodeSearchResponseDTO.swift
//  Preferabli
//

import Foundation

struct CollectionCodeSearchResponseDTO: Decodable {
    let collections: [CollectionDTO]

    private enum CodingKeys: String, CodingKey {
        case collections = "collections-by-code"
    }
}
