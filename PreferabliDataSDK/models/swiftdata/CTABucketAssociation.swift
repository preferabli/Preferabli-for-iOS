//
//  CTABucketAssociation.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 6/2/26.
//


import SwiftData
import Foundation

@Model
public final class CTABucketAssociation: HasIntID, HasTimestamps {

    @Attribute(.unique) public var id: Int

    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var order: Int?
    
    @Relationship public var page: CTAPage
    @Relationship(deleteRule: .nullify, inverse: \CTABucket.bucket_associations) public var bucket: CTABucket
    
    // local only
    public var isTombstoned: Bool = false
    
    public init(id: Int, page: CTAPage, bucket: CTABucket) {
        self.id = id
        self.page = page
        self.bucket = bucket
    }

    public static func predicate(forID id: Int) -> Predicate<CTABucketAssociation> {
        #Predicate<CTABucketAssociation> { $0.id == id }
    }
}
