//
//  ContentItem.swift
//  PreferabliDataSDK
//
//  SwiftData models for API /content and /personalities payloads.
//

import Foundation
import SwiftData

@Model
public final class ContentItem: HasIntID, HasTimestamps, HasImage {

    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var title: String?
    public var desc: String?
    public var episode_name: String?

    public var episode_order: Int?

    @Relationship(deleteRule: .nullify, inverse: \ContentItem.content_children)
    public var content_parent: ContentItem?

    @Relationship(deleteRule: .cascade)
    public var content_children: [ContentItem] = []

    @Relationship(deleteRule: .nullify)
    public var primary_media: Media?

    @Relationship(deleteRule: .cascade, inverse: \ContentPersonalityAssociation.content)
    public var personality_associations: [ContentPersonalityAssociation] = []

    @Relationship(deleteRule: .cascade, inverse: \ContentVariantAssociation.content)
    public var variant_associations: [ContentVariantAssociation] = []

//    @Relationship(deleteRule: .cascade, inverse: \ContentChannelAssociation.content)
//    public var channel_associations: [ContentChannelAssociation] = []

    @Relationship(deleteRule: .cascade, inverse: \ContentVenueAssociation.content)
    public var venue_associations: [ContentVenueAssociation] = []

    @Relationship(deleteRule: .cascade, inverse: \ContentExperienceAssociation.content)
    public var experience_associations: [ContentExperienceAssociation] = []

//    @Relationship(deleteRule: .cascade, inverse: \ContentMarketTraitAssociation.content)
//    public var market_traits_associations: [ContentMarketTraitAssociation] = []

    public init(id: Int) {
        self.id = id
    }

    public func getImage(width: Int, height: Int, quality: Int = 80) -> URL? {
        primary_media?.getImage(width: width, height: height, quality: quality)
    }

    public func getPlaceholderImage() -> String? {
        nil
    }

    public static func predicate(forID id: Int) -> Predicate<ContentItem> {
        #Predicate<ContentItem> { $0.id == id }
    }
}

@Model
public final class Personality: HasIntID, HasTimestamps, HasImage {

    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var name: String?
    public var desc: String?
    public var badge_title: String?
    public var badge_text_color_hex: String?
    public var badge_gradient_css: String?

    @Relationship(deleteRule: .nullify)
    public var primary_media: Media?

    @Relationship(deleteRule: .cascade, inverse: \ContentPersonalityAssociation.personality)
    public var content_associations: [ContentPersonalityAssociation] = []

    public init(id: Int) {
        self.id = id
    }

    public func getImage(width: Int, height: Int, quality: Int = 80) -> URL? {
        primary_media?.getImage(width: width, height: height, quality: quality)
    }

    public func getPlaceholderImage() -> String? {
        nil
    }

    public static func predicate(forID id: Int) -> Predicate<Personality> {
        #Predicate<Personality> { $0.id == id }
    }
}

@Model
public final class ContentPersonalityAssociation: HasIntID, HasTimestamps {

    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var content_id: Int?
    public var personality_id: Int?
    public var relationship: String?
    public var order: Int?

    @Relationship(deleteRule: .nullify)
    public var content: ContentItem?

    @Relationship(deleteRule: .nullify)
    public var personality: Personality?

    public init(id: Int, content: ContentItem? = nil, personality: Personality? = nil) {
        self.id = id
        self.content = content
        self.personality = personality
        self.content_id = content?.id
        self.personality_id = personality?.id
    }

    public static func predicate(forID id: Int) -> Predicate<ContentPersonalityAssociation> {
        #Predicate<ContentPersonalityAssociation> { $0.id == id }
    }
}

@Model
public final class ContentVariantAssociation: HasIntID, HasTimestamps {

    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var content_id: Int?
    public var product_id: Int?
    public var variant_id: Int?
    public var order: Int?

    // Legacy denormalized variant fields. Current content payloads send variants via products_cache,
    // so these fields are cleared while the association links to the upserted Variant by id.
    public var variant_year: Int?
    public var variant_price: Decimal?
    public var variant_num_dollar_signs: Int?
    public var variant_fresh: Bool?
    public var variant_recommendable: Bool?
    public var variant_deleted_on_curation: Bool?

    @Relationship(deleteRule: .nullify)
    public var content: ContentItem?

    @Relationship(deleteRule: .nullify)
    public var variant: Variant?

    @Relationship(deleteRule: .nullify)
    public var variant_primary_image: Media?

    @Relationship(deleteRule: .nullify)
    public var variant_images: [Media] = []

    public init(id: Int, content: ContentItem? = nil) {
        self.id = id
        self.content = content
        self.content_id = content?.id
    }

    public static func predicate(forID id: Int) -> Predicate<ContentVariantAssociation> {
        #Predicate<ContentVariantAssociation> { $0.id == id }
    }
}

@Model
public final class ContentChannelAssociation: HasIntID, HasTimestamps {

    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var content_id: Int?
    public var channel_id: Int?
    public var order: Int?

    @Relationship(deleteRule: .nullify)
    public var content: ContentItem?

    @Relationship(deleteRule: .nullify)
    public var channel: Channel?

    public init(id: Int, content: ContentItem? = nil) {
        self.id = id
        self.content = content
        self.content_id = content?.id
    }

    public static func predicate(forID id: Int) -> Predicate<ContentChannelAssociation> {
        #Predicate<ContentChannelAssociation> { $0.id == id }
    }
}

@Model
public final class ContentVenueAssociation: HasIntID, HasTimestamps {

    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var content_id: Int?
    public var venue_id: Int?
    public var order: Int?

    @Relationship(deleteRule: .nullify)
    public var content: ContentItem?

    @Relationship(deleteRule: .nullify)
    public var venue: Venue?

    public init(id: Int, content: ContentItem? = nil) {
        self.id = id
        self.content = content
        self.content_id = content?.id
    }

    public static func predicate(forID id: Int) -> Predicate<ContentVenueAssociation> {
        #Predicate<ContentVenueAssociation> { $0.id == id }
    }
}

@Model
public final class ContentExperienceAssociation: HasIntID, HasTimestamps {

    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var content_id: Int?
    public var experience_id: Int?
    public var order: Int?

    @Relationship(deleteRule: .nullify)
    public var content: ContentItem?

    @Relationship(deleteRule: .nullify)
    public var experience: Experience?

    public init(id: Int, content: ContentItem? = nil) {
        self.id = id
        self.content = content
        self.content_id = content?.id
    }

    public static func predicate(forID id: Int) -> Predicate<ContentExperienceAssociation> {
        #Predicate<ContentExperienceAssociation> { $0.id == id }
    }
}

@Model
public final class ContentMarketTraitAssociation: HasIntID, HasTimestamps {

    @Attribute(.unique) public var id: Int
    public var created_at: Date = Foundation.Date.now
    public var updated_at: Date = Foundation.Date.now

    public var content_id: Int?
    public var market_trait_id: Int?
    public var order: Int?

    @Relationship(deleteRule: .nullify)
    public var content: ContentItem?

    @Relationship(deleteRule: .nullify)
    public var market_trait: MarketTrait?

    public init(id: Int, content: ContentItem? = nil) {
        self.id = id
        self.content = content
        self.content_id = content?.id
    }

    public static func predicate(forID id: Int) -> Predicate<ContentMarketTraitAssociation> {
        #Predicate<ContentMarketTraitAssociation> { $0.id == id }
    }
}
