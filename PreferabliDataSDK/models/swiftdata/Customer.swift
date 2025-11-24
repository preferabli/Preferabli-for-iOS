// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// A logged in merchant customer.
@Model
public final class Customer: HasIntID, HasTimestamps {
    
    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    var avatar_url: String?
    var merchant_user_email_address: String?
    var merchant_user_id: String?
    var merchant_user_name: String?
    var merchant_user_display_name: String?
    var role: String?
    var user_id: Int?
    var has_profile: Bool?
    var claim_code: String?
    var ratings_collection_id: Int?

    public init(id: Int) { self.id = id }

    init(id: Int, avatar_url: String? = nil, merchant_user_email_address: String? = nil, merchant_user_id: String? = nil, merchant_user_name: String? = nil, merchant_user_display_name: String? = nil, role: String? = nil, user_id: Int? = nil, has_profile: Bool? = nil, claim_code: String? = nil, ratings_collection_id: Int? = nil) {
        self.id = id
        self.avatar_url = avatar_url
        self.merchant_user_email_address = merchant_user_email_address
        self.merchant_user_id = merchant_user_id
        self.merchant_user_name = merchant_user_name
        self.merchant_user_display_name = merchant_user_display_name
        self.role = role
        self.user_id = user_id
        self.has_profile = has_profile
        self.claim_code = claim_code
        self.ratings_collection_id = ratings_collection_id
        Storage.getKeyStore().set(id, forKey: "customer_id")
        Storage.getKeyStore().set(merchant_user_email_address, forKey: "email")
        Storage.getKeyStore().set(ratings_collection_id, forKey: "ratings_id")
    }
    
    /// Get a customer's display name.
    /// - Returns: the name as a string.
    public func getName() -> String {
        if (merchant_user_display_name.isEmptyOrWhitespace) {
            return merchant_user_display_name!
        } else if (merchant_user_name.isEmptyOrWhitespace) {
            return merchant_user_name!
        } else if (merchant_user_email_address.isEmptyOrWhitespace) {
            return merchant_user_email_address!
        } else if (merchant_user_id.isEmptyOrWhitespace) {
            return merchant_user_id!
        }
        
        return ""
    }
    
    public static func predicate(forID id: Int) -> Predicate<Customer> {
        #Predicate<Customer> { $0.id == id }
    }
    
    /// Get the customer's  avatar.
    /// - Parameters:
    ///   - width: returns an image with the specified width in pixels.
    ///   - height: returns an image with the specified height in pixels.
    ///   - quality: returns an image with the specified quality. Scales from 0 - 100.
    /// - Returns: the URL of the requested image.
    public func getAvatar(width : Int, height : Int, quality : Int = 80) -> URL? {
        return PreferabliTools.getImageUrl(image: avatar_url, width: width, height: height, quality: quality)
    }
}
