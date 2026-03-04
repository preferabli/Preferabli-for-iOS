import SwiftData
import Foundation

@Model
public final class CTABucket: Identifiable, HasIntID, HasImage {

    @Attribute(.unique) public var id: Int

    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var badge_icon: String?
    public var badge_color_primary: String?
    public var badge_color_secondary: String?
    public var order: Int?
    public var color_secondary: String?
    public var color_primary: String?
    public var deeplink_url: String?
    public var badge_title: String?
    public var title: String?
    public var desc: String?
    public var section: String
    public var market_id: Int?
    
    @Relationship(deleteRule: .nullify) public var primary_image: Media?

    public init(id: Int, section : String) {
        self.id = id
        self.section = section
    }

    public static func predicate(forID id: Int) -> Predicate<CTABucket> {
        #Predicate<CTABucket> { $0.id == id }
    }

    public func getImage(width: Int, height: Int, quality: Int) -> URL? {
        PreferabliTools.getImageUrl(image: primary_image?.path, width: width, height: height, quality: quality)
    }

    public func getPlaceholderImage() -> String? { nil }
}
