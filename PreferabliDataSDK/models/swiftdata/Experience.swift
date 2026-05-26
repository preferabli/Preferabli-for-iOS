//
//  Experience.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 4/3/26.
//


import Foundation
import SwiftData

@Model
public final class Experience: HasIntID, HasImage {
    @Attribute(.unique) public var id: Int

    public var booking_link: String?
    public var booking_terms: String?
    public var brand_id: Int?
    public var cuvee_experience: Bool?
    public var experience_description: String?
    public var discount_code: String?
    public var duration: Int?
    public var experience_type: String?
    public var header_image_url: String?
    public var min_availability_notice_days: Int?
    public var name: String
    public var number_of_wines_poured: Int?
    public var order: Int?
    public var prepayment_required: Bool?
    public var price: Double?
    public var qualifier: Bool?
    public var qualifier_text: String?
    public var qualifier_title: String?
    public var reservation_api: String?
    public var reservation_notice: String?
    public var reservation_options: String?
    public var reservation_type: String?
    public var show_upgrade: Bool?
    public var stripe_product_id: String?
    public var terms_and_conditions: String?
    public var unit_label: String?
    public var upgrade_experience_id: Int?
    public var visible: Bool?
    public var wt_nft_id: Int?
    
    // new from me
    public var badge_title: String?
    public var badge_subtitle: String?
    public var badge_color: String?
    public var badge_text_color: String?
    public var cancellation_fee: String?
    public var primary_inventory_id: Int?
    public var reservations_provider: String?
    public var preferabli_image_url: String?
    
    // local only
    public var isTombstoned: Bool = false
    public var isUnlocked: Bool = false

    
    // MARK: - Relationships

    @Relationship(deleteRule: .nullify)
    public var venue: Venue


    @Relationship(deleteRule: .cascade, inverse: \ExperienceBenefit.experience)
    public var benefits: [ExperienceBenefit] = []

    @Relationship(deleteRule: .cascade, inverse: \ExperienceOperationHoursNormal.experience)
    public var operation_hours_normals: [ExperienceOperationHoursNormal] = []

    @Relationship(deleteRule: .nullify, inverse: \ExperiencePrice.experience)
    public var prices: [ExperiencePrice] = []

    @Relationship(inverse: \ExperienceType.experiences)
    public var experience_types: [ExperienceType] = []
    
    @Relationship
    public var affiliates: [Affiliate] = []

    public init(id: Int, name: String, venue: Venue) {
        self.id = id
        self.name = name
        self.venue = venue
    }
    
    public static func predicate(forID id: Int) -> Predicate<Experience> {
        #Predicate<Experience> { $0.id == id }
    }
    
    public func getImage(width: Int, height: Int, quality: Int = 80) -> URL? {
        PreferabliTools.getImageUrl(image: preferabli_image_url ?? header_image_url ?? benefits.first?.image_url, width: width, height: height, quality: quality)
    }

    public func getPlaceholderImage() -> String? {
        nil
    }
}

@Model
public final class ExperienceBenefit: HasIntID {
    @Attribute(.unique) public var id: Int

    public var experience_id: Int?
    public var benefit_description: String?
    public var image_url: String?
    public var subtitle: String?
    public var title: String?
    
    public var experience: Experience?

    public init(id: Int) {
        self.id = id
    }
    
    public static func predicate(forID id: Int) -> Predicate<ExperienceBenefit> {
        #Predicate<ExperienceBenefit> { $0.id == id }
    }
}

@Model
public final class ExperienceOperationHoursNormal: HasIntID {
    @Attribute(.unique) public var id: Int

    public var day_of_week: Int?
    public var end_times: [String] = []
    public var experience_id: Int?
    public var increment: Int?
    public var start_times: [String] = []
    
    public var experience: Experience?

    public init(id: Int) {
        self.id = id
    }
    
    public static func predicate(forID id: Int) -> Predicate<ExperienceOperationHoursNormal> {
        #Predicate<ExperienceOperationHoursNormal> { $0.id == id }
    }
}

@Model
public final class ExperiencePrice: HasIntID {
    @Attribute(.unique) public var id: Int

    public var active: Bool?
    public var age_range: String?
    public var experience_economics: String?
    public var experience_id: Int?
    public var experience_tier: String?
    public var guest_increment: Int?
    public var incentive_type_id: Int?
    public var list_price: Double?
    public var max_count: Int?
    public var min_count: Int?
    public var partner_ref: Int?
    public var price: Double?
    public var price_type: String?
    public var stripe_product_price_id: String?
    public var price_on_request: Bool?
    
    public var experience: Experience?

    public init(id: Int) {
        self.id = id
    }
    
    public static func predicate(forID id: Int) -> Predicate<ExperiencePrice> {
        #Predicate<ExperiencePrice> { $0.id == id }
    }
}

@Model
public final class ExperienceType: HasIntID {
    @Attribute(.unique) public var id: Int

    public var filter_order: Int?
    public var filter_visible: Bool?
    public var highlight: Bool?
    public var home_order: Int?
    public var home_visible: Bool?
    public var icon_url: String?
    public var image_url: String?
    public var market_id: Int?
    public var preferabli_market_trait_id: Int?
    public var name: String?
    
    public var experiences: [Experience] = []

    public init(id: Int) {
        self.id = id
    }
    
    public static func predicate(forID id: Int) -> Predicate<ExperienceType> {
        #Predicate<ExperienceType> { $0.id == id }
    }
}
