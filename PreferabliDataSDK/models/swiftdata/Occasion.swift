//
//  Occasion.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 7/9/26.
//


import Foundation
import SwiftData

@Model
public final class Occasion {
    public var count: Int
    public var last_used: Date
    public var name: String

    public init(count: Int = 0, last_used: Date = Date(), name: String) {
        self.count = count
        self.last_used = last_used
        self.name = name
    }

    public static func sortOccasionsByLastUsed(occasions: [Occasion]) -> [Occasion] {
        occasions.sorted {
            if $0.last_used == $1.last_used {
                return $0.count > $1.count
            }
            return $0.last_used > $1.last_used
        }
    }
}
