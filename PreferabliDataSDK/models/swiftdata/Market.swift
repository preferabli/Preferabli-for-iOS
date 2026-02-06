import SwiftData
import Foundation

@Model
public final class Market: Identifiable, HasIntID, HasTimestamps, HasImage {

    @Attribute(.unique) public var id: Int

    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var name: String?
    public var desc: String?
    public var image_url: String?
    public var latitude: Double?
    public var longitude: Double?
    public var order: Int?
    public var country_code: String?
    public var top_level: Bool?

    // ✅ Tree
    public var parent: Market?

    @Relationship(deleteRule: .cascade, inverse: \Market.parent)
    public var submarkets: [Market] = []

    // ✅ MarketTraits (join-ish table, but we store full trait payload here)
    @Relationship(deleteRule: .cascade, inverse: \MarketTrait.market)
    public var traits: [MarketTrait] = []
    
    public var venues: [Venue] = []

    public init(id: Int) { self.id = id }

    public static func predicate(forID id: Int) -> Predicate<Market> {
        #Predicate<Market> { $0.id == id }
    }

    public func getImage(width: Int, height: Int, quality: Int) -> URL? {
        PreferabliTools.getImageUrl(image: image_url, width: width, height: height, quality: quality)
    }

    public func getPlaceholderImage() -> String? { nil }
}
