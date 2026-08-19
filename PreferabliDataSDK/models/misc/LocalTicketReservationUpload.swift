//
//  LocalTicketReservationUpload.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 8/13/26.
//


struct LocalTicketReservationUpload {
    let localId: Int
    let experienceId: Int
    let bookingConfirmationRef: String
    let groupLead: String?
    let meetingAddress: String?
    let date: String?
    let time: String?
    let guestCount: Int
    let completedSafetyBrief: Bool
}
