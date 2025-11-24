//
//  Reservation.swift
//  Tastefuli
//
//  Created by Nicholas Bortolussi on 8/27/25.
//

import Foundation
import SwiftData

@Model
final class Reservation: HasIntID, HasTimestamps {
    
    @Attribute(.unique) var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    public var region: String?
    public var date: Date?
    public var title: String?
    public var timeString: String?
    public var imageURLString: String?
    
    public init(id: Int) { self.id = id }

    // Convenience (non-persisted)
    var imageURL: URL? { imageURLString.flatMap(URL.init(string:)) }
    
    public static func predicate(forID id: Int) -> Predicate<Reservation> {
        #Predicate<Reservation> { $0.id == id }
    }
}
