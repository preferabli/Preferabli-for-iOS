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
