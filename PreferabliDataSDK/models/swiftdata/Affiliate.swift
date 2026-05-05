//
//  Affiliate.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 4/30/26.
//

import Foundation
import SwiftData

@Model
public final class Affiliate: HasIntID, HasImage {
    @Attribute(.unique) public var id: Int

    public var affiliate_code: String?
    public var affiliate_param: String?
    public var affiliate_description: String?
    public var filter_visible: Bool?
    public var header_image_url: String?
    public var logo_image_url: String?
    public var market_id: Int?
    public var name: String?
    public var order: Int?
    public var slug: String?
    public var title: String?
    public var visible: Bool?

    @Relationship(inverse: \Experience.affiliates)
    public var experiences: [Experience] = []

    public init(id: Int) {
        self.id = id
    }

    public static func predicate(forID id: Int) -> Predicate<Affiliate> {
        #Predicate<Affiliate> { $0.id == id }
    }

    public func getImage(width: Int, height: Int, quality: Int = 80) -> URL? {
        PreferabliTools.getImageUrl(
            image: header_image_url,
            width: width,
            height: height,
            quality: quality
        )
    }

    public func getPlaceholderImage() -> String? {
        nil
    }
}
