// Converted from Core Data NSManagedObject on 2025-08-29 12:35:08
import Foundation
import SwiftData

/// Styles express how product characteristics synthesize in the context of human perception and define the nature of consumer taste preferences. These are *not* unique for each customer, which are represented as ``ProfileStyle``.
@Model
public final class Style: HasIntID, HasTimestamps, HasImage {

    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now
    public var desc: String?
    public var name: String?
    public var type: String?
    public var primary_image_url: String?
    public var product_category: String?

    // relationships
    @Relationship(deleteRule: .nullify) public var locations: [Location] = []
    @Relationship(deleteRule: .nullify) public var profile_styles: [ProfileStyle] = []
    
    public init(id: Int) { self.id = id }

    init(desc: String? = nil, id: Int, name: String? = nil, type: String? = nil, primary_image_url: String? = nil, product_category: String? = nil, locations: [Location] = []) {
        self.desc = desc
        self.id = id
        self.name = name
        self.type = type
        self.primary_image_url = primary_image_url
        self.product_category = product_category
        self.locations = locations
    }
    
    /// Get the style image.
    /// - Parameters:
    ///   - width: returns an image with the specified width in pixels.
    ///   - height: returns an image with the specified height in pixels.
    ///   - quality: returns an image with the specified quality. Scales from 0 - 100.
    /// - Returns: the URL of the requested image.
    public func getImage(width : Int, height : Int, quality : Int = 80) -> URL? {
        return PreferabliTools.getImageUrl(image: primary_image_url, width: width, height: height, quality: quality)
    }
    
    public func getPlaceholderImage() -> String? {
        return nil
    }
    
    public static func predicate(forID id: Int) -> Predicate<Style> {
        #Predicate<Style> { $0.id == id }
    }
    
    /// Get product type of the style.
    /// - Returns: ``ProductType`` of the style.
    public func getProductType() -> ProductType? {
         return ProductType.getProductTypeFromString(value: type)
    }
    
    /// Get product subcategory of the style.
    /// - Returns: ``ProductSubcategory`` of the style.
    public func getProductSubcategory() -> ProductSubcategory? {
       return ProductSubcategory.getProductSubcategoryFromString(value: type);
   }
    
    /// Get product category of the style.
    /// - Returns: ``ProductCategory`` of the style.
    public func getProductCategory() -> ProductCategory? {
       return ProductCategory.getProductCategoryFromString(value: product_category);
   }
}
