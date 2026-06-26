//
//  Storage+DTOUpserts.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/14/25.
//

import Foundation
import SwiftData

// MARK: - Cancellation helpers
extension Storage {
    /// Upserts are always invoked inside `withBackgroundContext`, `withBackgroundContextAsync`, or `withContext`.
    /// Still, we must cooperate with Task cancellation because logout may be deleting the graph concurrently.
    @inline(__always)
    nonisolated static func checkCancelled() throws {
        try Task.checkCancellation()
    }

    /// Use right before *relationship setters* / collection replacements, which are the hottest crash points
    /// when instances have been invalidated by a wipe.
    @inline(__always)
    nonisolated static func checkCancelledBeforeRelationshipWrite() throws {
        try Task.checkCancellation()
    }
}

extension Storage {

    // MARK: Product

    @discardableResult
    nonisolated static func upsertProduct(from dto: ProductDTO, tempProductId: Int? = nil, in ctx: ModelContext) throws -> Product {

        try checkCancelled()

        let product: Product
        if let pid = tempProductId, let temp = try Storage.fetchById(Product.self, id: pid, in: ctx) {
            product = temp
            product.id = dto.id
        } else {
            product = try fetchOrInsert(Product.self, id: dto.id, in: ctx) { Product(id: dto.id) }
        }

        try checkCancelled()

        product.name = dto.name
        product.created_at = dto.created_at ?? product.created_at
        product.updated_at = dto.updated_at ?? product.updated_at
        product.brand = dto.brand
        product.decant = dto.decant
        product.grape = dto.grape
        product.brand_lat = dto.brand_lat
        product.brand_lon = dto.brand_lon
        product.show_year_dropdown = dto.show_year_dropdown
        product.recommendable = dto.recommendable
        product.region = dto.region
        product.type = dto.type
        product.category = dto.category
        product.subcategory = dto.subcategory
        product.brand_id = dto.brand_id
        product.product_hash = dto.hash
        product.country_code = dto.country_code

        // Primary image
        if let imgDTO = dto.primary_image {
            try checkCancelled()
            let media = try upsertMedia(from: imgDTO, in: ctx)

            try checkCancelledBeforeRelationshipWrite()
            if product.primary_image !== media {
                product.primary_image = media
            }
        }

        // Variants
        var mostRecentYear = -2
        product.cachedMostRecentVariant = nil
        
        if let vDTOs = dto.variants {
            for vDTO in vDTOs {
                try checkCancelled()
                let variant = try upsertVariant(from: vDTO, product: product, in: ctx)
                if variant.year > mostRecentYear {
                    mostRecentYear = variant.year

                    try checkCancelledBeforeRelationshipWrite()
                    product.cachedMostRecentVariant = variant
                }
            }
        }

        if let latest = dto.latest_variant_num_dollar_signs, latest != 0 {
            if try fetchAnyVariant(productId: product.id, in: ctx) == nil {
                try checkCancelled()

                let variant = Variant(
                    id: generateRandomLongId(),
                    year: Variant.CURRENT_VARIANT_YEAR,
                    product: product
                )
                variant.num_dollar_signs = latest
                variant.isTombstoned = false

                ctx.insert(variant)

                try checkCancelledBeforeRelationshipWrite()
                product.cachedMostRecentVariant = variant
            }
        }

        return product
    }
    
