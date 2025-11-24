// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// Indicates a user's level of preference for a specific ``Product``.
@Model
public final class PreferenceData {
    
    public var title : String?
    public var details : String?
    public var refreshed_at: Date?
    
    /// How confident we are in our rating.
    public var confidence_code : Int?
    
    /// A score from 85 - 100 which informs us how likely a user is to enjoy a product. *Nil if the user will not like the product.*
    public var formatted_predict_rating : Int?
    
    // Relationships
    @Relationship(inverse: \Product.preference_data) var product: Product
    
    init(product : Product) {
        self.product = product
    }
    
    public func getPrediction() -> Prediction {
        let fullMessage = (title?.lowercased() ?? "") + "" + (details?.lowercased() ?? "")
        let score = formatted_predict_rating
        if (fullMessage.contains("yes") || (score != nil && score! > 85)) {
            if (score! > 93) {
                return .LOVE
            }
            return .LIKE
        } else if (fullMessage.contains("maybe") || fullMessage.contains("uh oh")) {
            return .MAYBE
        } else if (fullMessage.contains("already rated")) {
            return .ALREADY_RATED
        }
        
        return .DISLIKE
    }
}

public enum Prediction {
    /// A will love the product.
    case LOVE
    /// A user will like the product.
    case LIKE
    /// We are not sure about this one.
    case MAYBE
    /// A user will dislike the product.
    case DISLIKE
    /// User already rated the product.
    case ALREADY_RATED
    
}
