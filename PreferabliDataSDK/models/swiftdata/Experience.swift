//
//  Experience.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 1/26/26.
//

import Foundation
import SwiftData

@Model
public final class Experience: HasIntID, HasTimestamps, HasImage {

    @Attribute(.unique) public var id: Int

    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var name: String?
    public var desc: String?

    public var primary_inventory_id: Int?

    public var reservations_provider: String?
    public var booking_link: String?
    public var discount_code: String?

    // MARK: - Relationships
    @Relationship(deleteRule: .cascade) public var images: [Media] = []

    // Venue is required (mandatory relationship)
    @Relationship(deleteRule: .nullify) public var venue: Venue

    // MARK: - Init

    public init(id: Int, venue: Venue) {
        self.id = id
        self.venue = venue
    }

    public init(
        id: Int,
        created_at: Date = .now,
        updated_at: Date = .now,
        name: String? = nil,
        desc: String? = nil,
        images: [Media] = [],
        primary_inventory_id: Int? = nil,
        reservations_provider: String? = nil,
        booking_link: String? = nil,
        discount_code: String? = nil,
        venue: Venue
    ) {
        self.id = id
        self.created_at = created_at
        self.updated_at = updated_at
        self.name = name
        self.desc = desc
        self.images = images
        self.primary_inventory_id = primary_inventory_id
        self.reservations_provider = reservations_provider
        self.booking_link = booking_link
        self.discount_code = discount_code
        self.venue = venue
    }

    public static func predicate(forID id: Int) -> Predicate<Experience> {
        #Predicate<Experience> { $0.id == id }
    }

    // MARK: - HasImage

    public var primary_image: Media? { images.first }

    public func getImage(width: Int, height: Int, quality: Int = 80) -> URL? {
        PreferabliTools.getImageUrl(image: primary_image?.path, width: width, height: height, quality: quality)
    }

    public func getPlaceholderImage() -> String? {
        nil
    }
}
