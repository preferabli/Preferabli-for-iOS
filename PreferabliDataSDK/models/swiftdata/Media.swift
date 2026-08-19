// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// An image or video.
@Model
public final class Media: HasIntID, HasTimestamps, HasImage {
    
    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    public var path: String?
    public var type: String?
    public var mime_type: String?
    
    @Relationship(deleteRule: .nullify, inverse: \Media.posterFor)
    public var poster: Media?

    @Relationship(deleteRule: .nullify)
    public var posterFor: [Media] = []

    // MARK: - Ownership inverses
    //
    // Media rows are shared by API identity. Keep a distinct inverse for each
    // semantic relationship so SwiftData can merge uniqueness conflicts
    // without having to infer which parent relationship owns the edge.
    @Relationship(deleteRule: .nullify, inverse: \PreferabliUser.avatar)
    public var avatarForUsers: [PreferabliUser] = []

    @Relationship(deleteRule: .nullify, inverse: \Variant.primary_image)
    public var primaryImageForVariants: [Variant] = []

    @Relationship(deleteRule: .nullify, inverse: \Product.primary_image)
    public var primaryImageForProducts: [Product] = []

    @Relationship(deleteRule: .nullify, inverse: \ContentItem.primary_media)
    public var primaryMediaForContentItems: [ContentItem] = []

    @Relationship(deleteRule: .nullify, inverse: \Personality.primary_media)
    public var primaryMediaForPersonalities: [Personality] = []

    @Relationship(deleteRule: .nullify, inverse: \ContentVariantAssociation.variant_primary_image)
    public var primaryImageForContentVariants: [ContentVariantAssociation] = []

    @Relationship(deleteRule: .nullify, inverse: \ContentVariantAssociation.variant_images)
    public var imagesForContentVariants: [ContentVariantAssociation] = []

    @Relationship(deleteRule: .nullify, inverse: \CTABucketItem.primary_image)
    public var primaryImageForCTABucketItems: [CTABucketItem] = []

    @Relationship(deleteRule: .nullify, inverse: \CTABucketItem.sub_image_1)
    public var firstSubImageForCTABucketItems: [CTABucketItem] = []

    @Relationship(deleteRule: .nullify, inverse: \CTABucketItem.sub_image_2)
    public var secondSubImageForCTABucketItems: [CTABucketItem] = []

    @Relationship(deleteRule: .nullify, inverse: \RecipeGroup.primary_image)
    public var primaryImageForRecipeGroups: [RecipeGroup] = []

    @Relationship(deleteRule: .nullify, inverse: \Collection.primary_image)
    public var primaryImageForCollections: [Collection] = []

    @Relationship(deleteRule: .nullify, inverse: \Venue.primary_image)
    public var primaryImageForVenues: [Venue] = []

    @Relationship(deleteRule: .nullify, inverse: \Venue.logo)
    public var logoForVenues: [Venue] = []

    @Relationship(deleteRule: .nullify, inverse: \Venue.video)
    public var videoForVenues: [Venue] = []

    @Relationship(deleteRule: .nullify, inverse: \Venue.images)
    public var imagesForVenues: [Venue] = []

    @Relationship(deleteRule: .nullify, inverse: \Channel.primary_image)
    public var primaryImageForChannels: [Channel] = []

    @Relationship(deleteRule: .nullify, inverse: \Channel.images)
    public var imagesForChannels: [Channel] = []

    @Relationship(deleteRule: .nullify, inverse: \Itinerary.primary_image)
    public var primaryImageForItineraries: [Itinerary] = []

    @Relationship(deleteRule: .nullify, inverse: \Itinerary.images)
    public var imagesForItineraries: [Itinerary] = []

    public init(id: Int) { self.id = id }
    
    /// Get the media's path for display as an image. Only use if the media is an image.
    /// - Parameters:
    ///   - width: returns an image with the specified width in pixels.
    ///   - height: returns an image with the specified height in pixels.
    ///   - quality: returns an image with the specified quality. Scales from 0 - 100.
    /// - Returns: the URL of the requested image.
    public func getImage(width : Int, height : Int, quality : Int = 80) -> URL? {
        return PreferabliTools.getImageUrl(media: self, width: width, height: height, quality: quality )
    }
    
    public func getPlaceholderImage() -> String? {
        return nil
    }
    
    public static func predicate(forID id: Int) -> Predicate<Media> {
        #Predicate<Media> { $0.id == id }
    }
}
