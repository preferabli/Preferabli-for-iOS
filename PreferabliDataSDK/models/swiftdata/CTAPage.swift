import SwiftData
import Foundation

@Model
public final class CTAPage: Identifiable, HasIntID {

    @Attribute(.unique) public var id: Int

    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var slug: String?
    public var name: String?
    public var market_id: Int?
    public var affiliate_id: Int?

    
    // local only
    public var isTombstoned: Bool = false
    
    @Relationship(deleteRule: .cascade, inverse: \CTABucketAssociation.page) public var page_bucket_associations: [CTABucketAssociation]  = []

    public init(id: Int) {
        self.id = id
    }

    public static func predicate(forID id: Int) -> Predicate<CTAPage> {
        #Predicate<CTAPage> { $0.id == id }
    }
}
