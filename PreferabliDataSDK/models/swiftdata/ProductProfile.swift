// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// The profile data for a ``Product``.
@Model
public final class ProductProfile : HasIntID {
    
    @Attribute(.unique) public var id: Int

    public var refreshed_at: Date?

    // Traits
    public var trait1Name: String?
    public var trait2Name: String?
    public var trait3Name: String?
    public var trait4Name: String?

    public var trait1Level: Float?
    public var trait2Level: Float?
    public var trait3Level: Float?
    public var trait4Level: Float?

    // Flavors
    public var flavor1Name: String?
    public var flavor2Name: String?
    public var flavor3Name: String?
    public var flavor4Name: String?

    public var flavor1Image: String?
    public var flavor2Image: String?
    public var flavor3Image: String?
    public var flavor4Image: String?

    // Food categories
    public var food_category_1_name: String?
    public var food_category_2_name: String?
    public var food_category_3_name: String?
    public var food_category_4_name: String?

    public var food_category_1_icon_png_url: String?
    public var food_category_2_icon_png_url: String?
    public var food_category_3_icon_png_url: String?
    public var food_category_4_icon_png_url: String?

    // Relationships
    @Relationship(inverse: \Product.profile) var product: Product

    init(product : Product) {
        self.product = product
        self.id = product.id
    }
    
    public static func predicate(forID id: Int) -> Predicate<ProductProfile> {
        #Predicate<ProductProfile> { $0.id == id }
    }
    
    public func getFoodImage1() -> HasImage {
        return HasImageStruct(imageUrl: food_category_1_icon_png_url)
    }
    
    public func getFoodImage2() -> HasImage {
        return HasImageStruct(imageUrl: food_category_2_icon_png_url)
    }
    
    public func getFoodImage3() -> HasImage {
        return HasImageStruct(imageUrl: food_category_3_icon_png_url)
    }
    
    public func getFoodImage4() -> HasImage {
        return HasImageStruct(imageUrl: food_category_4_icon_png_url)
    }
}
