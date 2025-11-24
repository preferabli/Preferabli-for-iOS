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
// One-time helper: a protocol only for models with Int ids
public protocol HasIntID: PersistentModel {
    var id: Int { get set }
    static func predicate(forID id: Int) -> Predicate<Self>
}


public extension HasIntID {
    /// True if the model has a server/DB id assigned.
    var hasValidID: Bool { id.isValidID() }
}

public protocol HasTombstone: PersistentModel {
    var isTombstoned: Bool { get set }
}

// Share timestamps across models without inheritance.
public protocol HasTimestamps {
    var created_at: Date { get set }
    var updated_at: Date { get set }
}

// Has image that we can grab.
public protocol HasImage {
    func getImage(width : Int, height : Int, quality : Int) -> URL?
    func getPlaceholderImage() -> String?
}

public struct HasImageStruct : HasImage {
    let imageUrl : String?
    init(imageUrl: String?) {
        self.imageUrl = imageUrl
    }
    
    public func getImage(width: Int, height: Int, quality: Int = 80) -> URL? {
        return PreferabliTools.getImageUrl(image: imageUrl, width: width, height: height, quality: quality)
    }
    
    public func getPlaceholderImage() -> String? {
        return nil
    }
}

// Don't need quality
public extension HasImage {
    // Convenience overload with your default
    func getImage(width: Int, height: Int, quality: Int = 80) -> URL? {
        // Optionally provide a shared implementation here,
        // or leave it to conformers and just keep the default arg.
        getImage(width: width, height: height, quality: quality)
    }
}

// Default helpers (no storage here).
public extension HasTimestamps {
    func getCreatedAt() -> Date { created_at ?? Date() }
    func getUpdatedAt() -> Date { updated_at ?? Date() }
}
