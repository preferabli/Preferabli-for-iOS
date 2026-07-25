import SwiftData
import Foundation

@Model
public final class CTABucketItem: Identifiable, HasIntID, HasImage {

    @Attribute(.unique) public var id: Int

    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var is_centered: Bool?
    public var badge_icon: String?
    public var badge_color_hex_primary: String?
    public var badge_color_hex_secondary: String?
    public var color_hex_secondary: String?
    public var color_hex_primary: String?
    public var text_color_hex: String?
    public var gradient_css: String?
    public var badge_gradient_css: String?
    public var badge_text_color_hex: String?
    public var deeplink_url: String?
    public var badge_title: String?
    public var title: String?
    public var desc: String?
    public var half_gradient: Bool?
    public var badge_placement: String?
    
    @Relationship(deleteRule: .nullify) public var primary_image: Media?
    @Relationship(deleteRule: .nullify) public var sub_image_1: Media?
    @Relationship(deleteRule: .nullify) public var sub_image_2: Media?
    
    @Relationship(deleteRule: .cascade, inverse: \CTABucketItemAssociation.item)
    public var bucket_item_associations: [CTABucketItemAssociation] = []
    
    public init(id: Int) {
        self.id = id
    }

    public static func predicate(forID id: Int) -> Predicate<CTABucketItem> {
        #Predicate<CTABucketItem> { $0.id == id }
    }

    public func getImage(width: Int, height: Int, quality: Int) -> URL? {
        PreferabliTools.getImageUrl(media: primary_image, width: width, height: height, quality: quality)
    }

    public func getPlaceholderImage() -> String? { nil }
}
