// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// A logged in Preferabli user. Most SDK installations will never use this.
@Model
public final class PreferabliUser : HasIntID, HasTimestamps {
    @Attribute(.unique) public var id: Int
    public var created_at: Date?
    public var updated_at: Date?
    public var country: String?
    public var display_name: String?
    public var email: String?
    public var is_team_preferabli: Bool?
    public var fname: String?
    public var lname: String?
    public var location: String?
    public var claim_code: String?
    public var has_merchant_access: Bool?
    public var has_kiosks: Bool?
    public var zip_code: String?
    public var intercom_hmac: String?
    public var rating_collection_id: Int?
    public var provided_feedback_at: Date?
    public var wishlist_collection_id: Int?
    
    @Relationship(deleteRule: .nullify) var avatar: Media?

    public init(id: Int) { self.id = id }

    init(id: Int, birthyear: Int? = nil, country: String? = nil, display_name: String? = nil, email: String? = nil, is_team_preferabli: Bool = false, fname: String? = nil, lname: String? = nil, location: String? = nil, claim_code: String? = nil, has_merchant_access: Bool = false, has_kiosks: Bool = false, zip_code: String? = nil, intercom_hmac: String? = nil, rating_collection_id: Int? = nil, provided_feedback_at: Date? = nil, wishlist_collection_id: Int? = nil, avatar: Media? = nil, created_at: Date? = nil, updated_at: Date? = nil) {
        self.country = country
        self.display_name = display_name
        self.email = email
        self.is_team_preferabli = is_team_preferabli
        self.fname = fname
        self.id = id
        self.lname = lname
        self.location = location
        self.claim_code = claim_code
        self.has_merchant_access = has_merchant_access
        self.has_kiosks = has_kiosks
        self.zip_code = zip_code
        self.intercom_hmac = intercom_hmac
        self.rating_collection_id = rating_collection_id
        self.provided_feedback_at = provided_feedback_at
        self.wishlist_collection_id = wishlist_collection_id
        self.avatar = avatar
        PreferabliTools.setUserProperties(user: self)
    }
    
    /// Get the user's avatar.
    /// - Parameters:
    ///   - width: returns an image with the specified width in pixels.
    ///   - height: returns an image with the specified height in pixels.
    ///   - quality: returns an image with the specified quality. Scales from 0 - 100.
    /// - Returns: the URL of the requested image.
    public func getAvatar(width : Float, height : Float, quality : Int = 80) -> URL? {
        return PreferabliTools.getImageUrl(image: avatar?.path, width: width, height: height, quality: quality)
    }
}
