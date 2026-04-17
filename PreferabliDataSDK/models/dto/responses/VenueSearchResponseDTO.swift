//
//  VenueSearchResponseDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 11/17/25.
//

import Foundation

struct VenueSearchResponseDTO: Decodable {
    let venues: [VenueDTO]
}
