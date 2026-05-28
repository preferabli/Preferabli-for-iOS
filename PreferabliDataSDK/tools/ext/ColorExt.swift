//
//  ColorExt.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 10/17/25.
//

import Foundation
import UIKit
import SwiftUI

extension Color {
    public init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
    
    // Renamed to avoid overload ambiguity with init(hex: String)
    public init?(optionalHex: String?) {
        guard var hex = optionalHex?.trimmingCharacters(in: .whitespacesAndNewlines),
              !hex.isEmpty else { return nil }

        if hex.hasPrefix("#") { hex.removeFirst() }
        hex = hex.uppercased()

        self.init(hex: hex)
    }
    
    func toHex(includeAlpha: Bool = false) -> String? {
        UIColor(self).toHex(includeAlpha: includeAlpha)
    }
    
    /// Darken by blending toward black (0.0–1.0)
    public func darkened(_ amount: CGFloat) -> Color {
        mixed(with: .black, amount: amount)
    }
    
    public func mixed(with other: Color, amount: CGFloat) -> Color {
        let t = max(0, min(1, amount))
        return Color(uiColor: UIColor(self).mixed(with: UIColor(other), amount: t))
    }
}

extension UIColor {
    public var rgba: (CGFloat, CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
    
    /// Linear blend: amount = 0 → self, amount = 1 → other
    public func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        let t = max(0, min(1, amount))
        return UIColor(
            red:   r1 * (1 - t) + r2 * t,
            green: g1 * (1 - t) + g2 * t,
            blue:  b1 * (1 - t) + b2 * t,
            alpha: a1 * (1 - t) + a2 * t
        )
    }

    /// Keep only `strength` of the original color power, mix the rest with white.
    public func lightenedForCardTone(strength: CGFloat = 0.15) -> UIColor {
        return mixed(with: .white, amount: 1 - strength)
    }
    
    public func packRGB() -> Int {
        let (r, g, b, _) = self.rgba
        return (Int(r * 255) << 16) | (Int(g * 255) << 8) | Int(b * 255)
    }

    /// Unpacks an RGB Int (0xRRGGBB) into a UIColor
    public static func unpackRGB(_ value: Int) -> UIColor {
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }
    
    public func toHex(includeAlpha: Bool = false) -> String? {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        guard self.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return nil   // Color couldn’t be converted (e.g. system color)
        }
        
        if includeAlpha {
            let rgba = (Int)(r * 255) << 24 |
                       (Int)(g * 255) << 16 |
                       (Int)(b * 255) << 8  |
                       (Int)(a * 255)
            return String(format: "#%08X", rgba)
        } else {
            let rgb = (Int)(r * 255) << 16 |
                      (Int)(g * 255) << 8  |
                      (Int)(b * 255)
            return String(format: "#%06X", rgb)
        }
    }
}

extension UIImage {
    /// Draws a circular initials avatar with provided colors.
    public static func initialsAvatar(
        initials: String,
        diameter: CGFloat,
        backgroundColor: UIColor,
        textColor: UIColor,
        fontWeight: UIFont.Weight = .semibold
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter), format: format)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: CGSize(width: diameter, height: diameter))

            // Circle fill
            backgroundColor.setFill()
            UIBezierPath(ovalIn: rect).fill()

            // Initials text
            let fontSize = diameter * 0.34
            let font = UIFont.systemFont(ofSize: fontSize, weight: fontWeight)

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraph
            ]

            // Slight vertical tweak tends to look better for 2 letters
            let text = initials.uppercased()
            let textSize = text.size(withAttributes: attrs)
            let textRect = CGRect(
                x: (diameter - textSize.width) / 2,
                y: (diameter - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )

            text.draw(in: textRect, withAttributes: attrs)
        }
    }
}

extension UIColor {
    /// Supports: "#RRGGBB", "RRGGBB", "#AARRGGBB", "AARRGGBB"
    convenience init?(hex: String?) {
        guard var hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines),
              !hex.isEmpty else { return nil }

        if hex.hasPrefix("#") { hex.removeFirst() }
        hex = hex.uppercased()

        var value: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&value) else { return nil }

        let r, g, b, a: CGFloat
        switch hex.count {
        case 6: // RRGGBB
            a = 1.0
            r = CGFloat((value & 0xFF0000) >> 16) / 255.0
            g = CGFloat((value & 0x00FF00) >> 8) / 255.0
            b = CGFloat(value & 0x0000FF) / 255.0
        case 8: // AARRGGBB
            a = CGFloat((value & 0xFF000000) >> 24) / 255.0
            r = CGFloat((value & 0x00FF0000) >> 16) / 255.0
            g = CGFloat((value & 0x0000FF00) >> 8) / 255.0
            b = CGFloat(value & 0x000000FF) / 255.0
        default:
            return nil
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }
    
    public var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        let ai = Int(round(a * 255))
        return String(format: "#%02X%02X%02X%02X", ri, gi, bi, ai)
    }
}

extension Color {
    public  func saturated(_ amount: CGFloat = 1.25) -> Color {
        UIColor(self).saturated(amount).swiftUIColor
    }
}

extension UIColor {
    public func saturated(_ amount: CGFloat = 1.25) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }

        return UIColor(
            hue: hue,
            saturation: min(saturation * amount, 1),
            brightness: brightness,
            alpha: alpha
        )
    }

    public  var swiftUIColor: Color {
        Color(uiColor: self)
    }
}
