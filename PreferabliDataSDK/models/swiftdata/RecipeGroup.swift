//
//  RecipeGroup.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 3/9/26.
//


import Foundation
import SwiftData

@Model
public final class RecipeGroup: HasIntID, HasTimestamps, HasImage {

    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var order: Int?
    public var internal_notes: String?
    public var name: String?
    public var icon_svg_url: String?
    public var type: String?

    @Relationship() public var recipes: [Recipe] = []
    @Relationship(deleteRule: .nullify) public var primary_image: Media?

    public init(id: Int) {
        self.id = id
    }

    public static func predicate(forID id: Int) -> Predicate<RecipeGroup> {
        #Predicate<RecipeGroup> { $0.id == id }
    }

    static public func sortRecipeGroups(groups: [RecipeGroup]) -> [RecipeGroup] {
        groups.sorted {
            if let lhs = $0.order, let rhs = $1.order, lhs != rhs {
                return lhs < rhs
            }
            return String.alphaSortIgnoreThe(x: $0.name, y: $1.name, comparisonResult: .orderedAscending)
        }
    }
    
    public func getImage(width: Int, height: Int, quality: Int = 80) -> URL? {
        PreferabliTools.getImageUrl(media: primary_image, width: width, height: height, quality: quality)
    }

    public func getPlaceholderImage() -> String? {
        return nil
    }
}
