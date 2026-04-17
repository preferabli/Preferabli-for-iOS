//
//  ReservationsResponseDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 4/15/26.
//

import Foundation

struct ReservationsResponseDTO: Decodable {
    let data: [ReservationDTO]
}
