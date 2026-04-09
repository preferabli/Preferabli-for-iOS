//
//  BalloonReservation.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 4/8/26.
//


import SwiftData
import Foundation

@Model
public final class BalloonReservation: HasStringID {
    @Attribute(.unique) public var id: String

    public var customer_email: String?
    public var customer_name: String?
    public var customer_phone: String?

    @Relationship(deleteRule: .cascade)
    public var items: [BalloonReservationItem] = []

    public init(id: String) {
        self.id = id
    }

    public static func predicate(forID id: String) -> Predicate<BalloonReservation> {
        #Predicate<BalloonReservation> { $0.id == id }
    }
}


@Model
public final class BalloonReservationItem {
    public var meeting_point: String?
    public var meeting_point_coordinates: String?
    public var qty: Int?
    public var sku: String?
    public var start_date: Date?

    public init() {}
}
