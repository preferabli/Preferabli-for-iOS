//
//  CTABucketItemAssociation.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 6/24/26.
//


import SwiftData
import Foundation

@Model
public final class CTABucketItemAssociation: HasIntID, HasTimestamps {

    @Attribute(.unique) public var id: Int

    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    public var order: Int?

    @Relationship public var bucket: CTABucket
    @Relationship public var item: CTABucketItem

    public var isTombstoned: Bool = false

    public init(id: Int, bucket: CTABucket, item: CTABucketItem) {
        self.id = id
        self.bucket = bucket
        self.item = item
    }

    public static func predicate(forID id: Int) -> Predicate<CTABucketItemAssociation> {
        #Predicate<CTABucketItemAssociation> { $0.id == id }
    }
}
