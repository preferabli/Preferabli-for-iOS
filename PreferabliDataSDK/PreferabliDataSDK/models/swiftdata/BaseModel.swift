//
//  BaseModel.swift
//  PreferabliDataSDK
//
//  Created by Nicholas Bortolussi on 8/29/25.
//  Copyright © 2025 RingIT, Inc,. All rights reserved.
//

import SwiftData
import Foundation

// Every SwiftData model that has an Int id can conform to this.
// (Conformance is on the concrete @Model types.)
public protocol HasIntID: PersistentModel {
    var id: Int { get set }
}

// Share timestamps across models without inheritance.
public protocol HasTimestamps {
    var created_at: Date? { get set }
    var updated_at: Date? { get set }
}

// Default helpers (no storage here).
public extension HasTimestamps {
    func getCreatedAt() -> Date { created_at ?? Date() }
    func getUpdatedAt() -> Date { updated_at ?? Date() }
}
