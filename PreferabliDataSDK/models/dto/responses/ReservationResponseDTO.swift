//
//  ReservationResponseDTO.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 4/15/26.
//

import Foundation

struct ReservationResponseDTO: Decodable {
    let booking_id: Int
    let reservation_request_id: Int
}