    nonisolated static func fetchVariant(
        productId: Int,
        year: Int,
        in ctx: ModelContext
    ) throws -> Variant? {
        var fd = FetchDescriptor<Variant>(
            predicate: #Predicate<Variant> {
                $0.product.id == productId &&
                $0.year == year &&
                $0.isTombstoned == false
            },
            sortBy: [
                SortDescriptor(\Variant.id, order: .reverse)
            ]
        )
        fd.fetchLimit = 1
        return try ctx.fetch(fd).first
    }

    nonisolated static func fetchAnyVariant(
        productId: Int,
        in ctx: ModelContext
    ) throws -> Variant? {
        var fd = FetchDescriptor<Variant>(
            predicate: #Predicate<Variant> {
                $0.product.id == productId &&
                $0.isTombstoned == false
            }
        )
        fd.fetchLimit = 1
        return try ctx.fetch(fd).first
    }

    // MARK: ProductProfile

    @discardableResult
    nonisolated static func upsertProductProfile(
        from dto: ProductProfileDTO,
        for product: Product,
        in ctx: ModelContext
    ) throws -> ProductProfile {

        try checkCancelled()

        let profile = try fetchOrInsert(ProductProfile.self, id: product.id, in: ctx) { ProductProfile(product: product) }

        try checkCancelledBeforeRelationshipWrite()
        profile.product = product
        if product.profile !== profile {
            product.profile = profile
        }

        try checkCancelled()

        profile.refreshed_at = Date()
        profile.trait1Name  = dto.trait1Name
        profile.trait2Name  = dto.trait2Name
        profile.trait3Name  = dto.trait3Name
        profile.trait4Name  = dto.trait4Name
        profile.trait1Level = dto.trait1Level
        profile.trait2Level = dto.trait2Level
        profile.trait3Level = dto.trait3Level
        profile.trait4Level = dto.trait4Level
        profile.flavor1Name = dto.flavor1Name
        profile.flavor2Name = dto.flavor2Name
        profile.flavor3Name = dto.flavor3Name
        profile.flavor4Name = dto.flavor4Name
        profile.flavor1Image = dto.flavor1Image
        profile.flavor2Image = dto.flavor2Image
        profile.flavor3Image = dto.flavor3Image
        profile.flavor4Image = dto.flavor4Image
        profile.food_category_1_name         = dto.food_category_1_name
        profile.food_category_2_name         = dto.food_category_2_name
        profile.food_category_3_name         = dto.food_category_3_name
        profile.food_category_4_name         = dto.food_category_4_name
        profile.food_category_1_icon_png_url = dto.food_category_1_icon_png_url
        profile.food_category_2_icon_png_url = dto.food_category_2_icon_png_url
        profile.food_category_3_icon_png_url = dto.food_category_3_icon_png_url
        profile.food_category_4_icon_png_url = dto.food_category_4_icon_png_url

        return profile
    }

    @discardableResult
    nonisolated static func upsertPreferenceData(
        from dto: PreferenceDataDTO,
        for product: Product,
        in ctx: ModelContext
    ) throws -> PreferenceData {

        try checkCancelled()

        var preference_data = product.preference_data
        if preference_data == nil {
            let created = PreferenceData(product: product)

            try checkCancelledBeforeRelationshipWrite()
            product.preference_data = created

            ctx.insert(created)
            preference_data = created
        }

        let data = preference_data!

        try checkCancelled()

        data.refreshed_at = Date()
        data.title  = dto.title
        data.confidence_code = dto.confidence_code
        data.details = dto.details
        data.formatted_predict_rating = dto.formatted_predict_rating

        return data
    }

    // MARK: Variant

    @discardableResult
    nonisolated static func upsertVariant(
        from dto: VariantDTO,
        product: Product,
        in ctx: ModelContext
    ) throws -> Variant {

        try checkCancelled()

        let v: Variant

        if let existing = try fetchById(Variant.self, id: dto.id, in: ctx) {
            v = existing
        } else if dto.id > 0,
                  let temp = try fetchTempVariant(
                      productId: product.id,
                      year: dto.year,
                      in: ctx
                  ) {
            v = temp
            v.id = dto.id
        } else {
            v = Variant(id: dto.id, year: dto.year, product: product)
            ctx.insert(v)
        }

        v.year = dto.year

        try checkCancelledBeforeRelationshipWrite()
        v.product = product

        v.created_at = dto.created_at ?? v.created_at
        v.updated_at = dto.updated_at ?? v.updated_at
        v.num_dollar_signs = dto.num_dollar_signs ?? v.num_dollar_signs
        v.price = dto.price ?? v.price
        v.recommendable = dto.recommendable ?? v.recommendable
        v.isTombstoned = false

        if let imgDTO = dto.primary_image {
            let media = try upsertMedia(from: imgDTO, in: ctx)
            if v.primary_image !== media {
                v.primary_image = media
            }
        }

        return v
    }
    
    private nonisolated static func fetchTempVariant(
        productId: Int,
        year: Int,
        in ctx: ModelContext
    ) throws -> Variant? {
        var fd = FetchDescriptor<Variant>(
            predicate: #Predicate<Variant> {
                $0.product.id == productId &&
                $0.year == year &&
                $0.id < 0 &&
                $0.isTombstoned == false
            }
        )
        fd.fetchLimit = 1
        return try ctx.fetch(fd).first
    }

    // MARK: Tag

    @discardableResult
    nonisolated static func upsertTag(from dto: TagDTO, variant: Variant, tempTagId: Int? = nil, in ctx: ModelContext) throws -> Tag {

        try checkCancelled()

        let t: Tag
        if let tid = tempTagId, let temp = try Storage.fetchById(Tag.self, id: tid, in: ctx) {
            t = temp
            t.id = dto.id
        } else {
            t = try fetchOrInsert(Tag.self, id: dto.id, in: ctx) { Tag(id: dto.id, collection_id: dto.collection_id, variant: variant) }
        }

        try checkCancelled()

        t.collection_id = dto.collection_id ?? t.collection_id
        t.comment = dto.comment ?? t.comment
        t.created_at = dto.created_at ?? t.created_at
        t.location = dto.location ?? t.location
        t.badge = dto.badge ?? t.badge
        t.tagged_in_collection_id = dto.tagged_in_collection_id ?? t.tagged_in_collection_id
        t.tagged_in_channel_id = dto.tagged_in_channel_id ?? t.tagged_in_channel_id
        t.tagged_in_channel_name = dto.tagged_in_channel_name ?? t.tagged_in_channel_name
        t.type = dto.type ?? t.type
        t.updated_at = dto.updated_at ?? t.updated_at
        t.user_id = dto.user_id ?? t.user_id
        t.value = dto.value ?? t.value
        t.bin = dto.bin ?? t.bin
        t.variant_id = dto.variant_id ?? t.variant_id
        t.quantity = dto.quantity ?? t.quantity
        t.format_ml = dto.format_ml ?? t.format_ml
        t.price = dto.price ?? t.price
        t.customer_id = dto.customer_id ?? t.customer_id

        let product = variant.product
        let newDate = t.created_at ?? .now

        // These are just pointer assignments but still relationship-ish cached refs.
        try checkCancelledBeforeRelationshipWrite()

        if t.isRating() {
            let currentDate = product.cachedMostRecentRating?.created_at ?? .distantPast
            if newDate >= currentDate {
                product.cachedMostRecentRating = t
            }
        } else if t.isWishlist() {
            let currentDate = product.cachedWishlist?.created_at ?? .distantPast
            if newDate >= currentDate {
                product.cachedWishlist = t
            }
        } else if t.tag_type == .COLLECTION, Storage.isCellarCollectionID(t.collection_id) {
            let currentDate = product.cachedCellar?.created_at ?? .distantPast
            if newDate >= currentDate {
                product.cachedCellar = t
            }
        }

        return t
    }

    // MARK: Media

    @discardableResult
    nonisolated static func upsertMedia(from dto: MediaDTO, in ctx: ModelContext) throws -> Media {
        try checkCancelled()

        let m = try fetchOrInsert(Media.self, id: dto.id, in: ctx) {
            Media(id: dto.id)
        }

        m.id = dto.id
        m.path = dto.path ?? m.path
        m.type = dto.type ?? m.type
        m.mime_type = dto.mime_type ?? m.mime_type

        if let posterDTO = dto.poster {
            try checkCancelled()

            // Do not allow a Media row to point to itself as its poster.
            guard posterDTO.id != dto.id else {
                try checkCancelledBeforeRelationshipWrite()
                m.poster = nil
                return m
            }

            let poster = try upsertInternalMedia(from: posterDTO, in: ctx)

            try checkCancelledBeforeRelationshipWrite()

            // Do NOT use `m.poster !== poster` here.
            // Accessing `m.poster` can fault stale/future backing data.
            m.poster = poster
        } else {
            try checkCancelledBeforeRelationshipWrite()
            m.poster = nil
        }

        return m
    }
    
    @discardableResult
    nonisolated static func upsertInternalMedia(from dto: InternalMediaDTO, in ctx: ModelContext) throws -> Media {

        try checkCancelled()

        let m = try fetchOrInsert(Media.self, id: dto.id, in: ctx) { Media(id: dto.id) }
        m.id = dto.id
        m.path = dto.path ?? m.path
        m.type = dto.type ?? m.type
        m.mime_type = dto.mime_type ?? m.mime_type
        
        return m
    }
    
    @discardableResult
    nonisolated static func upsertAffiliate(
        from dto: AffiliateDTO,
        in ctx: ModelContext
    ) throws -> Affiliate? {

        try checkCancelled()

        let affiliate = try fetchOrInsert(Affiliate.self, id: dto.id, in: ctx) {
            Affiliate(id: dto.id)
        }

        affiliate.affiliate_code = dto.affiliate_code ?? affiliate.affiliate_code
        affiliate.affiliate_param = dto.affiliate_param ?? affiliate.affiliate_param
        affiliate.affiliate_description = dto.description ?? affiliate.affiliate_description
        affiliate.filter_visible = dto.filter_visible ?? affiliate.filter_visible
        affiliate.header_image_url = dto.header_image_url ?? affiliate.header_image_url
        affiliate.logo_image_url = dto.logo_image_url ?? affiliate.logo_image_url
        affiliate.market_id = dto.market_id ?? affiliate.market_id
        affiliate.name = dto.name ?? affiliate.name
        affiliate.order = dto.order ?? affiliate.order
        affiliate.slug = dto.slug ?? affiliate.slug
        affiliate.title = dto.title ?? affiliate.title
        affiliate.visible = dto.visible ?? affiliate.visible

        if let experienceDTOs = dto.experiences {
            var newExperiences: [Experience] = []
            newExperiences.reserveCapacity(experienceDTOs.count)

            for experienceDTO in experienceDTOs {
                try checkCancelled()

                guard
                    let venueID = experienceDTO.preferabli_venue_id,
                    let venue = try Storage.fetchById(Venue.self, id: venueID, in: ctx)
                else {
                    continue
                }

                let experience = try upsertExperience(
                    from: experienceDTO,
                    venue: venue,
                    in: ctx
                )
                experience.isUnlocked = true

                newExperiences.append(experience)
            }

            try checkCancelledBeforeRelationshipWrite()
            affiliate.experiences = newExperiences
        }

        return affiliate
    }

    @discardableResult
    nonisolated static func upsertExperience(
        from dto: ExperienceDTO,
        venue: Venue,
        in ctx: ModelContext
    ) throws -> Experience {

        try checkCancelled()

        let experience = try fetchOrInsert(Experience.self, id: dto.id, in: ctx) {
            Experience(id: dto.id, name: dto.name, venue: venue)
        }

        try checkCancelled()

        experience.id = dto.id
        experience.name = dto.name

        experience.booking_link = dto.booking_link ?? experience.booking_link
        experience.booking_terms = dto.booking_terms ?? experience.booking_terms
        experience.brand_id = dto.brand_id ?? experience.brand_id
        experience.cuvee_experience = dto.cuvee_experience ?? experience.cuvee_experience
        experience.experience_description = dto.description ?? experience.experience_description
        experience.discount_code = dto.discount_code ?? experience.discount_code
        experience.duration = dto.duration ?? experience.duration
        experience.experience_type = dto.experience_type ?? experience.experience_type
        experience.header_image_url = dto.header_image_url ?? experience.header_image_url
        experience.min_availability_notice_days = dto.min_availability_notice_days ?? experience.min_availability_notice_days
        experience.number_of_wines_poured = dto.number_of_wines_poured ?? experience.number_of_wines_poured
        experience.order = dto.order ?? experience.order
        experience.prepayment_required = dto.prepayment_required ?? experience.prepayment_required
        experience.price = dto.price ?? experience.price
        experience.qualifier = dto.qualifier ?? experience.qualifier
        experience.qualifier_text = dto.qualifier_text ?? experience.qualifier_text
        experience.qualifier_title = dto.qualifier_title ?? experience.qualifier_title
        experience.reservation_api = dto.reservation_api ?? experience.reservation_api
        experience.reservation_notice = dto.reservation_notice ?? experience.reservation_notice
        experience.reservation_options = dto.reservation_options ?? experience.reservation_options
        experience.reservation_type = dto.reservation_type ?? experience.reservation_type
        experience.show_upgrade = dto.show_upgrade ?? experience.show_upgrade
        experience.stripe_product_id = dto.stripe_product_id ?? experience.stripe_product_id
        experience.terms_and_conditions = dto.terms_and_conditions ?? experience.terms_and_conditions
        experience.unit_label = dto.unit_label ?? experience.unit_label
        experience.upgrade_experience_id = dto.upgrade_experience_id ?? experience.upgrade_experience_id
        experience.visible = dto.visible ?? experience.visible
        experience.wt_nft_id = dto.wt_nft_id ?? experience.wt_nft_id
        experience.reservations_provider = dto.reservations_provider ?? experience.reservations_provider
        experience.cancellation_fee = dto.cancellation_fee ?? experience.cancellation_fee
        experience.badge_title = dto.badge_title ?? experience.badge_title
        experience.badge_subtitle = dto.badge_subtitle ?? experience.badge_subtitle
        experience.badge_color_hex = dto.badge_color_hex ?? experience.badge_color_hex
        experience.badge_text_color_hex = dto.badge_text_color_hex ?? experience.badge_text_color_hex
        experience.badge_gradient_css = dto.badge_gradient_css ?? experience.badge_gradient_css
        experience.primary_inventory_id = dto.primary_inventory_id ?? experience.primary_inventory_id
        experience.preferabli_image_url = dto.preferabli_image_url ?? experience.preferabli_image_url
        experience.is_booking_link_external = dto.is_booking_link_external ?? experience.is_booking_link_external
        
        // inside Storage.upsertExperience(...)
        if experience.isTombstoned {
            experience.isTombstoned = false
        }

        try checkCancelledBeforeRelationshipWrite()
        if experience.venue.id != venue.id {
            experience.venue = venue
        }

        // MARK: Benefits
        if let benefitDTOs = dto.experience_benefits {
            var newBenefits: [ExperienceBenefit] = []
            newBenefits.reserveCapacity(benefitDTOs.count)

            for benefitDTO in benefitDTOs {
                try checkCancelled()
                let benefit = try upsertExperienceBenefit(from: benefitDTO, experience: experience, in: ctx)
                newBenefits.append(benefit)
            }

            try checkCancelledBeforeRelationshipWrite()
            experience.benefits = newBenefits
        }

        // MARK: Operation Hours Normals
        if let hourDTOs = dto.operation_hours_normal {
            var newHours: [ExperienceOperationHoursNormal] = []
            newHours.reserveCapacity(hourDTOs.count)

            for hourDTO in hourDTOs {
                try checkCancelled()
                let hour = try upsertExperienceOperationHoursNormal(from: hourDTO, experience: experience, in: ctx)
                newHours.append(hour)
            }

            try checkCancelledBeforeRelationshipWrite()
            experience.operation_hours_normals = newHours
        }

        // MARK: Prices
        if let priceDTOs = dto.experience_prices {
            var newPrices: [ExperiencePrice] = []
            newPrices.reserveCapacity(priceDTOs.count)

            for priceDTO in priceDTOs {
                try checkCancelled()
                let price = try upsertExperiencePrice(from: priceDTO, experience: experience, in: ctx)
                newPrices.append(price)
            }

            try checkCancelledBeforeRelationshipWrite()
            experience.prices = newPrices
        }

        // MARK: Types
        if let typeDTOs = dto.experience_types {
            var newTypes: [ExperienceType] = []
            newTypes.reserveCapacity(typeDTOs.count)

            for typeDTO in typeDTOs {
                try checkCancelled()
                let type = try upsertExperienceType(from: typeDTO, experience: experience, in: ctx)
                newTypes.append(type)
            }

            try checkCancelledBeforeRelationshipWrite()
            experience.experience_types = newTypes
        }

        return experience
    }

    @discardableResult
    nonisolated static func upsertExperienceBenefit(
        from dto: ExperienceBenefitDTO,
        experience: Experience,
        in ctx: ModelContext
    ) throws -> ExperienceBenefit {

        try checkCancelled()

        let benefit = try fetchOrInsert(ExperienceBenefit.self, id: dto.id, in: ctx) {
            ExperienceBenefit(id: dto.id)
        }

        benefit.id = dto.id
        benefit.experience_id = dto.experience_id ?? experience.id
        benefit.benefit_description = dto.description ?? benefit.benefit_description
        benefit.image_url = dto.image_url ?? benefit.image_url
        benefit.subtitle = dto.subtitle ?? benefit.subtitle
        benefit.title = dto.title ?? benefit.title

        return benefit
    }

    @discardableResult
    nonisolated static func upsertExperienceOperationHoursNormal(
        from dto: ExperienceOperationHoursNormalDTO,
        experience: Experience,
        in ctx: ModelContext
    ) throws -> ExperienceOperationHoursNormal {

        try checkCancelled()

        let hours = try fetchOrInsert(ExperienceOperationHoursNormal.self, id: dto.id, in: ctx) {
            ExperienceOperationHoursNormal(id: dto.id)
        }

        hours.id = dto.id
        hours.day_of_week = dto.day_of_week ?? hours.day_of_week
        hours.end_times = dto.end_times ?? hours.end_times
        hours.experience_id = dto.experience_id ?? experience.id
        hours.increment = dto.increment ?? hours.increment
        hours.start_times = dto.start_times ?? hours.start_times

        return hours
    }

    @discardableResult
    nonisolated static func upsertExperiencePrice(
        from dto: ExperiencePriceDTO,
        experience: Experience,
        in ctx: ModelContext
    ) throws -> ExperiencePrice {

        try checkCancelled()

        let price = try fetchOrInsert(ExperiencePrice.self, id: dto.id, in: ctx) {
            ExperiencePrice(id: dto.id)
        }

        price.id = dto.id
        price.active = dto.active ?? price.active
        price.age_range = dto.age_range ?? price.age_range
        price.experience_economics = dto.experience_economics ?? price.experience_economics
        price.experience_id = dto.experience_id ?? experience.id
        price.experience_tier = dto.experience_tier ?? price.experience_tier
        price.guest_increment = dto.guest_increment ?? price.guest_increment
        price.price_on_request = dto.price_on_request ?? price.price_on_request
        price.incentive_type_id = dto.incentive_type_id ?? price.incentive_type_id
        price.list_price = dto.list_price ?? price.list_price
        price.max_count = dto.max_count ?? price.max_count
        price.min_count = dto.min_count ?? price.min_count
        price.partner_ref = dto.partner_ref ?? price.partner_ref
        price.price = dto.price ?? price.price
        price.price_type = dto.price_type ?? price.price_type
        price.stripe_product_price_id = dto.stripe_product_price_id ?? price.stripe_product_price_id

        return price
    }

    @discardableResult
    nonisolated static func upsertExperienceType(
        from dto: ExperienceTypeDTO,
        experience: Experience,
        in ctx: ModelContext
    ) throws -> ExperienceType {

        try checkCancelled()

        let type = try fetchOrInsert(ExperienceType.self, id: dto.id, in: ctx) {
            ExperienceType(id: dto.id)
        }

        type.id = dto.id
        type.filter_order = dto.filter_order ?? type.filter_order
        type.filter_visible = dto.filter_visible ?? type.filter_visible
        type.highlight = dto.highlight ?? type.highlight
        type.home_order = dto.home_order ?? type.home_order
        type.home_visible = dto.home_visible ?? type.home_visible
        type.icon_url = dto.icon_url ?? type.icon_url
        type.image_url = dto.image_url ?? type.image_url
        type.market_id = dto.market_id ?? type.market_id
        type.preferabli_market_trait_id = dto.preferabli_market_trait_id ?? type.preferabli_market_trait_id
        type.name = dto.name ?? type.name

        return type
    }

    // MARK: Venue

    @discardableResult
    nonisolated static func upsertVenue(from dto: VenueDTO, in ctx: ModelContext) throws -> Venue? {

        try checkCancelled()

        guard let name = dto.name else {
            return nil
        }

        let v = try fetchOrInsert(Venue.self, id: dto.id, in: ctx) {
            Venue(id: dto.id, name: name)
        }

        // MARK: - Fields (nil means clear; write only if changed)

        if v.address_l1 != dto.address_l1 { v.address_l1 = dto.address_l1 }
        if v.address_l2 != dto.address_l2 { v.address_l2 = dto.address_l2 }
        if v.city != dto.city { v.city = dto.city }
        if v.country != dto.country { v.country = dto.country }
        if v.display_name != dto.display_name { v.display_name = dto.display_name }

        if v.lat != dto.lat { v.lat = dto.lat }
        if v.lon != dto.lon { v.lon = dto.lon }

        if v.primary_inventory_id != dto.primary_inventory_id { v.primary_inventory_id = dto.primary_inventory_id }
        if v.featured_collection_id != dto.featured_collection_id { v.featured_collection_id = dto.featured_collection_id }

        if v.is_virtual != dto.is_virtual { v.is_virtual = dto.is_virtual }

        if v.phone != dto.phone { v.phone = dto.phone }
        if v.email_address != dto.email_address { v.email_address = dto.email_address }
        if v.state != dto.state { v.state = dto.state }
        if v.url != dto.url { v.url = dto.url }

        if v.url_facebook != dto.url_facebook { v.url_facebook = dto.url_facebook }
        if v.url_instagram != dto.url_instagram { v.url_instagram = dto.url_instagram }
        if v.url_twitter != dto.url_twitter { v.url_twitter = dto.url_twitter }
        if v.url_youtube != dto.url_youtube { v.url_youtube = dto.url_youtube }

        if v.zip_code != dto.zip_code { v.zip_code = dto.zip_code }
        if v.notes != dto.notes { v.notes = dto.notes }

        if v.is_partner != dto.is_partner { v.is_partner = dto.is_partner }
        
        if v.isTombstoned { v.isTombstoned = false }
        
        // MARK: - Media pointers
        if let video = dto.video {
            try checkCancelled()
            let media = try upsertMedia(from: video, in: ctx)

            try checkCancelledBeforeRelationshipWrite()
            if v.video !== media { v.video = media }
        } else {
            try checkCancelledBeforeRelationshipWrite()
            v.video = nil
        }
        
        if let logo = dto.logo {
            try checkCancelled()
            let media = try upsertMedia(from: logo, in: ctx)
            media.mime_type = "image/png"

            try checkCancelledBeforeRelationshipWrite()
            if v.logo !== media { v.logo = media }
        } else {
            try checkCancelledBeforeRelationshipWrite()
            v.logo = nil
        }

        if let primary = dto.primary_image {
            try checkCancelled()
            let media = try upsertMedia(from: primary, in: ctx)

            try checkCancelledBeforeRelationshipWrite()
            if v.primary_image !== media { v.primary_image = media }
        } else {
            try checkCancelledBeforeRelationshipWrite()
            v.primary_image = nil
        }


        // MARK: - Relationship lists (source-of-truth as provided by venue DTO)
        if let imgs = dto.images {
            var newImages: [Media] = []
            newImages.reserveCapacity(imgs.count)

            for img in imgs {
                try checkCancelled()
                newImages.append(try upsertMedia(from: img, in: ctx))
            }

            try checkCancelledBeforeRelationshipWrite()
            v.images = newImages
        }

        if let hrs = dto.hours {
            var newHours: [VenueHour] = []
            newHours.reserveCapacity(hrs.count)

            for h in hrs {
                try checkCancelled()
                newHours.append(try upsertVenueHour(from: h, in: ctx))
            }

            try checkCancelledBeforeRelationshipWrite()
            v.hours = newHours
        }

        if let dms = dto.active_delivery_methods {
            var newDms: [DeliveryMethod] = []
            newDms.reserveCapacity(dms.count)

            for dm in dms {
                try checkCancelled()
                newDms.append(try upsertDeliveryMethod(from: dm, in: ctx))
            }

            try checkCancelledBeforeRelationshipWrite()
            v.active_delivery_methods = newDms
        }

        return v
    }
    
    nonisolated static func deleteVenuesNotInBatch(
        _ keep: Set<Int>,
        rootMarket: Market,
        in ctx: ModelContext
    ) throws {
        try checkCancelled()

        let hierarchyIDs = collectMarketHierarchyIDs(from: rootMarket)

        guard !hierarchyIDs.isEmpty else { return }

        let existing = try ctx.fetch(FetchDescriptor<Venue>())

        for venue in existing {
            try checkCancelled()

            if keep.contains(venue.id) {
                continue
            }

            let venueMarketIDs = Set(venue.market_ids_cache)

            // If cache is empty, do NOT delete. Safer than nuking unknown legacy rows.
            if venueMarketIDs.isEmpty {
                continue
            }

            let isInThisHierarchy = !venueMarketIDs.isDisjoint(with: hierarchyIDs)
            let isOnlyInThisHierarchy = venueMarketIDs.isSubset(of: hierarchyIDs)

            if isInThisHierarchy && isOnlyInThisHierarchy {
                try checkCancelledBeforeRelationshipWrite()
                venue.isTombstoned = true
            }
        }
    }

    nonisolated private static func collectMarketHierarchyIDs(from market: Market) -> Set<Int> {
        var ids = Set<Int>()

        func walk(_ market: Market) {
            ids.insert(market.id)

            for child in market.submarkets {
                walk(child)
            }
        }

        walk(market)
        return ids
    }
    
    @discardableResult
    nonisolated static func upsertVenue(
        from dto: VenueDTO,
        market: Market?,
        batch: VenueUpsertBatch,
        in ctx: ModelContext
    ) throws -> Venue? {
        try checkCancelled()

        guard let name = dto.name else {
            return nil
        }

        let v = try cachedVenue(
            id: dto.id,
            name: name,
            batch: batch,
            in: ctx
        )

        if v.name != name { v.name = name }

        // MARK: - Fields

        if v.address_l1 != dto.address_l1 { v.address_l1 = dto.address_l1 }
        if v.address_l2 != dto.address_l2 { v.address_l2 = dto.address_l2 }
        if v.city != dto.city { v.city = dto.city }
        if v.country != dto.country { v.country = dto.country }
        if v.display_name != dto.display_name { v.display_name = dto.display_name }

        if v.lat != dto.lat { v.lat = dto.lat }
        if v.lon != dto.lon { v.lon = dto.lon }

        if v.primary_inventory_id != dto.primary_inventory_id { v.primary_inventory_id = dto.primary_inventory_id }
        if v.featured_collection_id != dto.featured_collection_id { v.featured_collection_id = dto.featured_collection_id }

        if v.is_virtual != dto.is_virtual { v.is_virtual = dto.is_virtual }

        if v.phone != dto.phone { v.phone = dto.phone }
        if v.email_address != dto.email_address { v.email_address = dto.email_address }
        if v.state != dto.state { v.state = dto.state }
        if v.url != dto.url { v.url = dto.url }

        if v.url_facebook != dto.url_facebook { v.url_facebook = dto.url_facebook }
        if v.url_instagram != dto.url_instagram { v.url_instagram = dto.url_instagram }
        if v.url_twitter != dto.url_twitter { v.url_twitter = dto.url_twitter }
        if v.url_youtube != dto.url_youtube { v.url_youtube = dto.url_youtube }

        if v.zip_code != dto.zip_code { v.zip_code = dto.zip_code }
        if v.notes != dto.notes { v.notes = dto.notes }

        if v.is_partner != dto.is_partner { v.is_partner = dto.is_partner }
        
        if v.isTombstoned { v.isTombstoned = false }


        // MARK: - Market cache

        let dtoMarketIDs = dto.market_ids ?? []
        let newMarketIDs = Array(
            Set(dtoMarketIDs).union([market?.id].compactMap { $0 })
        ).sorted()

        if v.market_ids_cache != newMarketIDs {
            v.market_ids_cache = newMarketIDs
        }

        // MARK: - Media pointers

        if let video = dto.video {
            let media = try cachedMedia(from: video, batch: batch, in: ctx)

            try checkCancelledBeforeRelationshipWrite()
            if v.video !== media { v.video = media }
        } else if v.video != nil {
            try checkCancelledBeforeRelationshipWrite()
            v.video = nil
        }

        if let logo = dto.logo {
            let media = try cachedMedia(from: logo, batch: batch, in: ctx)
            media.mime_type = "image/png"

            try checkCancelledBeforeRelationshipWrite()
            if v.logo !== media { v.logo = media }
        } else if v.logo != nil {
            try checkCancelledBeforeRelationshipWrite()
            v.logo = nil
        }

        if let primary = dto.primary_image {
            let media = try cachedMedia(from: primary, batch: batch, in: ctx)

            try checkCancelledBeforeRelationshipWrite()
            if v.primary_image !== media { v.primary_image = media }
        } else if v.primary_image != nil {
            try checkCancelledBeforeRelationshipWrite()
            v.primary_image = nil
        }

        // MARK: - Venue <-> MarketTrait

        if let venueTraitDTOs = dto.market_trait_associations {
            let scopeMarketID = market?.id

            let resolved: [(order: Int?, trait: MarketTraitDTO)] = venueTraitDTOs.compactMap { row in
                guard let trait = row.market_trait else { return nil }
                return (row.order, trait)
            }

            let keepKeys = Set(
                resolved.map {
                    VenueMarketTrait.makeKey(
                        venueID: v.id,
                        marketID: scopeMarketID,
                        traitID: $0.trait.id
                    )
                }
            )

            if !v.venue_market_traits.isEmpty {
                for link in v.venue_market_traits {
                    try checkCancelled()

                    guard link.market_id == scopeMarketID else { continue }

                    if !keepKeys.contains(link.key) {
                        try checkCancelledBeforeRelationshipWrite()
                        ctx.delete(link)
                        batch.venueMarketTraitsByKey[link.key] = nil
                    }
                }
            }

            var newScopedLinks: [VenueMarketTrait] = []
            newScopedLinks.reserveCapacity(resolved.count)

            for (order, traitDTO) in resolved {
                try checkCancelled()

                let trait = try cachedMarketTrait(
                    from: traitDTO,
                    batch: batch,
                    in: ctx
                )

                let key = VenueMarketTrait.makeKey(
                    venueID: v.id,
                    marketID: scopeMarketID,
                    traitID: trait.id
                )

                let link = try cachedVenueMarketTrait(
                    key: key,
                    venue: v,
                    trait: trait,
                    marketID: scopeMarketID,
                    batch: batch,
                    in: ctx
                )

                if link.order != order { link.order = order }

                newScopedLinks.append(link)
            }

            let preserved = v.venue_market_traits.filter { $0.market_id != scopeMarketID }
            let currentScoped = v.venue_market_traits.filter { $0.market_id == scopeMarketID }

            if !sameVenueMarketTraitKeys(currentScoped, newScopedLinks) {
                try checkCancelledBeforeRelationshipWrite()
                v.venue_market_traits = preserved + newScopedLinks
            }
        }

        // MARK: - Relationship lists

        if let imgs = dto.images {
            var newImages: [Media] = []
            newImages.reserveCapacity(imgs.count)

            for img in imgs {
                try checkCancelled()
                newImages.append(try cachedMedia(from: img, batch: batch, in: ctx))
            }

            if !sameIntIDs(v.images, newImages) {
                try checkCancelledBeforeRelationshipWrite()
                v.images = newImages
            }
        }

        if let hrs = dto.hours {
            var newHours: [VenueHour] = []
            newHours.reserveCapacity(hrs.count)

            for h in hrs {
                try checkCancelled()
                newHours.append(try cachedVenueHour(from: h, batch: batch, in: ctx))
            }

            if !sameIntIDs(v.hours, newHours) {
                try checkCancelledBeforeRelationshipWrite()
                v.hours = newHours
            }
        }

        if let dms = dto.active_delivery_methods {
            var newDms: [DeliveryMethod] = []
            newDms.reserveCapacity(dms.count)

            for dm in dms {
                try checkCancelled()
                newDms.append(try cachedDeliveryMethod(from: dm, batch: batch, in: ctx))
            }

            if !sameIntIDs(v.active_delivery_methods, newDms) {
                try checkCancelledBeforeRelationshipWrite()
                v.active_delivery_methods = newDms
            }
        }

        return v
    }

    @discardableResult
    nonisolated static func upsertVenueHour(from dto: VenueHourDTO, in ctx: ModelContext) throws -> VenueHour {

        try checkCancelled()

        let h = try fetchOrInsert(VenueHour.self, id: dto.id, in: ctx) { VenueHour(id: dto.id) }
        h.weekday = dto.weekday ?? h.weekday
        h.open_time = dto.open_time ?? h.open_time
        h.close_time = dto.close_time ?? h.close_time
        h.is_closed = dto.is_closed ?? h.is_closed
        return h
    }

    @discardableResult
    nonisolated static func upsertDeliveryMethod(from dto: DeliveryMethodDTO, in ctx: ModelContext) throws -> DeliveryMethod {

        try checkCancelled()

        let d = try fetchOrInsert(DeliveryMethod.self, id: dto.id, in: ctx) { DeliveryMethod(id: dto.id) }
        d.shipping_type = dto.shipping_type ?? d.shipping_type
        d.state_abbreviation = dto.state_abbreviation ?? d.state_abbreviation
        d.state_display_name = dto.state_display_name ?? d.state_display_name
        d.country = dto.country ?? d.country
        d.shipping_cost_note = dto.shipping_cost_note ?? d.shipping_cost_note
        d.shipping_speed_note = dto.shipping_speed_note ?? d.shipping_speed_note
        return d
    }

    // MARK: Collection tree

    @discardableResult
    nonisolated static func upsertCollection(from dto: CollectionDTO, in ctx: ModelContext) throws -> Collection {

        try checkCancelled()

        let c = try fetchOrInsert(Collection.self, id: dto.id, in: ctx) { Collection(id: dto.id) }

        c.channel_id = dto.channel_id ?? c.channel_id
        c.sort_channel_id = dto.sort_channel_id ?? c.sort_channel_id
        c.code = dto.code ?? c.code
        c.desc = dto.description ?? c.desc
        c.end_date = dto.end_date ?? c.end_date
        c.updated_at = dto.updated_at ?? c.updated_at
        c.auto_wili = dto.auto_wili ?? c.auto_wili
        c.is_pinned = dto.is_pinned ?? c.is_pinned
        c.display_time = dto.display_time ?? c.display_time
        c.is_browsable = dto.is_browsable ?? c.is_browsable
        c.is_my_cellar = dto.is_my_cellar ?? c.is_my_cellar
        c.lbs_order = dto.lbs_order ?? c.lbs_order
        c.product_count = dto.product_count ?? c.product_count
        c.name = dto.name ?? c.name
        c.badge_method = dto.badge_method ?? c.badge_method
        c.currency = dto.currency ?? c.currency
        c.timezone = dto.timezone ?? c.timezone
        c.published = dto.published ?? c.published
        c.archived = dto.archived ?? c.archived
        c.display_price = dto.display_price ?? c.display_price
        c.display_quantity = dto.display_quantity ?? c.display_quantity
        c.display_bin = dto.display_bin ?? c.display_bin
        c.has_predict_order = dto.has_predict_order ?? c.has_predict_order
        c.is_randomized = dto.is_randomized ?? c.is_randomized
        c.display_group_headings = dto.display_group_headings ?? c.display_group_headings
        c.is_blind = dto.is_blind ?? c.is_blind
        c.start_date = dto.start_date ?? c.start_date
        c.created_at = dto.created_at ?? c.created_at
        c.venue_id = dto.venue_id ?? c.venue_id
        c.sort_channel_name = dto.sort_channel_name ?? c.sort_channel_name
        c.location_based_recs = dto.location_based_recs ?? c.location_based_recs

        // Primary image (fix duplicated block + handle nil)
        if let img = dto.primary_image {
            try checkCancelled()
            let media = try upsertMedia(from: img, in: ctx)

            try checkCancelledBeforeRelationshipWrite()
            if c.primary_image !== media { c.primary_image = media }
        } else {
            try checkCancelledBeforeRelationshipWrite()
            c.primary_image = nil
        }

        if let vers = dto.versions {
            var newVers: [CollectionVersion] = []
            newVers.reserveCapacity(vers.count)

            for ver in vers {
                try checkCancelled()
                newVers.append(try upsertCollectionVersion(from: ver, collection: c, in: ctx))
            }

            try checkCancelledBeforeRelationshipWrite()
            c.versions = newVers
        }

        return c
    }

    // MARK: - CollectionVersion / CollectionGroup / CollectionOrder

    @discardableResult
    nonisolated static func upsertCollectionVersion(
        from dto: CollectionVersionDTO,
        collection: Collection,
        in ctx: ModelContext
    ) throws -> CollectionVersion {

        try checkCancelled()

        let v = try fetchOrInsert(CollectionVersion.self, id: dto.id, in: ctx) {
            CollectionVersion(id: dto.id, collection: collection)
        }

        v.created_at = dto.created_at ?? v.created_at
        v.updated_at = dto.updated_at ?? v.updated_at
        v.name       = dto.name       ?? v.name
        v.order      = dto.order      ?? v.order

        try checkCancelledBeforeRelationshipWrite()
        if v.collection.id != collection.id {
            v.collection = collection
        }

        if let groupDTOs = dto.groups {
            var newGroups: [CollectionGroup] = []
            newGroups.reserveCapacity(groupDTOs.count)

            for g in groupDTOs {
                try checkCancelled()
                newGroups.append(try upsertCollectionGroup(from: g, version: v, in: ctx))
            }

            try checkCancelledBeforeRelationshipWrite()
            v.groups = newGroups
        }

        return v
    }

    @discardableResult
    nonisolated static func upsertCollectionGroup(
        from dto: CollectionGroupDTO,
        version: CollectionVersion,
        in ctx: ModelContext
    ) throws -> CollectionGroup {

        try checkCancelled()

        let g = try fetchOrInsert(CollectionGroup.self, id: dto.id, in: ctx) {
            CollectionGroup(id: dto.id, version: version)
        }

        g.created_at      = dto.created_at      ?? g.created_at
        g.updated_at      = dto.updated_at      ?? g.updated_at
        g.name            = dto.name            ?? g.name
        g.order           = dto.order           ?? g.order
        g.orderings_count = dto.orderings_count ?? g.orderings_count

        try checkCancelledBeforeRelationshipWrite()
        if g.version.id != version.id {
            g.version = version
        }

        return g
    }

    @discardableResult
    nonisolated static func upsertCollectionOrder(
        from dto: CollectionOrderDTO,
        group: CollectionGroup,
        tag: Tag,
        in ctx: ModelContext
    ) throws -> CollectionOrder {

        try checkCancelled()

        let o = try fetchOrInsert(CollectionOrder.self, id: dto.id, in: ctx) {
            CollectionOrder(
                id: dto.id,
                tag_id: tag.id,
                order: dto.order ?? 0,
                group: group,
                tag: tag
            )
        }

        o.created_at = dto.created_at ?? o.created_at
        o.updated_at = dto.updated_at ?? o.updated_at
        o.order = dto.order
        
        // inside Storage.upsertCollectionOrder(from:group:tag:in:)
        o.collectionID = group.version.collection.id
        o.groupID      = group.id
        o.productID    = tag.variant.product.id
        o.tagCreatedAt = tag.created_at
        o.tagTypeRaw   = tag.tag_type?.getDatabaseName()
        o.year         = (tag.variant.year > 0) ? tag.variant.year : nil
        o.searchableRaw = tag.searchableContent   // compute once, store once

        try checkCancelledBeforeRelationshipWrite()
        if o.group.id != group.id { o.group = group }
        if o.tag.id != tag.id { o.tag = tag }
        o.tag_id = tag.id

        return o
    }

    @discardableResult
    nonisolated static func upsertCollectionTrait(from dto: CollectionTraitDTO, in ctx: ModelContext) throws -> CollectionTrait {

        try checkCancelled()

        let t = try fetchOrInsert(CollectionTrait.self, id: dto.id, in: ctx) { CollectionTrait(id: dto.id) }
        t.name = dto.name ?? t.name
        t.order = dto.order ?? t.order
        t.restrict_to_ring_it = dto.restrict_to_ring_it ?? t.restrict_to_ring_it
        return t
    }

    // MARK: Profile & ProfileStyle

    @discardableResult
    nonisolated static func upsertProfile(from dto: ProfileDTO, in ctx: ModelContext) throws -> Profile {

        try checkCancelled()

        let p = try fetchOrInsert(Profile.self, id: dto.id, in: ctx) { Profile(id: dto.id) }

        p.user_id = dto.user_id
        p.customer_id = dto.customer_id

        p.score = dto.score
        p.score_red       = dto.score_red
        p.score_white     = dto.score_white
        p.score_rose      = dto.score_rose
        p.score_sparkling = dto.score_sparkling
        p.score_fortified = dto.score_fortified
        p.score_whiskey   = dto.score_whiskey
        p.score_tequila   = dto.score_tequila
        p.score_vodka     = dto.score_vodka
        p.score_gin       = dto.score_gin
        p.score_rum       = dto.score_rum
        p.score_sake      = dto.score_sake
        p.score_cocktail  = dto.score_cocktail
        p.score_beer      = dto.score_beer
        p.score_cheese    = dto.score_cheese

        p.created_at = dto.created_at ?? p.created_at
        p.updated_at = dto.updated_at ?? p.updated_at

        for pStyle in dto.preference_styles {
            try checkCancelled()
            _ = try upsertProfileStyle(from: pStyle, profile: p, in: ctx)
        }

        return p
    }

    @discardableResult
    nonisolated static func upsertProfileStyle(from dto: ProfileStyleDTO, profile: Profile, in ctx: ModelContext) throws -> ProfileStyle {

        try checkCancelled()

        let ps = try fetchOrInsert(ProfileStyle.self, id: dto.id, in: ctx) {
            ProfileStyle(id: dto.id, style_id: dto.style_id)
        }

        ps.conflict = dto.conflict ?? ps.conflict
        ps.order_profile = dto.order_profile ?? ps.order_profile
        ps.order_recommend = dto.order_recommend ?? ps.order_recommend
        ps.rating = dto.rating ?? ps.rating
        ps.strength = dto.strength ?? ps.strength
        ps.style_id = dto.style_id ?? ps.style_id
        ps.recommend = dto.recommend ?? ps.recommend
        ps.refine = dto.refine ?? ps.refine
        ps.keywords = dto.keywords ?? ps.keywords
        ps.created_at = dto.created_at ?? ps.created_at
        ps.updated_at = dto.updated_at ?? ps.updated_at

        try checkCancelledBeforeRelationshipWrite()
        ps.profile = profile

        if let s = dto.style {
            try checkCancelled()
            let style = try upsertStyle(from: s, in: ctx)

            try checkCancelledBeforeRelationshipWrite()
            ps.style = style
        }

        return ps
    }

    // MARK: UserCollection

    @discardableResult
    nonisolated static func upsertUserCollection(from dto: UserCollectionDTO, in ctx: ModelContext) throws -> UserCollection {

        try checkCancelled()

        let collection = try upsertCollection(from: dto.collection, in: ctx)
        let uc = try fetchOrInsert(UserCollection.self, id: dto.id, in: ctx) {
            UserCollection(id: dto.id, collection_id: dto.collection_id, collection: collection)
        }

        uc.relationship_type = dto.relationship_type ?? uc.relationship_type
        uc.created_at = dto.created_at ?? uc.created_at
        uc.updated_at = dto.updated_at ?? uc.updated_at

        try checkCancelledBeforeRelationshipWrite()
        if uc.collection.id != collection.id { uc.collection = collection }

        return uc
    }

    // MARK: Food

    @discardableResult
    nonisolated static func upsertFood(from dto: FoodDTO, in ctx: ModelContext) throws -> Food {

        try checkCancelled()

        let f = try fetchOrInsert(Food.self, id: dto.id, in: ctx) { Food(id: dto.id) }
        f.name = dto.name ?? f.name
        f.keywords = dto.keywords ?? f.keywords
        f.created_at = dto.created_at ?? f.created_at
        f.updated_at = dto.updated_at ?? f.updated_at
        f.food_category_id = dto.food_category_id ?? f.food_category_id
        f.food_category_name = dto.food_category_name ?? f.food_category_name
        f.food_category_icon_svg_url = dto.food_category_icon_svg_url ?? f.food_category_icon_svg_url
        f.food_category_url = dto.food_category_url ?? f.food_category_url
        f.primary_image_url = dto.primary_image_url ?? f.primary_image_url
        f.desc = dto.description ?? f.desc

        return f
    }

    // MARK: - Customer

    @discardableResult
    nonisolated static func upsertCustomer(from dto: CustomerDTO, in ctx: ModelContext) throws -> Customer {

        try checkCancelled()

        let c = try fetchOrInsert(Customer.self, id: dto.id, in: ctx) { Customer(id: dto.id) }
        c.created_at = dto.created_at ?? c.created_at
        c.updated_at = dto.updated_at ?? c.updated_at
        c.avatar_url = dto.avatar_url ?? c.avatar_url
        c.merchant_user_email_address = dto.merchant_user_email_address ?? c.merchant_user_email_address
        c.merchant_user_id = dto.merchant_user_id ?? c.merchant_user_id
        c.merchant_user_name = dto.merchant_user_name ?? c.merchant_user_name
        c.merchant_user_display_name = dto.merchant_user_display_name ?? c.merchant_user_display_name
        c.role = dto.role ?? c.role
        return c
    }

    // MARK: - Location

    @discardableResult
    nonisolated static func upsertLocation(from dto: LocationDTO, in ctx: ModelContext) throws -> Location {

        try checkCancelled()

        let l = try fetchOrInsert(Location.self, id: dto.id, in: ctx) { Location(id: dto.id) }
        l.created_at = dto.created_at ?? l.created_at
        l.updated_at = dto.updated_at ?? l.updated_at
        if let lat = dto.latitude { l.latitude = lat }
        if let lon = dto.longitude { l.longitude = lon }
        if let zip = dto.zip_code { l.zip_code = zip }
        if let country_code = dto.country_code { l.country_code = country_code }

        return l
    }

    // MARK: - Reservation

    // MARK: - Reservation

    @discardableResult
    nonisolated static func upsertReservation(from dto: ReservationDTO, in ctx: ModelContext) throws -> Reservation {

        try checkCancelled()

        let r = try fetchOrInsert(Reservation.self, id: dto.id, in: ctx) {
            Reservation(id: dto.id)
        }

        try checkCancelled()

        r.id = dto.id

        // MARK: - Top-level fields
        r.customer_slug = dto.customer_slug ?? r.customer_slug
        r.date = Storage.normalizeAPIDateString(dto.date) ?? r.date
        r.status = dto.status ?? r.status
        r.requested_times = dto.requested_times ?? r.requested_times
        r.times_available = dto.times_available ?? r.times_available

        // MARK: - Brand snapshot
        if let brandDTO = dto.brand {
            r.brand_id = brandDTO.id
            r.venue_id = brandDTO.venue_id
            r.brand_name = brandDTO.name ?? r.brand_name
            r.brand_logo_image_url = brandDTO.logo_image_url ?? r.brand_logo_image_url
        }

        // MARK: - Experience snapshot
        if let experienceDTO = dto.experience {
            r.experience_id = experienceDTO.id
            r.experience_name = experienceDTO.name ?? r.experience_name
            r.experience_header_image_url = experienceDTO.header_image_url ?? r.experience_header_image_url
            r.experience_preferabli_image_url = experienceDTO.preferabli_image_url ?? r.experience_preferabli_image_url
        }

        // MARK: - Booking snapshot
        if let bookingDTO = dto.concierge_reservation_booking {
            r.booking_id = bookingDTO.id ?? r.booking_id
            r.booking_account_id = bookingDTO.account_id ?? r.booking_account_id
            r.booking_confirmation_ref = bookingDTO.booking_confirmation_ref ?? r.booking_confirmation_ref
            r.booking_type = bookingDTO.booking_type ?? r.booking_type
            r.booking_brand_id = bookingDTO.brand_id ?? r.booking_brand_id
            r.booking_venue_id = bookingDTO.venue_id ?? r.booking_venue_id
            r.booking_confirmed_time = bookingDTO.confirmed_time ?? r.booking_confirmed_time
            r.booking_created_on = Storage.parseDate(bookingDTO.created_on) ?? r.booking_created_on
            r.booking_updated_on = Storage.parseDate(bookingDTO.updated_on) ?? r.booking_updated_on
            r.booking_customer_slug = bookingDTO.customer_slug ?? r.booking_customer_slug
            r.booking_date = Storage.normalizeAPIDateString(bookingDTO.date) ?? r.booking_date
            r.booking_experience_id = bookingDTO.experience_id ?? r.booking_experience_id
            r.booking_modification_link = bookingDTO.modification_link ?? r.booking_modification_link
            r.booking_payment_method_id = bookingDTO.payment_method_id ?? r.booking_payment_method_id
            r.booking_request_id = bookingDTO.request_id ?? r.booking_request_id
            r.booking_specific_requests = bookingDTO.specific_requests ?? r.booking_specific_requests
            r.booking_status = bookingDTO.status ?? r.booking_status

            if dto.experience == nil, let bookingExperienceDTO = bookingDTO.experience {
                r.experience_id = bookingExperienceDTO.id
                r.experience_name = bookingExperienceDTO.name ?? r.experience_name
                r.experience_header_image_url = bookingExperienceDTO.header_image_url ?? r.experience_header_image_url
                r.experience_preferabli_image_url = bookingExperienceDTO.preferabli_image_url ?? r.experience_preferabli_image_url
            }
        }

        // MARK: - Request guests
        if let guestDTOs = dto.concierge_reservation_request_guests {
            var newGuests: [ReservationRequestGuest] = []
            newGuests.reserveCapacity(guestDTOs.count)

            for (index, guestDTO) in guestDTOs.enumerated() {
                try checkCancelled()
                let guest = try upsertReservationRequestGuest(
                    from: guestDTO,
                    reservation: r,
                    index: index,
                    in: ctx
                )
                newGuests.append(guest)
            }

            try checkCancelledBeforeRelationshipWrite()
            r.request_guests = newGuests
        }

        return r
    }

    @discardableResult
    nonisolated static func upsertReservationRequestGuest(
        from dto: ReservationRequestGuestDTO,
        reservation: Reservation,
        index: Int,
        in ctx: ModelContext
    ) throws -> ReservationRequestGuest {

        try checkCancelled()

        let key = ReservationRequestGuest.makeKey(
            reservationID: reservation.id,
            experiencePriceID: dto.experience_price_id,
            index: index
        )

        let guest: ReservationRequestGuest
        if let existing = try Storage.fetchByKey(ReservationRequestGuest.self, key: key, in: ctx) {
            guest = existing
        } else {
            let created = ReservationRequestGuest(key: key)
            ctx.insert(created)
            guest = created
        }

        guest.key = key
        guest.reservation_id = reservation.id
        guest.concierge_reservation_request = dto.concierge_reservation_request ?? guest.concierge_reservation_request
        guest.experience_price_id = dto.experience_price_id ?? guest.experience_price_id
        guest.quantity = dto.quantity ?? guest.quantity

        if let priceDTO = dto.experience_price {
            guest.price_active = priceDTO.active ?? guest.price_active
            guest.price_age_range = priceDTO.age_range ?? guest.price_age_range
            guest.price_experience_economics = priceDTO.experience_economics ?? guest.price_experience_economics
            guest.price_experience_id = priceDTO.experience_id ?? guest.price_experience_id
            guest.price_experience_tier = priceDTO.experience_tier ?? guest.price_experience_tier
            guest.price_guest_increment = priceDTO.guest_increment ?? guest.price_guest_increment
            guest.price_price_on_request = priceDTO.price_on_request ?? guest.price_price_on_request
            guest.price_incentive_type_id = priceDTO.incentive_type_id ?? guest.price_incentive_type_id
            guest.price_list_price = priceDTO.list_price ?? guest.price_list_price
            guest.price_max_count = priceDTO.max_count ?? guest.price_max_count
            guest.price_min_count = priceDTO.min_count ?? guest.price_min_count
            guest.price_partner_ref = priceDTO.partner_ref ?? guest.price_partner_ref
            guest.price_price = priceDTO.price ?? guest.price_price
            guest.price_price_type = priceDTO.price_type ?? guest.price_price_type
            guest.price_stripe_product_price_id = priceDTO.stripe_product_price_id ?? guest.price_stripe_product_price_id
        }

        return guest
    }
    

        // MARK: - BalloonReservation

        @discardableResult
        nonisolated static func upsertBalloonReservation(
            from dto: BalloonReservationDTO,
            in ctx: ModelContext
        ) throws -> BalloonReservation {

            try checkCancelled()

            let reservation = try fetchOrInsert(BalloonReservation.self, id: dto.id, in: ctx) {
                BalloonReservation(id: dto.id)
            }

            try checkCancelled()

            reservation.id = dto.id
            reservation.customer_email = dto.customer_email ?? reservation.customer_email
            reservation.customer_name = dto.customer_name ?? reservation.customer_name
            reservation.customer_phone = dto.customer_phone ?? reservation.customer_phone

            if let itemDTOs = dto.items {
                var newItems: [BalloonReservationItem] = []
                newItems.reserveCapacity(itemDTOs.count)

                for itemDTO in itemDTOs {
                    try checkCancelled()
                    let item = try upsertBalloonReservationItem(from: itemDTO, in: ctx)
                    newItems.append(item)
                }

                try checkCancelledBeforeRelationshipWrite()
                reservation.items = newItems
            }

            return reservation
        }

        @discardableResult
        nonisolated static func upsertBalloonReservationItem(
            from dto: BalloonReservationItemDTO,
            in ctx: ModelContext
        ) throws -> BalloonReservationItem {

            try checkCancelled()

            let item = BalloonReservationItem()
            item.meeting_point = dto.meeting_point
            item.meeting_point_coordinates = dto.meeting_point_coordinates
            item.qty = Int(dto.qty ?? "1")
            item.sku = dto.sku

            if let start = dto.start_date {
                item.start_date = Date(timeIntervalSince1970: TimeInterval(start))
            } else {
                item.start_date = nil
            }

            ctx.insert(item)
            return item
        }

    // MARK: - Style

    @discardableResult
    nonisolated static func upsertStyle(from dto: StyleDTO, profile_style: ProfileStyle? = nil, in ctx: ModelContext) throws -> Style {

        try checkCancelled()

        let s = try fetchOrInsert(Style.self, id: dto.id, in: ctx) { Style(id: dto.id, type: dto.type) }

        s.created_at        = dto.created_at ?? s.created_at
        s.updated_at        = dto.updated_at ?? s.updated_at
        s.desc              = dto.description
        s.name              = dto.name
        s.type              = dto.type
        s.primary_image_url = dto.primary_image_url
        s.product_category  = dto.product_category
        s.is_global = dto.is_global
        s.show_map = dto.show_map

        // Relationship pointer write
        if let ps = profile_style {
            try checkCancelledBeforeRelationshipWrite()
            ps.style = s
        }

        // Source-of-truth replacement: build then assign
        var newLocations: [Location] = []
        newLocations.reserveCapacity(dto.locations.count)

        for locationDTO in dto.locations {
            try checkCancelled()
            newLocations.append(try upsertLocation(from: locationDTO, in: ctx))
        }

        try checkCancelledBeforeRelationshipWrite()
        s.locations = newLocations

        return s
    }

    // MARK: - FoodCategory

    @discardableResult
    nonisolated static func upsertFoodCategory(from dto: FoodCategoryDTO, in ctx: ModelContext) throws -> FoodCategory {

        try checkCancelled()

        let fc = try fetchOrInsert(FoodCategory.self, id: dto.id, in: ctx) { FoodCategory(id: dto.id) }
        fc.created_at = dto.created_at ?? fc.created_at
        fc.updated_at = dto.updated_at ?? fc.updated_at
        fc.name = dto.name ?? fc.name
        fc.icon_url = dto.icon_url ?? fc.icon_url
        fc.icon_svg_url = dto.icon_svg_url ?? fc.icon_svg_url
        
        return fc
    }

    /// Fetch (or create) a Search row by its `text`. Your model has no `id`.
    private static func fetchSearchByText(_ text: String, in ctx: ModelContext) throws -> Search? {
        var fd = FetchDescriptor<Search>(predicate: #Predicate<Search> { $0.text == text })
        fd.fetchLimit = 1
        return try ctx.fetch(fd).first
    }

    @discardableResult
    static func upsertSearch(from dto: SearchDTO, in ctx: ModelContext) throws -> Search {

        try checkCancelled()

        if let existing = try fetchSearchByText(dto.text, in: ctx) {
            if let cnt = dto.count { existing.count = cnt }
            if let d = dto.last_searched { existing.last_searched = d }
            return existing
        }

        let new = Search(
            count: dto.count ?? 0,
            last_searched: dto.last_searched ?? Date(),
            text: dto.text
        )
        ctx.insert(new)
        return new
    }

    // MARK: - PreferabliUser

    @discardableResult
    nonisolated static func upsertPreferabliUser(from dto: PreferabliUserDTO, in ctx: ModelContext) throws -> PreferabliUser {

        try checkCancelled()

        let u = try fetchOrInsert(PreferabliUser.self, id: dto.id, in: ctx) { PreferabliUser(id: dto.id) }

        u.created_at = dto.created_at ?? u.created_at
        u.updated_at = dto.updated_at ?? u.updated_at

        u.country = dto.country ?? u.country
        u.display_name = dto.display_name ?? u.display_name
        u.email = dto.email ?? u.email
        u.is_team_preferabli = dto.is_team_preferabli ?? u.is_team_preferabli
        u.fname = dto.fname ?? u.fname
        u.lname = dto.lname ?? u.lname
        u.claim_code = dto.claim_code ?? u.claim_code
        u.has_merchant_access = dto.has_merchant_access ?? u.has_merchant_access
        u.has_kiosks = dto.has_kiosks ?? u.has_kiosks
        u.zip_code = dto.zip_code ?? u.zip_code
        u.intercom_hmac = dto.intercom_hmac ?? u.intercom_hmac
        u.rating_collection_id = dto.rating_collection_id ?? u.rating_collection_id
        u.provided_feedback_at = dto.provided_feedback_at ?? u.provided_feedback_at
        u.wishlist_collection_id = dto.wishlist_collection_id ?? u.wishlist_collection_id
        u.avatar_background_color_hex = dto.avatar_background_color_hex ?? u.avatar_background_color_hex
        u.avatar_text_color_hex = dto.avatar_text_color_hex ?? u.avatar_text_color_hex

        if let avatarDTO = dto.avatar {
            try checkCancelled()
            let media = try upsertMedia(from: avatarDTO, in: ctx)

            try checkCancelledBeforeRelationshipWrite()
            u.avatar = media
        } else {
            try checkCancelledBeforeRelationshipWrite()
            u.avatar = nil
        }

        return u
    }

    // MARK: - Channel

    @discardableResult
    nonisolated static func upsertChannel(from dto: ChannelDTO, in ctx: ModelContext) throws -> Channel {

        try checkCancelled()

        let c = try fetchOrInsert(Channel.self, id: dto.id, in: ctx) { Channel(id: dto.id) }

        c.account_id = dto.account_id ?? c.account_id
        c.name = dto.name ?? c.name
        c.description_text = dto.description ?? c.description_text
        c.order = dto.order ?? c.order
        c.archived = dto.archived ?? c.archived
        c.published = dto.published ?? c.published

        c.default_display_vintages = dto.default_display_vintages ?? c.default_display_vintages
        c.default_display_variants = dto.default_display_variants ?? c.default_display_variants
        c.default_display_variant_details = dto.display_variant_details ?? c.default_display_variant_details
        c.default_display_price = dto.default_display_price ?? c.default_display_price
        c.default_display_quantity = dto.default_display_quantity ?? c.default_display_quantity
        c.default_display_bin = dto.default_display_bin ?? c.default_display_bin
        c.default_downweight_previous_recs_duration = dto.default_downweight_previous_recs_duration ?? c.default_downweight_previous_recs_duration

        c.has_download_pdf = dto.has_download_pdf ?? c.has_download_pdf
        c.has_download_csv = dto.has_download_csv ?? c.has_download_csv
        c.has_download_xlsx = dto.has_download_xlsx ?? c.has_download_xlsx

        c.is_retailer = dto.is_retailer ?? c.is_retailer
        c.is_producer = dto.is_producer ?? c.is_producer
        c.is_restaurant = dto.is_restaurant ?? c.is_restaurant
        c.is_hospitality = dto.is_hospitality ?? c.is_hospitality
        c.is_event = dto.is_event ?? c.is_event
        c.is_verified = dto.is_verified ?? c.is_verified

        c.default_timezone = dto.default_timezone ?? c.default_timezone
        c.default_currency = dto.default_currency ?? c.default_currency
        c.default_badge_method = dto.default_badge_method ?? c.default_badge_method

        c.num_dollar_signs_cutoff_1 = dto.num_dollar_signs_cutoff_1 ?? c.num_dollar_signs_cutoff_1
        c.num_dollar_signs_cutoff_2 = dto.num_dollar_signs_cutoff_2 ?? c.num_dollar_signs_cutoff_2
        c.num_dollar_signs_cutoff_3 = dto.num_dollar_signs_cutoff_3 ?? c.num_dollar_signs_cutoff_3
        c.num_dollar_signs_cutoff_4 = dto.num_dollar_signs_cutoff_4 ?? c.num_dollar_signs_cutoff_4
        c.num_dollar_signs_cutoff_5 = dto.num_dollar_signs_cutoff_5 ?? c.num_dollar_signs_cutoff_5

        c.currency_exchange_multiplier_from_foreign_to_usd =
        dto.currency_exchange_multiplier_from_foreign_to_usd ?? c.currency_exchange_multiplier_from_foreign_to_usd

        c.featured_collection_id = dto.featured_collection_id ?? c.featured_collection_id
        c.primary_inventory_id = dto.primary_inventory_id ?? c.primary_inventory_id
        c.primary_questionnaire_id = dto.primary_questionnaire_id ?? c.primary_questionnaire_id
        c.default_curation_batch_id = dto.default_curation_batch_id ?? c.default_curation_batch_id
        c.default_curation_questions_batch_id = dto.default_curation_questions_batch_id ?? c.default_curation_questions_batch_id
        c.max_number_of_venues = dto.max_number_of_venues ?? c.max_number_of_venues

        c.created_at = dto.created_at ?? c.created_at
        c.updated_at = dto.updated_at ?? c.updated_at

        if let imgDTO = dto.primary_image {
            try checkCancelled()
            let media = try upsertMedia(from: imgDTO, in: ctx)

            try checkCancelledBeforeRelationshipWrite()
            if c.primary_image !== media { c.primary_image = media }
        }

        if let imgDTOs = dto.images {
            var newImages: [Media] = []
            newImages.reserveCapacity(imgDTOs.count)

            for img in imgDTOs {
                try checkCancelled()
                newImages.append(try upsertMedia(from: img, in: ctx))
            }

            try checkCancelledBeforeRelationshipWrite()
            c.images = newImages
        }

        // Join rows: channel_venues (preserve per-edge flags)
        if let joinDTOs = dto.channel_venues {
            var newJoins: [ChannelVenue] = []
            newJoins.reserveCapacity(joinDTOs.count)

            for j in joinDTOs {
                try checkCancelled()

                let cv = try fetchOrInsert(ChannelVenue.self, id: j.id, in: ctx) { ChannelVenue(id: j.id) }

                cv.is_primary = j.is_primary ?? cv.is_primary
                cv.archived = j.archived ?? cv.archived

                try checkCancelledBeforeRelationshipWrite()
                if cv.channel?.id != c.id { cv.channel = c }

                if let vDTO = j.venue {
                    try checkCancelled()
                    let v = try upsertVenue(from: vDTO, in: ctx)

                    try checkCancelledBeforeRelationshipWrite()
                    if cv.venue?.id != v?.id { cv.venue = v }
                }

                newJoins.append(cv)
            }

            try checkCancelledBeforeRelationshipWrite()
            c.channel_venues = newJoins
        }

        return c
    }

    @discardableResult
    nonisolated static func upsertMarketsSourceOfTruth(
        from rootDTOs: [MarketDTO],
        in ctx: ModelContext
    ) throws -> [Market] {

        try checkCancelled()

        // 1) Collect all market IDs in the incoming forest
        var keepMarketIDs = Set<Int>()
        keepMarketIDs.reserveCapacity(rootDTOs.count * 2)

        func collect(_ dto: MarketDTO) throws {
            try checkCancelled()
            keepMarketIDs.insert(dto.id)
            if let submarkets = dto.submarkets {
                for child in submarkets { try collect(child) }
            }
        }

        for dto in rootDTOs { try collect(dto) }

        // 2) Delete any local Markets not in keep set
        try deleteMarketsNotInSet(keepMarketIDs, in: ctx)

        // 3) Upsert the forest (root parent = nil)
        var roots: [Market] = []
        roots.reserveCapacity(rootDTOs.count)

        for dto in rootDTOs {
            try checkCancelled()
            let m = try upsertMarketTreeNodeSourceOfTruth(from: dto, parent: nil, in: ctx)
            roots.append(m)
        }

        return roots
    }

    nonisolated private static func deleteMarketsNotInSet(
        _ keep: Set<Int>,
        in ctx: ModelContext
    ) throws {

        try checkCancelled()

        let all = try ctx.fetch(FetchDescriptor<Market>())

        for m in all {
            try checkCancelled()
            if !keep.contains(m.id) {
                // Deleting while a logout wipe is happening is also a hot point.
                try checkCancelledBeforeRelationshipWrite()
                ctx.delete(m) // cascades to submarkets + traits because of deleteRule
            }
        }
    }

    @discardableResult
    nonisolated private static func upsertMarketTreeNodeSourceOfTruth(
        from dto: MarketDTO,
        parent: Market?,
        in ctx: ModelContext
    ) throws -> Market {

        try checkCancelled()

        let market = try fetchOrInsert(Market.self, id: dto.id, in: ctx) { Market(id: dto.id) }

        try checkCancelled()

        // Fields
        market.name = dto.name ?? market.name
        market.desc = dto.description ?? market.desc
        market.image_url = dto.image_url ?? market.image_url
        market.order = dto.top_level_order ?? market.order
        market.country_code = dto.country_code ?? market.country_code
        market.latitude = dto.latitude ?? market.latitude
        market.longitude = dto.longitude ?? market.longitude
        market.top_level = dto.top_level_order != nil
        market.display_appellations = dto.display_appellations ?? market.display_appellations
        market.created_at = dto.created_at ?? market.created_at
        market.updated_at = dto.updated_at ?? market.updated_at
        market.default_span_delta = dto.default_span_delta ?? market.default_span_delta

        // Parent
        try checkCancelledBeforeRelationshipWrite()
        if market.parent?.id != parent?.id {
            market.parent = parent
        }

        // Traits: source-of-truth per market
        let assocDTOs = dto.market_trait_associations ?? []
        try upsertMarketTraitsSourceOfTruth(from: assocDTOs, for: market, in: ctx)

        // Children
        let childDTOs = dto.submarkets ?? []
        var newChildren: [Market] = []
        newChildren.reserveCapacity(childDTOs.count)

        for childDTO in childDTOs {
            try checkCancelled()
            let child = try upsertMarketTreeNodeSourceOfTruth(from: childDTO, parent: market, in: ctx)
            newChildren.append(child)
        }

        if !sameIDs(market.submarkets, newChildren) {
            try checkCancelledBeforeRelationshipWrite()
            market.submarkets = newChildren
        }

        return market
    }
    
    @discardableResult
    nonisolated private static func upsertMarketTraitAssociationForVenue(
        from dto: MarketTraitDTO,
        venue: Venue,
        market: Market?,
        in ctx: ModelContext
    ) throws -> MarketTrait {

        try checkCancelled()

        // 1) Hydrate trait
        let t = try fetchOrInsert(MarketTrait.self, id: dto.id, in: ctx) { MarketTrait(id: dto.id) }
        t.type = dto.type ?? t.type
        t.name = dto.name ?? t.name
        t.icon_url = dto.icon_url ?? t.icon_url
        t.created_at = dto.created_at ?? t.created_at
        t.updated_at = dto.updated_at ?? t.updated_at

        // 2) Ensure join row exists (order is not provided by this DTO; keep existing)
        let scopeMarketID = market?.id
        let key = VenueMarketTrait.makeKey(venueID: venue.id, marketID: scopeMarketID, traitID: t.id)

        let link: VenueMarketTrait
        if let existing = try Storage.fetchByKey(VenueMarketTrait.self, key: key, in: ctx) {
            link = existing
        } else {
            let created = VenueMarketTrait(key: key, venue: venue, trait: t, market_id: scopeMarketID)
            ctx.insert(created)
            link = created
        }

        // Re-assert denorms (helps after wipes / partial graph)
        link.venue_id = venue.id
        link.trait_id = t.id
        link.market_id = scopeMarketID

        try checkCancelledBeforeRelationshipWrite()
        if link.venue.id != venue.id { link.venue = venue }
        if link.trait.id != t.id { link.trait = t }

        // Ensure venue list contains it (avoid duplicates)
        try checkCancelledBeforeRelationshipWrite()
        if !venue.venue_market_traits.contains(where: { $0.key == link.key }) {
            venue.venue_market_traits.append(link)
        }

        return t
    }

    /// Source of truth:
    /// - Upsert all MarketTraitAssociation rows in DTO
    /// - Delete any local MarketTraitAssociation linked to this market that isn't in DTO
    nonisolated private static func upsertMarketTraitsSourceOfTruth(
        from assocDTOs: [MarketTraitAssociationDTO],
        for market: Market,
        in ctx: ModelContext
    ) throws {

        try checkCancelled()

        let keepAssociationIDs = Set(assocDTOs.map { $0.id })

        // 1) Delete missing associations for this market
        if !market.traits.isEmpty {
            for existing in market.traits {
                try checkCancelled()
                if !keepAssociationIDs.contains(existing.id) {
                    try checkCancelledBeforeRelationshipWrite()
                    ctx.delete(existing)
                }
            }
        }

        // 2) Upsert / build new ordered list (preserve API order)
        var newAssocs: [MarketTraitAssociation] = []
        newAssocs.reserveCapacity(assocDTOs.count)

        for aDTO in assocDTOs {
            try checkCancelled()

            guard let traitDTO = aDTO.market_trait else { continue }

            // Hydrate trait using *traitDTO.id* (NOT association id)
            let mt = try fetchOrInsert(MarketTrait.self, id: traitDTO.id, in: ctx) { MarketTrait(id: traitDTO.id) }
            mt.type = traitDTO.type ?? mt.type
            mt.name = traitDTO.name ?? mt.name
            mt.icon_url = traitDTO.icon_url ?? mt.icon_url
            mt.created_at = traitDTO.created_at ?? mt.created_at
            mt.updated_at = traitDTO.updated_at ?? mt.updated_at

            // Association row uses *aDTO.id*
            let mta = try fetchOrInsert(MarketTraitAssociation.self, id: aDTO.id, in: ctx) {
                MarketTraitAssociation(id: aDTO.id, market: market, market_trait: mt)
            }

            mta.order = aDTO.order ?? mta.order
            mta.is_filter_option = aDTO.is_filter_option ?? mta.is_filter_option
            mta.created_at = aDTO.created_at ?? mta.created_at
            mta.updated_at = aDTO.updated_at ?? mta.updated_at

            try checkCancelledBeforeRelationshipWrite()
            if mta.market.id != market.id { mta.market = market }
            if mta.market_trait.id != mt.id { mta.market_trait = mt }

            newAssocs.append(mta)
        }

        if !sameTraitIDs(market.traits, newAssocs) {
            try checkCancelledBeforeRelationshipWrite()
            market.traits = newAssocs
        }
    }

        @discardableResult
        nonisolated static func upsertRecipeGroup(from dto: RecipeGroupDTO, in ctx: ModelContext) throws -> RecipeGroup {

            try checkCancelled()

            let g = try fetchOrInsert(RecipeGroup.self, id: dto.id, in: ctx) { RecipeGroup(id: dto.id) }

            g.created_at = dto.created_at ?? g.created_at
            g.updated_at = dto.updated_at ?? g.updated_at
            g.order = dto.order ?? g.order
            g.internal_notes = dto.internal_notes ?? g.internal_notes
            g.name = dto.name ?? g.name
            g.type = dto.type ?? g.type
            g.icon_svg_url = dto.icon_svg_url ?? g.icon_svg_url
            
            // Primary image
            if let imgDTO = dto.primary_image {
                try checkCancelled()
                let media = try upsertMedia(from: imgDTO, in: ctx)

                try checkCancelledBeforeRelationshipWrite()
                if g.primary_image !== media { g.primary_image = media }
            } else {
                try checkCancelledBeforeRelationshipWrite()
                g.primary_image = nil
            }

            return g
        }

        // MARK: - Recipe

        @discardableResult
        nonisolated static func upsertRecipe(from dto: RecipeDTO, in ctx: ModelContext) throws -> Recipe {

            try checkCancelled()

            let fc = try upsertFoodCategory(from: dto.food_category, in: ctx)

            let r = try fetchOrInsert(Recipe.self, id: dto.id, in: ctx) { Recipe(id: dto.id, category: fc) }

            r.created_at = dto.created_at ?? r.created_at
            r.updated_at = dto.updated_at ?? r.updated_at
            r.merchant_recipe_id = dto.merchant_recipe_id ?? r.merchant_recipe_id
            r.url = dto.url ?? r.url
            r.primary_image_url = dto.primary_image_url ?? r.primary_image_url
            r.desc = dto.description ?? r.desc
            r.name = dto.name ?? r.name

            if let groupDTOs = dto.recipe_groups {
                var newGroups: [RecipeGroup] = []
                newGroups.reserveCapacity(groupDTOs.count)

                for gDTO in groupDTOs {
                    try checkCancelled()
                    newGroups.append(try upsertRecipeGroup(from: gDTO, in: ctx))
                }

                try checkCancelledBeforeRelationshipWrite()
                r.recipe_groups = newGroups
            }

            return r
        }
    
    @discardableResult
    nonisolated static func upsertProductRecipe(order: Int, recipe: Recipe, product: Product, in ctx: ModelContext) throws -> ProductRecipe {

        try checkCancelled()
        
        let key = ProductRecipe.makeKey(order: order, recipeId: recipe.id, productId: product.id)

        let pr: ProductRecipe
        if let existing = try Storage.fetchByKey(ProductRecipe.self, key: key, in: ctx) {
            pr = existing
        } else {
            let created = ProductRecipe(key: key, order: order, recipe: recipe, product: product)
            ctx.insert(created)
            pr = created
        }

        return pr
    }
    
    @discardableResult
    nonisolated static func upsertCTABucketAssociation(from dto: CTABucketAssociationDTO, page: CTAPage, bucket: CTABucket, in ctx: ModelContext) throws -> CTABucketAssociation {

        try checkCancelled()

        let r = try fetchOrInsert(CTABucketAssociation.self, id: dto.id, in: ctx) { CTABucketAssociation(id: dto.id, page: page, bucket: bucket) }

        r.page = page
        r.bucket = bucket
        r.isTombstoned = false
        r.created_at = dto.created_at ?? r.created_at
        r.updated_at = dto.updated_at ?? r.updated_at
        r.order = dto.order ?? r.order

        return r
    }
    
    @discardableResult
    nonisolated static func upsertCTABucket(from dto: CTABucketDTO, in ctx: ModelContext) throws -> CTABucket {

        try checkCancelled()


        let r = try fetchOrInsert(CTABucket.self, id: dto.id, in: ctx) { CTABucket(id: dto.id) }

        r.created_at = dto.created_at ?? r.created_at
        r.updated_at = dto.updated_at ?? r.updated_at
        r.name = dto.name ?? r.name
        r.type = dto.type ?? r.type
        r.item_width = dto.item_width ?? r.item_width
        r.item_height = dto.item_height ?? r.item_height
        r.item_corner_radius = dto.item_corner_radius ?? r.item_corner_radius
        r.deeplink_url = dto.deeplink_url ?? r.deeplink_url

        if let associations = dto.bucket_item_associations {
            let keepIDs = Set(associations.map(\.id))

            for oldAssociation in r.bucket_item_associations where !keepIDs.contains(oldAssociation.id) {
                oldAssociation.isTombstoned = true
            }

            for associationDTO in associations {
                try checkCancelled()

                let item = try upsertCTABucketItem(
                    from: associationDTO.item,
                    in: ctx
                )

                _ = try upsertCTABucketItemAssociation(
                    from: associationDTO,
                    bucket: r,
                    item: item,
                    in: ctx
                )
            }
        }

        return r
    }
    
    @discardableResult
    nonisolated static func upsertCTAPage(from dto: CTAPageDTO, in ctx: ModelContext) throws -> CTAPage {

        try checkCancelled()


        let r = try fetchOrInsert(CTAPage.self, id: dto.id, in: ctx) { CTAPage(id: dto.id) }

        r.created_at = dto.created_at ?? r.created_at
        r.updated_at = dto.updated_at ?? r.updated_at
        r.name = dto.name ?? r.name
        r.slug = dto.slug ?? r.slug
        r.market_id = dto.market_id ?? r.market_id
        r.affiliate_id = dto.affiliate_id ?? r.affiliate_id
        r.isTombstoned = false

        if let bucketAssociations = dto.page_bucket_associations {
            let keepIDs = Set(bucketAssociations.map(\.id))

            for oldAssociation in r.page_bucket_associations where !keepIDs.contains(oldAssociation.id) {
                oldAssociation.isTombstoned = true
            }

            for association in bucketAssociations {
                try checkCancelled()
                let bucket = try upsertCTABucket(from: association.bucket, in: ctx)
                _ = try upsertCTABucketAssociation(
                    from: association,
                    page: r,
                    bucket: bucket,
                    in: ctx
                )
            }
        } else {
            for page_bucket_ass in r.page_bucket_associations {
                page_bucket_ass.isTombstoned = true
            }
        }

        return r
    }
    
    @discardableResult
    nonisolated static func upsertCTABucketItemAssociation(
        from dto: CTABucketItemAssociationDTO,
        bucket: CTABucket,
        item: CTABucketItem,
        in ctx: ModelContext
    ) throws -> CTABucketItemAssociation {

        try checkCancelled()

        let r = try fetchOrInsert(CTABucketItemAssociation.self, id: dto.id, in: ctx) {
            CTABucketItemAssociation(id: dto.id, bucket: bucket, item: item)
        }

        r.bucket = bucket
        r.item = item
        r.isTombstoned = false
        r.order = dto.order ?? r.order
        r.created_at = dto.created_at ?? r.created_at
        r.updated_at = dto.updated_at ?? r.updated_at

        return r
    }

        @discardableResult
    nonisolated static func upsertCTABucketItem(
        from dto: CTABucketItemDTO,
        in ctx: ModelContext
    ) throws -> CTABucketItem {
        
        try checkCancelled()

            let b = try fetchOrInsert(CTABucketItem.self, id: dto.id, in: ctx) {
                CTABucketItem(id: dto.id)
            }
        
            try checkCancelled()

            // Fields
            b.badge_icon = dto.badge_icon
            b.badge_color_hex_primary = dto.badge_color_hex_primary
            b.badge_color_hex_secondary = dto.badge_color_hex_secondary
            b.badge_gradient_css = dto.badge_gradient_css
            b.text_color_hex = dto.text_color_hex
            b.color_hex_secondary = dto.color_hex_secondary
            b.color_hex_primary = dto.color_hex_primary
            b.gradient_css = dto.gradient_css
            b.deeplink_url = dto.deeplink_url
            b.badge_title = dto.badge_title
            b.title = dto.title
            b.desc = dto.description

            b.created_at = dto.created_at ?? b.created_at
            b.updated_at = dto.updated_at ?? b.updated_at

            // Primary image
            if let imgDTO = dto.primary_image {
                try checkCancelled()
                let media = try upsertMedia(from: imgDTO, in: ctx)

                try checkCancelledBeforeRelationshipWrite()
                if b.primary_image !== media { b.primary_image = media }
            } else {
                try checkCancelledBeforeRelationshipWrite()
                b.primary_image = nil
            }
            
            // sub image 1
            if let imgDTO = dto.sub_image_1 {
                try checkCancelled()
                let media = try upsertMedia(from: imgDTO, in: ctx)

                try checkCancelledBeforeRelationshipWrite()
                if b.sub_image_1 !== media { b.sub_image_1 = media }
            } else {
                try checkCancelledBeforeRelationshipWrite()
                b.sub_image_1 = nil
            }
            
            // sub image 2
            if let imgDTO = dto.sub_image_2 {
                try checkCancelled()
                let media = try upsertMedia(from: imgDTO, in: ctx)

                try checkCancelledBeforeRelationshipWrite()
                if b.sub_image_2 !== media { b.sub_image_2 = media }
            } else {
                try checkCancelledBeforeRelationshipWrite()
                b.sub_image_2 = nil
            }

            return b
        }

        /// Source-of-truth upsert for CTABuckets with scoped deletes.
        ///
        /// - If `scopeMarketId` and `scopeSection` are nil => delete *all* CTAs not in API response.
        /// - If either is set => delete only CTAs matching that scope that are not in API response.
        ///
        /// Returns the IDs that exist after the operation (the keep set).
    @discardableResult
    nonisolated static func upsertCTAPagesSourceOfTruth(
        from responseDTOs: [CTAPageDTO],
        in ctx: ModelContext
    ) throws -> [Int] {
        try checkCancelled()

        for pageDTO in responseDTOs {
            try checkCancelled()

            _ = try upsertCTAPage(
                from: pageDTO,
                in: ctx
            )
        }

        let keepIDs = Set(responseDTOs.map { $0.id })

        // 3) Then delete old rows
        try deleteCTAPagesNotInSet(
            keepIDs,
            in: ctx
        )

        return Array(keepIDs)
    }

        nonisolated private static func deleteCTAPagesNotInSet(
            _ keep: Set<Int>,
            in ctx: ModelContext
        ) throws {

            try checkCancelled()

            // Build fetch descriptor based on scope
            let fd: FetchDescriptor<CTAPage> = FetchDescriptor<CTAPage>() // global

            let existing = try ctx.fetch(fd)

            for b in existing {
                try checkCancelled()
                if !keep.contains(b.id) {
                    try checkCancelledBeforeRelationshipWrite()
                    b.isTombstoned = true
                }
            }
        }

    nonisolated private static func sameTraitIDs(_ a: [MarketTraitAssociation], _ b: [MarketTraitAssociation]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) where x.id != y.id { return false }
        return true
    }
    
    
    nonisolated private static func sameIDs(_ a: [Market], _ b: [Market]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) where x.id != y.id { return false }
        return true
    }
    
}

