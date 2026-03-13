//
//  ProductRecipe.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 3/13/26.
//


import SwiftData
import Foundation

@Model
public final class ProductRecipe {

    @Attribute(.unique) public var key: String

    public var order: Int
    
    @Relationship(deleteRule: .nullify) public var recipe: Recipe
    @Relationship(inverse: \Product.recipes) public var product: Product

    public init(key: String, order: Int, recipe: Recipe, product: Product) {
        self.key = key
        self.order = order
        self.recipe = recipe
        self.product = product
    }
    
    public static func makeKey(order: Int, recipeId: Int, productId: Int) -> String {
        "order:\(order)|recipe:\(recipeId)|product:\(productId)"
    }
    
    public static func predicate(forKey key: String) -> Predicate<ProductRecipe> {
        #Predicate<ProductRecipe> { $0.key == key }
    }
}
