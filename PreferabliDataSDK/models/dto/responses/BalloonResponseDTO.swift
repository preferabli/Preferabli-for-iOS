//
//  BalloonResponseDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 4/8/26.
//

import Foundation

struct BalloonResponseDTO: Decodable {
    let booking: BalloonReservationDTO
    let venue_id: Int?
    let experience_id: Int?
}