extension Storage {

    public nonisolated static func saveCellarCollectionIDs(_ cellarIds: [Int]) {
        let set = Set(cellarIds)
        CellarIDCacheStore.shared.set(set)

        Storage.getKeyStore().set(Array(set), forKey: cellarIDsKey)
    }

    public nonisolated static func loadCellarCollectionIDSetCached() -> Set<Int> {
        if !CellarIDCacheStore.shared.isEmpty() {
            return CellarIDCacheStore.shared.get()
        }

        let arr = Storage.getKeyStore().array(forKey: cellarIDsKey) as? [Int] ?? []
        let set = Set(arr)
        CellarIDCacheStore.shared.set(set)
        return set
    }

    public nonisolated static func isCellarCollectionID(_ id: Int) -> Bool {
        if CellarIDCacheStore.shared.contains(id) { return true }
        return loadCellarCollectionIDSetCached().contains(id)
    }
}

private let cellarIDsKey = "cellar_collection_ids_v1"

private final class CellarIDCacheStore: @unchecked Sendable {
    static let shared = CellarIDCacheStore()

    private var set: Set<Int> = []
    private let lock = NSLock()

    func get() -> Set<Int> {
        lock.lock(); defer { lock.unlock() }
        return set
    }

    func set(_ new: Set<Int>) {
        lock.lock(); defer { lock.unlock() }
        set = new
    }

