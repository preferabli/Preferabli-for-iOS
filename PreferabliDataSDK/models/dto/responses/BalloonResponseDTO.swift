//
//  BalloonResponseDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 4/8/26.
//

import Foundation

struct BalloonResponseDTO: Decodable {
    let data: BalloonResponseDataDTO
    
    struct BalloonResponseDataDTO: Decodable {
        let booking: BalloonReservationDTO
    }
}
