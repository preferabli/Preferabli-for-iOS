//
//  Recipe.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 3/9/26.
//


import Foundation
import SwiftData

@Model
public final class Recipe: HasIntID, HasTimestamps, HasImage {

    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var merchant_recipe_id: String?
    public var url: String?
    public var primary_image_url: String?
    public var desc: String?
    public var name: String?

    @Relationship(inverse: \RecipeGroup.recipes)
    public var recipe_groups: [RecipeGroup] = []
    @Relationship(deleteRule: .nullify) public var category: FoodCategory

    public init(id: Int, category : FoodCategory) {
        self.id = id
        self.category = category
    }

    public static func predicate(forID id: Int) -> Predicate<Recipe> {
        #Predicate<Recipe> { $0.id == id }
    }

    static public func sortRecipesAlpha(recipes: [Recipe]) -> [Recipe] {
        recipes.sorted {
            String.alphaSortIgnoreThe(x: $0.name, y: $1.name, comparisonResult: .orderedAscending)
        }
    }

    static public func filterRecipes(recipes: [Recipe], search_text: String) -> [Recipe] {
        if search_text.isEmptyOrWhitespace() {
            return recipes
        }

        let searchTerms = search_text.components(separatedBy: " ")
        return recipes.filter { recipe in
            for searchTerm in searchTerms {
                if !recipe.filterRecipe(search_term: searchTerm) {
                    return false
                }
            }
            return true
        }
    }

    public func getImage(width: Int, height: Int, quality: Int = 80) -> URL? {
        PreferabliTools.getImageUrl(image: primary_image_url, width: width, height: height, quality: quality)
    }

    public func getPlaceholderImage() -> String? {
        return nil
    }

    internal func filterRecipe(search_term: String) -> Bool {
        if search_term.isEmptyOrWhitespace() {
            return true
        } else if (name?.containsIgnoreCase(search_term) ?? false) {
            return true
        } else if (desc?.containsIgnoreCase(search_term) ?? false) {
            return true
        } else if (merchant_recipe_id?.containsIgnoreCase(search_term) ?? false) {
            return true
        } else if recipe_groups.contains(where: { $0.name?.containsIgnoreCase(search_term) ?? false }) {
            return true
        } else {
            return false
        }
    }
}