    func contains(_ id: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return set.contains(id)
    }

    func isEmpty() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return set.isEmpty
    }
}

extension Storage {
    nonisolated final class VenueUpsertBatch: @unchecked Sendable {
        var venuesByID: [Int: Venue]
        var mediaByID: [Int: Media]
        var venueHoursByID: [Int: VenueHour]
        var deliveryMethodsByID: [Int: DeliveryMethod]
        var marketTraitsByID: [Int: MarketTrait]
        var venueMarketTraitsByKey: [String: VenueMarketTrait]

        init(
            venueDTOs: [VenueDTO],
            market: Market?,
            in ctx: ModelContext
        ) throws {
            try Storage.checkCancelled()

            var venueIDs = Set<Int>()
            var mediaIDs = Set<Int>()
            var hourIDs = Set<Int>()
            var deliveryMethodIDs = Set<Int>()
            var marketTraitIDs = Set<Int>()
            var venueMarketTraitKeys = Set<String>()

            let scopeMarketID = market?.id

            for dto in venueDTOs {
                venueIDs.insert(dto.id)

                if let id = dto.video?.id { mediaIDs.insert(id) }
                if let id = dto.video_poster?.id { mediaIDs.insert(id) }
                if let id = dto.logo?.id { mediaIDs.insert(id) }
                if let id = dto.primary_image?.id { mediaIDs.insert(id) }

                for image in dto.images ?? [] {
                    mediaIDs.insert(image.id)
                }

                for hour in dto.hours ?? [] {
                    hourIDs.insert(hour.id)
                }

                for method in dto.active_delivery_methods ?? [] {
                    deliveryMethodIDs.insert(method.id)
                }

                for row in dto.market_trait_associations ?? [] {
                    guard let trait = row.market_trait else { continue }

                    marketTraitIDs.insert(trait.id)

                    let key = VenueMarketTrait.makeKey(
                        venueID: dto.id,
                        marketID: scopeMarketID,
                        traitID: trait.id
                    )

                    venueMarketTraitKeys.insert(key)
                }
            }

            self.venuesByID = try Storage.fetchExistingVenues(
                ids: Array(venueIDs),
                in: ctx
            )

            self.mediaByID = try Storage.fetchExistingMedia(
                ids: Array(mediaIDs),
                in: ctx
            )

            self.venueHoursByID = try Storage.fetchExistingVenueHours(
                ids: Array(hourIDs),
                in: ctx
            )

            self.deliveryMethodsByID = try Storage.fetchExistingDeliveryMethods(
                ids: Array(deliveryMethodIDs),
                in: ctx
            )

            self.marketTraitsByID = try Storage.fetchExistingMarketTraits(
                ids: Array(marketTraitIDs),
                in: ctx
            )

            self.venueMarketTraitsByKey = try Storage.fetchExistingVenueMarketTraits(
                keys: Array(venueMarketTraitKeys),
                in: ctx
            )
        }
    }

