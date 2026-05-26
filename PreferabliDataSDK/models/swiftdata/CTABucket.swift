import SwiftData
import Foundation

@Model
public final class CTABucket: Identifiable, HasIntID {

    @Attribute(.unique) public var id: Int

    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var order: Int?
    public var type: String?
    public var name: String?
    public var section: String?
    public var market_id: Int?
    public var affiliate_id: Int?
    public var item_height: Int?
    public var item_width: Int?
    public var item_corner_radius: Int?

    
    // local only
    public var isTombstoned: Bool = false
    
    @Relationship(deleteRule: .cascade) public var items: [CTABucketItem]  = []


    public init(id: Int) {
        self.id = id
    }

    public static func predicate(forID id: Int) -> Predicate<CTABucket> {
        #Predicate<CTABucket> { $0.id == id }
    }
}