    nonisolated static func fetchExistingVenueMarketTraits(
        keys: [String],
        in ctx: ModelContext
    ) throws -> [String: VenueMarketTrait] {
        let keys = Array(Set(keys))
        guard !keys.isEmpty else { return [:] }

        var result: [String: VenueMarketTrait] = [:]
        result.reserveCapacity(keys.count)

        let chunkSize = 500

        for start in stride(from: 0, to: keys.count, by: chunkSize) {
            try checkCancelled()

            let end = min(start + chunkSize, keys.count)
            let chunk = Array(keys[start..<end])

            let fd = FetchDescriptor<VenueMarketTrait>(
                predicate: #Predicate<VenueMarketTrait> { link in
                    chunk.contains(link.key)
                }
            )

            let links = try ctx.fetch(fd)

            for link in links {
                result[link.key] = link
            }
        }

        return result
    }
    
    @discardableResult
    nonisolated static func cachedVenue(
        id: Int,
        name: String,
        batch: VenueUpsertBatch,
        in ctx: ModelContext
    ) throws -> Venue {
        if let existing = batch.venuesByID[id] {
            return existing
        }

        let created = Venue(id: id, name: name)
        created.id = id
        ctx.insert(created)
        batch.venuesByID[id] = created
        return created
    }

    @discardableResult
    nonisolated static func cachedMedia(
        from dto: MediaDTO,
        batch: VenueUpsertBatch,
        in ctx: ModelContext
    ) throws -> Media {
        let media: Media

        if let existing = batch.mediaByID[dto.id] {
            media = existing
        } else {
            let created = Media(id: dto.id)
            created.id = dto.id
            ctx.insert(created)
            batch.mediaByID[dto.id] = created
            media = created
        }

        if media.path != dto.path { media.path = dto.path }
        if media.type != dto.type { media.type = dto.type }
        if media.mime_type != dto.mime_type { media.mime_type = dto.mime_type }

        if let posterDTO = dto.poster {
            guard posterDTO.id != dto.id else {
                media.poster = nil
                return media
            }

            let poster = try cachedInternalMedia(from: posterDTO, batch: batch, in: ctx)
            media.poster = poster
        } else {
            media.poster = nil
        }

        return media
    }

    @discardableResult
    nonisolated static func cachedInternalMedia(
        from dto: InternalMediaDTO,
        batch: VenueUpsertBatch,
        in ctx: ModelContext
    ) throws -> Media {
        let media: Media

        if let existing = batch.mediaByID[dto.id] {
            media = existing
        } else {
            let created = Media(id: dto.id)
            created.id = dto.id
            ctx.insert(created)
            batch.mediaByID[dto.id] = created
            media = created
        }

        if media.path != dto.path { media.path = dto.path }
        if media.type != dto.type { media.type = dto.type }
        if media.mime_type != dto.mime_type { media.mime_type = dto.mime_type }

        return media
    }

    @discardableResult
    nonisolated static func cachedVenueHour(
        from dto: VenueHourDTO,
        batch: VenueUpsertBatch,
        in ctx: ModelContext
    ) throws -> VenueHour {
        let hour: VenueHour

        if let existing = batch.venueHoursByID[dto.id] {
            hour = existing
        } else {
            let created = VenueHour(id: dto.id)
            created.id = dto.id
            ctx.insert(created)
            batch.venueHoursByID[dto.id] = created
            hour = created
        }

        if hour.weekday != dto.weekday { hour.weekday = dto.weekday }
        if hour.open_time != dto.open_time { hour.open_time = dto.open_time }
        if hour.close_time != dto.close_time { hour.close_time = dto.close_time }
        if hour.is_closed != dto.is_closed { hour.is_closed = dto.is_closed }

        return hour
    }

    @discardableResult
    nonisolated static func cachedDeliveryMethod(
        from dto: DeliveryMethodDTO,
        batch: VenueUpsertBatch,
        in ctx: ModelContext
    ) throws -> DeliveryMethod {
        let method: DeliveryMethod

        if let existing = batch.deliveryMethodsByID[dto.id] {
            method = existing
        } else {
            let created = DeliveryMethod(id: dto.id)
            created.id = dto.id
            ctx.insert(created)
            batch.deliveryMethodsByID[dto.id] = created
            method = created
        }

        if method.shipping_type != dto.shipping_type { method.shipping_type = dto.shipping_type }
        if method.state_abbreviation != dto.state_abbreviation { method.state_abbreviation = dto.state_abbreviation }
        if method.state_display_name != dto.state_display_name { method.state_display_name = dto.state_display_name }
        if method.country != dto.country { method.country = dto.country }
        if method.shipping_cost_note != dto.shipping_cost_note { method.shipping_cost_note = dto.shipping_cost_note }
        if method.shipping_speed_note != dto.shipping_speed_note { method.shipping_speed_note = dto.shipping_speed_note }

        return method
    }

    @discardableResult
    nonisolated static func cachedMarketTrait(
        from dto: MarketTraitDTO,
        batch: VenueUpsertBatch,
        in ctx: ModelContext
    ) throws -> MarketTrait {
        let trait: MarketTrait

        if let existing = batch.marketTraitsByID[dto.id] {
            trait = existing
        } else {
            let created = MarketTrait(id: dto.id)
            created.id = dto.id
            ctx.insert(created)
            batch.marketTraitsByID[dto.id] = created
            trait = created
        }

        if trait.type != dto.type { trait.type = dto.type }
        if trait.name != dto.name { trait.name = dto.name }
        if trait.icon_url != dto.icon_url { trait.icon_url = dto.icon_url }
        if trait.created_at != dto.created_at { trait.created_at = dto.created_at ?? Date.now }
        if trait.updated_at != dto.updated_at { trait.updated_at = dto.updated_at ?? Date.now }

        return trait
    }

    @discardableResult
    nonisolated static func cachedVenueMarketTrait(
        key: String,
        venue: Venue,
        trait: MarketTrait,
        marketID: Int?,
        batch: VenueUpsertBatch,
        in ctx: ModelContext
    ) throws -> VenueMarketTrait {
        let link: VenueMarketTrait

        if let existing = batch.venueMarketTraitsByKey[key] {
            link = existing
        } else {
            let created = VenueMarketTrait(
                key: key,
                venue: venue,
                trait: trait,
                market_id: marketID
            )

            ctx.insert(created)
            batch.venueMarketTraitsByKey[key] = created
            link = created
        }

        if link.key != key { link.key = key }
        if link.venue_id != venue.id { link.venue_id = venue.id }
        if link.trait_id != trait.id { link.trait_id = trait.id }
        if link.market_id != marketID { link.market_id = marketID }

        try checkCancelledBeforeRelationshipWrite()
        if link.venue.id != venue.id { link.venue = venue }
        if link.trait.id != trait.id { link.trait = trait }

        return link
    }

    @inline(__always)
    nonisolated private static func sameIntIDs<T: HasIntID>(_ lhs: [T], _ rhs: [T]) -> Bool {
        guard lhs.count == rhs.count else { return false }

        for (a, b) in zip(lhs, rhs) {
            if a.id != b.id { return false }
        }

        return true
    }

    @inline(__always)
    nonisolated private static func sameVenueMarketTraitKeys(
        _ lhs: [VenueMarketTrait],
        _ rhs: [VenueMarketTrait]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }

        for (a, b) in zip(lhs, rhs) {
            if a.key != b.key { return false }
        }

        return true
    }
}

extension Storage {
    nonisolated static func fetchExistingVenues(
        ids: [Int],
        in ctx: ModelContext
    ) throws -> [Int: Venue] {
        let ids = Array(Set(ids))
        guard !ids.isEmpty else { return [:] }

        var result: [Int: Venue] = [:]
        result.reserveCapacity(ids.count)

        let chunkSize = 500

        for start in stride(from: 0, to: ids.count, by: chunkSize) {
            try checkCancelled()

            let end = min(start + chunkSize, ids.count)
            let chunk = Array(ids[start..<end])

            let fd = FetchDescriptor<Venue>(
                predicate: #Predicate<Venue> { venue in
                    chunk.contains(venue.id)
                }
            )

            for venue in try ctx.fetch(fd) {
                result[venue.id] = venue
            }
        }

        return result
    }

    nonisolated static func fetchExistingMedia(
        ids: [Int],
        in ctx: ModelContext
    ) throws -> [Int: Media] {
        let ids = Array(Set(ids))
        guard !ids.isEmpty else { return [:] }

        var result: [Int: Media] = [:]
        result.reserveCapacity(ids.count)

        let chunkSize = 500

        for start in stride(from: 0, to: ids.count, by: chunkSize) {
            try checkCancelled()

            let end = min(start + chunkSize, ids.count)
            let chunk = Array(ids[start..<end])

            let fd = FetchDescriptor<Media>(
                predicate: #Predicate<Media> { media in
                    chunk.contains(media.id)
                }
            )

            for media in try ctx.fetch(fd) {
                result[media.id] = media
            }
        }

        return result
    }

    nonisolated static func fetchExistingVenueHours(
        ids: [Int],
        in ctx: ModelContext
    ) throws -> [Int: VenueHour] {
        let ids = Array(Set(ids))
        guard !ids.isEmpty else { return [:] }

        var result: [Int: VenueHour] = [:]
        result.reserveCapacity(ids.count)

        let chunkSize = 500

        for start in stride(from: 0, to: ids.count, by: chunkSize) {
            try checkCancelled()

            let end = min(start + chunkSize, ids.count)
            let chunk = Array(ids[start..<end])

            let fd = FetchDescriptor<VenueHour>(
                predicate: #Predicate<VenueHour> { hour in
                    chunk.contains(hour.id)
                }
            )

            for hour in try ctx.fetch(fd) {
                result[hour.id] = hour
            }
        }

        return result
    }

    nonisolated static func fetchExistingDeliveryMethods(
        ids: [Int],
        in ctx: ModelContext
    ) throws -> [Int: DeliveryMethod] {
        let ids = Array(Set(ids))
        guard !ids.isEmpty else { return [:] }

        var result: [Int: DeliveryMethod] = [:]
        result.reserveCapacity(ids.count)

        let chunkSize = 500

        for start in stride(from: 0, to: ids.count, by: chunkSize) {
            try checkCancelled()

            let end = min(start + chunkSize, ids.count)
            let chunk = Array(ids[start..<end])

            let fd = FetchDescriptor<DeliveryMethod>(
                predicate: #Predicate<DeliveryMethod> { method in
                    chunk.contains(method.id)
                }
            )

            for method in try ctx.fetch(fd) {
                result[method.id] = method
            }
        }

        return result
    }

    nonisolated static func fetchExistingMarketTraits(
        ids: [Int],
        in ctx: ModelContext
    ) throws -> [Int: MarketTrait] {
        let ids = Array(Set(ids))
        guard !ids.isEmpty else { return [:] }

        var result: [Int: MarketTrait] = [:]
        result.reserveCapacity(ids.count)

        let chunkSize = 500

        for start in stride(from: 0, to: ids.count, by: chunkSize) {
            try checkCancelled()

            let end = min(start + chunkSize, ids.count)
            let chunk = Array(ids[start..<end])

            let fd = FetchDescriptor<MarketTrait>(
                predicate: #Predicate<MarketTrait> { trait in
                    chunk.contains(trait.id)
                }
            )

            for trait in try ctx.fetch(fd) {
                result[trait.id] = trait
            }
        }

        return result
    }
}

extension Storage {
    nonisolated static func tombstoneExperiencesNotInSet(
        _ keep: Set<Int>,
        rootMarket: Market? = nil,
        scopeVenueId: Int? = nil,
        in ctx: ModelContext
    ) throws {
        try checkCancelled()

        let hierarchyIDs = rootMarket.map { collectMarketHierarchyIDs(from: $0) }

        let fd: FetchDescriptor<Experience>

        if let venueId = scopeVenueId {
            fd = FetchDescriptor(
                predicate: #Predicate<Experience> { experience in
                    experience.venue.id == venueId && !experience.isUnlocked
                }
            )
        } else {
            fd = FetchDescriptor(
                predicate: #Predicate<Experience> { experience in
                    !experience.isUnlocked
                }
            )
        }

        let existing = try ctx.fetch(fd)

        for experience in existing {
            try checkCancelled()

            if keep.contains(experience.id) {
                if experience.isTombstoned {
                    try checkCancelledBeforeRelationshipWrite()
                    experience.isTombstoned = false
                }
                continue
            }

            if let hierarchyIDs {
                let venueMarketIDs = Set(experience.venue.market_ids_cache)

                // Safer: don't tombstone legacy/unknown venue scope.
                if venueMarketIDs.isEmpty {
                    continue
                }

                let isInThisHierarchy = !venueMarketIDs.isDisjoint(with: hierarchyIDs)

                guard isInThisHierarchy else {
                    continue
                }
            }

            try checkCancelledBeforeRelationshipWrite()
            experience.isTombstoned = true
        }
    }
}

// MARK: - GenAI

extension Storage {

    @discardableResult
    nonisolated static func upsertGenAIMessage(
        from dto: GenAIMessageDTO,
        fallbackSessionId: String? = nil,
        fallbackTurn: Int? = nil,
        in ctx: ModelContext
    ) throws -> GenAIMessage {
        try checkCancelled()

        let messageId = dto.id
        let message: GenAIMessage

        let descriptor = FetchDescriptor<GenAIMessage>(
            predicate: #Predicate<GenAIMessage> { $0.id == messageId }
        )

        if let existing = try ctx.fetch(descriptor).first {
            message = existing
        } else if let matchingLocal = try fetchMatchingLocalGenAIMessage(for: dto, in: ctx) {
            message = matchingLocal
            message.id = messageId
        } else {
            message = GenAIMessage(id: messageId)
            ctx.insert(message)
        }

        message.sessionId = dto.sessionId ?? fallbackSessionId ?? message.sessionId
        message.transactionId = dto.transactionId ?? message.transactionId
        message.source = dto.source ?? message.source
        message.utterance = dto.utterance ?? message.utterance
        message.turn = dto.turn ?? fallbackTurn ?? message.turn
        message.created_at = dto.createdAt ?? message.created_at
        message.updated_at = dto.updatedAt ?? message.updated_at
        message.userAction = dto.userAction ?? message.userAction
        message.userOptions = dto.userOptions ?? message.userOptions
        message.userSelection = dto.userSelection ?? message.userSelection
        message.reportedIssue = dto.reportedIssue ?? message.reportedIssue
        message.feedbackId = dto.feedbackId ?? message.feedbackId
        message.positiveReaction = dto.positiveReaction ?? message.positiveReaction
        message.isTombstoned = isGenAISelectionActionOnlyMessage(dto)

        message.variantIds = dto.variantIds
        message.foodIds = dto.foodIds

        // Product IDs are finalized after hydration. Keep any direct entity IDs now.
        message.productIds = dto.productEntityIds

        if !dto.utteranceObjects.isEmpty {
            try replaceGenAIUtteranceObjects(on: message, with: dto.utteranceObjects, in: ctx)
        }

        try applyGenAISelectionActionIfNeeded(from: dto, in: ctx)

        return message
    }
    
    private nonisolated static func isGenAISelectionActionOnlyMessage(
        _ dto: GenAIMessageDTO
    ) -> Bool {
        guard dto.utterance?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
              let action = dto.userAction
        else { return false }

        return [
            "btn_food_entity_confirm",
            "btn_wine_entity_confirm",
            "btn_food_entity_reject",
            "btn_wine_entity_reject"
        ].contains(action)
    }
    
    private struct GenAIParsedSelection {
        let entityId: Int?
    }

    private nonisolated static func applyGenAISelectionActionIfNeeded(
        from dto: GenAIMessageDTO,
        in ctx: ModelContext
    ) throws {
        guard let sessionId = dto.sessionId,
              let turn = dto.turn,
              let action = dto.userAction
        else { return }

        let isFoodConfirm = action == "btn_food_entity_confirm"
        let isProductConfirm = action == "btn_wine_entity_confirm"
        let isFoodReject = action == "btn_food_entity_reject"
        let isProductReject = action == "btn_wine_entity_reject"

        guard isFoodConfirm || isProductConfirm || isFoodReject || isProductReject else { return }

        let descriptor = FetchDescriptor<GenAIMessage>(
            predicate: #Predicate<GenAIMessage> { message in
                message.sessionId == sessionId &&
                message.turn < turn &&
                message.isTombstoned == false
            },
            sortBy: [SortDescriptor(\.turn, order: .reverse)]
        )

        let previousMessages = try ctx.fetch(descriptor)

        guard let target = previousMessages.first(where: { message in
            if isFoodConfirm || isFoodReject {
                return message.hasFoodOptions
            } else {
                return message.hasProductOptions
            }
        }) else { return }

        if isFoodConfirm {
            let selection = parseGenAIUserSelection(dto.userSelection)
            target.selectedFoodId = selection.entityId
            target.didRejectSelection = false
            target.updated_at = Date()
        } else if isProductConfirm {
            let selection = parseGenAIUserSelection(dto.userSelection)
            target.selectedProductId = selection.entityId
            target.didRejectSelection = false
            target.updated_at = Date()
        } else {
            target.didRejectSelection = true
            target.updated_at = Date()
        }
    }
    
    private nonisolated static func parseGenAIUserSelection(
        _ raw: String?
    ) -> GenAIParsedSelection {
        guard var raw else {
            return GenAIParsedSelection(entityId: nil)
        }

        raw = raw.replacingOccurrences(of: "=>", with: ":")

        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return GenAIParsedSelection(entityId: nil)
        }

        return GenAIParsedSelection(
            entityId: object["entity_id"] as? Int
        )
    }


    private nonisolated static func fetchMatchingLocalGenAIMessage(
        for dto: GenAIMessageDTO,
        in ctx: ModelContext
    ) throws -> GenAIMessage? {
        guard let sessionId = dto.sessionId,
              let turn = dto.turn
        else { return nil }

        let descriptor = FetchDescriptor<GenAIMessage>(
            predicate: #Predicate<GenAIMessage> { message in
                message.sessionId == sessionId &&
                message.turn == turn &&
                message.isTombstoned == false
            }
        )

        let candidates = try ctx.fetch(descriptor)
        return candidates.first { candidate in
            if let source = dto.source, candidate.source != source { return false }

            if let utterance = dto.utterance,
               let candidateUtterance = candidate.utterance,
               candidateUtterance != utterance {
                return false
            }

            return true
        }
    }

    nonisolated static func updateGenAIMessageProductIds(
        messageId: Int,
        productIds: [Int],
        in ctx: ModelContext
    ) throws {
        guard let message = try fetchGenAIMessage(id: messageId, in: ctx) else { return }
        message.productIds = productIds.uniqued()
        message.updated_at = Date()
    }

    nonisolated static func fetchGenAIMessage(id: Int, in ctx: ModelContext) throws -> GenAIMessage? {
        let descriptor = FetchDescriptor<GenAIMessage>(
            predicate: #Predicate<GenAIMessage> { $0.id == id }
        )
        return try ctx.fetch(descriptor).first
    }

    private nonisolated static func replaceGenAIUtteranceObjects(
        on message: GenAIMessage,
        with utteranceDTOs: [GenAIUtteranceDTO],
        in ctx: ModelContext
    ) throws {
        for utterance in message.utteranceObjects {
            ctx.delete(utterance)
        }
        message.utteranceObjects.removeAll()

        for utteranceDTO in utteranceDTOs {
            try checkCancelled()

            let utterance = GenAIUtterance(
                type: utteranceDTO.type ?? "",
                subType: utteranceDTO.subType ?? "",
                order: utteranceDTO.order
            )
            utterance.message = message
            ctx.insert(utterance)

            for contentDTO in utteranceDTO.content {
                let content = GenAIUtteranceContent(
                    remoteId: contentDTO.remoteId,
                    productId: contentDTO.productId,
                    entityId: contentDTO.entityId,
                    order: contentDTO.order,
                    entityName: contentDTO.entityName,
                    entityProbability: contentDTO.entityProbability,
                    name: contentDTO.name,
                    recognitionType: contentDTO.recognitionType,
                    displayData: contentDTO.displayData
                )
                content.utterance = utterance
                ctx.insert(content)
                utterance.content.append(content)
            }

            message.utteranceObjects.append(utterance)
        }
    }
}

extension Storage {

    // MARK: - Content

    @discardableResult
    nonisolated static func upsertContent(
        from dto: ContentDTO,
        parent: ContentItem? = nil,
        includeChildren: Bool = true,
        includePersonalityAssociations: Bool = true,
        in ctx: ModelContext
    ) throws -> ContentItem {

        try checkCancelled()

        let content = try fetchOrInsert(ContentItem.self, id: dto.id, in: ctx) {
            ContentItem(id: dto.id)
        }

        content.created_at = dto.created_at ?? content.created_at
        content.updated_at = dto.updated_at ?? content.updated_at
        content.title = dto.title
        content.desc = dto.description
        content.episode_name = dto.episode_name
        content.episode_order = dto.episode_order

        
        // Parent. If this method is being called while walking a parent's child list,
        // prefer the supplied parent to avoid recursive parent/child loops.
        if let parent {
            try checkCancelledBeforeRelationshipWrite()
            if content.content_parent?.id != parent.id {
                content.content_parent = parent
            }
        } else if let parentDTO = dto.content_parent {
            let resolvedParent = try upsertContent(
                from: parentDTO,
                parent: nil,
                includeChildren: false,
                includePersonalityAssociations: false,
                in: ctx
            )

            try checkCancelledBeforeRelationshipWrite()
            if content.content_parent?.id != resolvedParent.id {
                content.content_parent = resolvedParent
            }
        } else {
            try checkCancelledBeforeRelationshipWrite()
            if content.content_parent != nil {
                content.content_parent = nil
            }
        }

        // Primary media: content endpoint is authoritative; nil clears.
        if let mediaDTO = dto.primary_media {
            try checkCancelled()
            let media = try upsertMedia(from: mediaDTO, in: ctx)

            try checkCancelledBeforeRelationshipWrite()
            if content.primary_media !== media {
                content.primary_media = media
            }
        } else {
            try checkCancelledBeforeRelationshipWrite()
            if content.primary_media != nil {
                content.primary_media = nil
            }
        }

        // Product cache is authoritative for the product/variant objects referenced by
        // variant_associations. Associations now carry product_id + variant_id only.
        if let productDTOs = dto.products_cache {
            for productDTO in productDTOs {
                try checkCancelled()
                _ = try upsertProduct(from: productDTO, in: ctx)
            }
        }

        // Venue cache is authoritative for Venue objects referenced by venue_associations.
        // Save every cached venue regardless of whether it is associated with this content item.
        if let venueDTOs = dto.venues_cache {
            for venueDTO in venueDTOs {
                try checkCancelled()
                _ = try upsertVenue(from: venueDTO, in: ctx)
            }
        }

//        if includeChildren, let childDTOs = dto.content_children {
//            var newChildren: [ContentItem] = []
//            newChildren.reserveCapacity(childDTOs.count)
//
//            for childDTO in childDTOs {
//                try checkCancelled()
//                let child = try upsertContent(
//                    from: childDTO,
//                    parent: content,
//                    includeChildren: true,
//                    includePersonalityAssociations: includePersonalityAssociations,
//                    in: ctx
//                )
//                newChildren.append(child)
//            }
//
//            if !sameIntIDs(content.content_children, newChildren) {
//                try checkCancelledBeforeRelationshipWrite()
//                content.content_children = newChildren
//            }
//        }

        if includePersonalityAssociations,
           let associationDTOs = dto.personality_associations {
            var newAssociations: [ContentPersonalityAssociation] = []
            newAssociations.reserveCapacity(associationDTOs.count)

            for associationDTO in associationDTOs {
                try checkCancelled()
                guard let personalityDTO = associationDTO.personality else { continue }

                let personality = try upsertPersonality(
                    from: personalityDTO,
                    in: ctx
                )

                let association = try upsertContentPersonalityAssociation(
                    from: associationDTO,
                    content: content,
                    personality: personality,
                    in: ctx
                )

                newAssociations.append(association)
            }

            try deleteMissing(content.personality_associations, keeping: Set(newAssociations.map(\.id)), in: ctx)

            if !sameIntIDs(content.personality_associations, newAssociations) {
                try checkCancelledBeforeRelationshipWrite()
                content.personality_associations = newAssociations
            }
        }

        if let associationDTOs = dto.variant_associations {
            var newAssociations: [ContentVariantAssociation] = []
            newAssociations.reserveCapacity(associationDTOs.count)

            for associationDTO in associationDTOs {
                try checkCancelled()
                newAssociations.append(
                    try upsertContentVariantAssociation(from: associationDTO, content: content, in: ctx)
                )
            }

            try deleteMissing(content.variant_associations, keeping: Set(newAssociations.map(\.id)), in: ctx)

            if !sameIntIDs(content.variant_associations, newAssociations) {
                try checkCancelledBeforeRelationshipWrite()
                content.variant_associations = newAssociations
            }
        }

//        if let associationDTOs = dto.channel_associations {
//            var newAssociations: [ContentChannelAssociation] = []
//            newAssociations.reserveCapacity(associationDTOs.count)
//
//            for associationDTO in associationDTOs {
//                try checkCancelled()
//                newAssociations.append(
//                    try upsertContentChannelAssociation(from: associationDTO, content: content, in: ctx)
//                )
//            }
//
//            try deleteMissing(content.channel_associations, keeping: Set(newAssociations.map(\.id)), in: ctx)
//
//            if !sameIntIDs(content.channel_associations, newAssociations) {
//                try checkCancelledBeforeRelationshipWrite()
//                content.channel_associations = newAssociations
//            }
//        }

        if let associationDTOs = dto.venue_associations {
            var newAssociations: [ContentVenueAssociation] = []
            newAssociations.reserveCapacity(associationDTOs.count)

            for associationDTO in associationDTOs {
                try checkCancelled()
                newAssociations.append(
                    try upsertContentVenueAssociation(from: associationDTO, content: content, in: ctx)
                )
            }

            try deleteMissing(content.venue_associations, keeping: Set(newAssociations.map(\.id)), in: ctx)

            if !sameIntIDs(content.venue_associations, newAssociations) {
                try checkCancelledBeforeRelationshipWrite()
                content.venue_associations = newAssociations
            }
        }

        if let associationDTOs = dto.experience_associations {
            var newAssociations: [ContentExperienceAssociation] = []
            newAssociations.reserveCapacity(associationDTOs.count)

            for associationDTO in associationDTOs {
                try checkCancelled()
                newAssociations.append(
                    try upsertContentExperienceAssociation(from: associationDTO, content: content, in: ctx)
                )
            }

            try deleteMissing(content.experience_associations, keeping: Set(newAssociations.map(\.id)), in: ctx)

            if !sameIntIDs(content.experience_associations, newAssociations) {
                try checkCancelledBeforeRelationshipWrite()
                content.experience_associations = newAssociations
            }
        }

//        if let associationDTOs = dto.market_traits_associations {
//            var newAssociations: [ContentMarketTraitAssociation] = []
//            newAssociations.reserveCapacity(associationDTOs.count)
//
//            for associationDTO in associationDTOs {
//                try checkCancelled()
//                newAssociations.append(
//                    try upsertContentMarketTraitAssociation(from: associationDTO, content: content, in: ctx)
//                )
//            }
//
//            try deleteMissing(content.market_traits_associations, keeping: Set(newAssociations.map(\.id)), in: ctx)
//
//            if !sameIntIDs(content.market_traits_associations, newAssociations) {
//                try checkCancelledBeforeRelationshipWrite()
//                content.market_traits_associations = newAssociations
//            }
//        }

        return content
    }

    @discardableResult
    nonisolated static func upsertContentChildren(
        parentID: Int,
        from childDTOs: [ContentDTO],
        replaceExisting: Bool = false,
        in ctx: ModelContext
    ) throws -> [ContentItem] {

        try checkCancelled()

        let parent = try fetchOrInsert(ContentItem.self, id: parentID, in: ctx) {
            ContentItem(id: parentID)
        }

        var childrenByID: [Int: ContentItem] = [:]
        var orderedChildren: [ContentItem] = []

        if !replaceExisting {
            for existingChild in parent.content_children {
                childrenByID[existingChild.id] = existingChild
                orderedChildren.append(existingChild)
            }
        }

        for childDTO in childDTOs {
            try checkCancelled()

            let child = try upsertContent(
                from: childDTO,
                parent: parent,
                includeChildren: false,
                includePersonalityAssociations: true,
                in: ctx
            )

            if childrenByID[child.id] == nil {
                orderedChildren.append(child)
            }

            childrenByID[child.id] = child
        }

        let mergedChildren = orderedChildren.compactMap { childrenByID[$0.id] }

        if !sameIntIDs(parent.content_children, mergedChildren) {
            try checkCancelledBeforeRelationshipWrite()
            parent.content_children = mergedChildren
        }

        return mergedChildren
    }

    // MARK: - Personality

    @discardableResult
    nonisolated static func upsertPersonality(
        from dto: PersonalityDTO,
        in ctx: ModelContext
    ) throws -> Personality {

        try checkCancelled()

        let personality = try fetchOrInsert(Personality.self, id: dto.id, in: ctx) {
            Personality(id: dto.id)
        }

        personality.created_at = dto.created_at ?? personality.created_at
        personality.updated_at = dto.updated_at ?? personality.updated_at
        personality.name = dto.name
        personality.desc = dto.description
        personality.badge_title = dto.badge_title
        personality.badge_gradient_css = dto.badge_gradient_css
        personality.badge_text_color_hex = dto.badge_text_color_hex

        if let mediaDTO = dto.primary_media {
            try checkCancelled()
            let media = try upsertMedia(from: mediaDTO, in: ctx)

            try checkCancelledBeforeRelationshipWrite()
            if personality.primary_media !== media {
                personality.primary_media = media
            }
        } else {
            try checkCancelledBeforeRelationshipWrite()
            if personality.primary_media != nil {
                personality.primary_media = nil
            }
        }

        return personality
    }


    @discardableResult
    nonisolated static func upsertPersonalityContentAssociations(
        personalityID: Int,
        from associationDTOs: [ContentPersonalityAssociationDTO],
        replaceExisting: Bool = false,
        in ctx: ModelContext
    ) throws -> [ContentPersonalityAssociation] {

        try checkCancelled()

        let personality = try fetchOrInsert(Personality.self, id: personalityID, in: ctx) {
            Personality(id: personalityID)
        }

        var associationsByID: [Int: ContentPersonalityAssociation] = [:]
        var orderedAssociations: [ContentPersonalityAssociation] = []

        if !replaceExisting {
            for existingAssociation in personality.content_associations {
                associationsByID[existingAssociation.id] = existingAssociation
                orderedAssociations.append(existingAssociation)
            }
        }

        for associationDTO in associationDTOs {
            try checkCancelled()
            guard let contentDTO = associationDTO.content else { continue }

            let content = try upsertContent(
                from: contentDTO,
                parent: nil,
                includeChildren: false,
                includePersonalityAssociations: false,
                in: ctx
            )

            let association = try upsertContentPersonalityAssociation(
                from: associationDTO,
                content: content,
                personality: personality,
                in: ctx
            )

            if associationsByID[association.id] == nil {
                orderedAssociations.append(association)
            }

            associationsByID[association.id] = association
        }

        let mergedAssociations = orderedAssociations.compactMap { associationsByID[$0.id] }

        if replaceExisting {
            try deleteMissing(personality.content_associations, keeping: Set(mergedAssociations.map(\.id)), in: ctx)
        }

        if !sameIntIDs(personality.content_associations, mergedAssociations) {
            try checkCancelledBeforeRelationshipWrite()
            personality.content_associations = mergedAssociations
        }

        return mergedAssociations
    }

    // MARK: - Association rows

    @discardableResult
    nonisolated static func upsertContentPersonalityAssociation(
        from dto: ContentPersonalityAssociationDTO,
        content: ContentItem,
        personality: Personality,
        in ctx: ModelContext
    ) throws -> ContentPersonalityAssociation {

        try checkCancelled()

        let association = try fetchOrInsert(ContentPersonalityAssociation.self, id: dto.id, in: ctx) {
            ContentPersonalityAssociation(id: dto.id, content: content, personality: personality)
        }

        association.created_at = dto.created_at ?? association.created_at
        association.updated_at = dto.updated_at ?? association.updated_at
        association.relationship = dto.relationship
        association.order = dto.order
        association.content_id = content.id
        association.personality_id = personality.id

        try checkCancelledBeforeRelationshipWrite()
        if association.content?.id != content.id {
            association.content = content
        }
        if association.personality?.id != personality.id {
            association.personality = personality
        }

        return association
    }

    @discardableResult
    nonisolated static func upsertContentVariantAssociation(
        from dto: ContentVariantAssociationDTO,
        content: ContentItem,
        in ctx: ModelContext
    ) throws -> ContentVariantAssociation {

        try checkCancelled()

        let association = try fetchOrInsert(ContentVariantAssociation.self, id: dto.id, in: ctx) {
            ContentVariantAssociation(id: dto.id, content: content)
        }

        association.created_at = dto.created_at ?? association.created_at
        association.updated_at = dto.updated_at ?? association.updated_at
        association.order = dto.order
        association.content_id = content.id

        try checkCancelledBeforeRelationshipWrite()
        if association.content?.id != content.id {
            association.content = content
        }

        association.product_id = dto.product_id
        association.variant_id = dto.variant_id

        // Variant details now come from dto.products_cache, which is upserted before associations.
        // Keep this association as a lightweight link by id.
        let variant = try dto.variant_id.flatMap { try Storage.fetchById(Variant.self, id: $0, in: ctx) }

        try checkCancelledBeforeRelationshipWrite()
        if association.variant?.id != variant?.id {
            association.variant = variant
        }

        association.variant_year = nil
        association.variant_price = nil
        association.variant_num_dollar_signs = nil
        association.variant_fresh = nil
        association.variant_recommendable = nil
        association.variant_deleted_on_curation = nil
        association.variant_primary_image = nil
        association.variant_images = []

        return association
    }

    @discardableResult
    nonisolated static func upsertContentChannelAssociation(
        from dto: ContentChannelAssociationDTO,
        content: ContentItem,
        in ctx: ModelContext
    ) throws -> ContentChannelAssociation {

        try checkCancelled()

        let association = try fetchOrInsert(ContentChannelAssociation.self, id: dto.id, in: ctx) {
            ContentChannelAssociation(id: dto.id, content: content)
        }

        association.created_at = dto.created_at ?? association.created_at
        association.updated_at = dto.updated_at ?? association.updated_at
        association.order = dto.order
        association.content_id = content.id

        try checkCancelledBeforeRelationshipWrite()
        if association.content?.id != content.id {
            association.content = content
        }

        if let channelDTO = dto.channel {
            let channel = try upsertChannel(from: channelDTO, in: ctx)
            association.channel_id = channel.id

            try checkCancelledBeforeRelationshipWrite()
            if association.channel?.id != channel.id {
                association.channel = channel
            }
        } else {
            association.channel_id = nil

            try checkCancelledBeforeRelationshipWrite()
            association.channel = nil
        }

        return association
    }

    @discardableResult
    nonisolated static func upsertContentVenueAssociation(
        from dto: ContentVenueAssociationDTO,
        content: ContentItem,
        in ctx: ModelContext
    ) throws -> ContentVenueAssociation {

        try checkCancelled()

        let association = try fetchOrInsert(ContentVenueAssociation.self, id: dto.id, in: ctx) {
            ContentVenueAssociation(id: dto.id, content: content)
        }

        association.created_at = dto.created_at ?? association.created_at
        association.updated_at = dto.updated_at ?? association.updated_at
        association.order = dto.order
        association.content_id = content.id

        try checkCancelledBeforeRelationshipWrite()
        if association.content?.id != content.id {
            association.content = content
        }

        association.venue_id = dto.venue_id

        // Venue details now come from dto.venues_cache, which is upserted before associations.
        let venue = try dto.venue_id.flatMap { try Storage.fetchById(Venue.self, id: $0, in: ctx) }

        try checkCancelledBeforeRelationshipWrite()
        if association.venue?.id != venue?.id {
            association.venue = venue
        }

        return association
    }

    @discardableResult
    nonisolated static func upsertContentExperienceAssociation(
        from dto: ContentExperienceAssociationDTO,
        content: ContentItem,
        in ctx: ModelContext
    ) throws -> ContentExperienceAssociation {

        try checkCancelled()

        let association = try fetchOrInsert(ContentExperienceAssociation.self, id: dto.id, in: ctx) {
            ContentExperienceAssociation(id: dto.id, content: content)
        }

        association.created_at = dto.created_at ?? association.created_at
        association.updated_at = dto.updated_at ?? association.updated_at
        association.order = dto.order
        association.content_id = content.id

        try checkCancelledBeforeRelationshipWrite()
        if association.content?.id != content.id {
            association.content = content
        }

        guard let experienceDTO = dto.experience else {
            association.experience_id = nil
            try checkCancelledBeforeRelationshipWrite()
            association.experience = nil
            return association
        }

        association.experience_id = experienceDTO.id

        let experience: Experience?
        if let venueID = experienceDTO.preferabli_venue_id,
           let venue = try Storage.fetchById(Venue.self, id: venueID, in: ctx) {
            experience = try upsertExperience(from: experienceDTO, venue: venue, in: ctx)
        } else if let existingExperience = try Storage.fetchById(Experience.self, id: experienceDTO.id, in: ctx) {
            experience = try upsertExperience(from: experienceDTO, venue: existingExperience.venue, in: ctx)
        } else {
            experience = nil
        }

        try checkCancelledBeforeRelationshipWrite()
        if association.experience?.id != experience?.id {
            association.experience = experience
        }

        return association
    }

    @discardableResult
    nonisolated static func upsertContentMarketTraitAssociation(
        from dto: ContentMarketTraitAssociationDTO,
        content: ContentItem,
        in ctx: ModelContext
    ) throws -> ContentMarketTraitAssociation {

        try checkCancelled()

        let association = try fetchOrInsert(ContentMarketTraitAssociation.self, id: dto.id, in: ctx) {
            ContentMarketTraitAssociation(id: dto.id, content: content)
        }

        association.created_at = dto.created_at ?? association.created_at
        association.updated_at = dto.updated_at ?? association.updated_at
        association.order = dto.order
        association.content_id = content.id

        try checkCancelledBeforeRelationshipWrite()
        if association.content?.id != content.id {
            association.content = content
        }

        if let traitDTO = dto.market_trait {
            let trait = try upsertMarketTraitReference(from: traitDTO, in: ctx)
            association.market_trait_id = trait.id

            try checkCancelledBeforeRelationshipWrite()
            if association.market_trait?.id != trait.id {
                association.market_trait = trait
            }
        } else {
            association.market_trait_id = nil

            try checkCancelledBeforeRelationshipWrite()
            association.market_trait = nil
        }

        return association
    }

    // MARK: - Reference helpers

    @discardableResult
    nonisolated static func upsertMarketTraitReference(
        from dto: MarketTraitDTO,
        in ctx: ModelContext
    ) throws -> MarketTrait {

        try checkCancelled()

        let trait = try fetchOrInsert(MarketTrait.self, id: dto.id, in: ctx) {
            MarketTrait(id: dto.id)
        }

        trait.type = dto.type ?? trait.type
        trait.name = dto.name ?? trait.name
        trait.icon_url = dto.icon_url ?? trait.icon_url
        trait.created_at = dto.created_at ?? trait.created_at
        trait.updated_at = dto.updated_at ?? trait.updated_at

        return trait
    }

    nonisolated private static func deleteMissing<T: HasIntID>(
        _ existing: [T],
        keeping keepIDs: Set<Int>,
        in ctx: ModelContext
    ) throws {
        for object in existing where !keepIDs.contains(object.id) {
            try checkCancelled()
            try checkCancelledBeforeRelationshipWrite()
            ctx.delete(object)
        }
    }
}
