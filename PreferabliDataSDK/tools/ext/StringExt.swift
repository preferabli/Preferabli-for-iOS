//
//  StringExt.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 11/18/16.
//  Copyright © 2025 Preferabli, Inc. All rights reserved.
//

import Foundation
import UIKit
import SwiftUI

extension NSAttributedString {
    public func isEmptyOrWhitespace() -> Bool {
        return length == .zero
    }
}

extension String {
    public func matches(_ pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(startIndex..., in: self)

        return regex.matches(in: self, range: range).compactMap {
            guard let bodyRange = Range($0.range(at: 1), in: self) else { return nil }
            return String(self[bodyRange])
        }
    }
}

extension String {
    
    public var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    public var flagEmoji: String {
        let upper = self.uppercased()
        guard upper.count == 2, upper.unicodeScalars.allSatisfy({ ("A"..."Z").contains(Character($0)) }) else {
            return "🏳️" // fallback
        }
        let base: UInt32 = 127397 // 127462 ("🇦") - 65 ("A")
        let scalars = upper.unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }
        return String(String.UnicodeScalarView(scalars))
    }
    
    func index(at offset: Int) -> String.Index {
        index(startIndex, offsetBy: offset)
      }
    
    subscript(offset: Int) -> Character {
            self[index(startIndex, offsetBy: offset)]
        }
    
    public func containsIgnoreCase(_ string : String) -> Bool {
        return self.lowercased().contains(string.lowercased())
    }
    
    public func isEmptyOrWhitespace() -> Bool {
        return self.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "").count == 0
    }
    
    public func capitalizingFirstLetter() -> String {
        return prefix(1).capitalized + dropFirst()
    }

    public mutating func capitalizeFirstLetter() {
        self = self.capitalizingFirstLetter()
    }
    
    public func lowercasingFirstLetter() -> String {
        return prefix(1).lowercased() + dropFirst()
    }

    public mutating func lowercaseFirstLetter() {
        self = self.lowercasingFirstLetter()
    }
    
    public var forSorting: String {
        let simple = folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: nil)
        let nonAlphaNumeric = CharacterSet.alphanumerics.inverted
        return simple.components(separatedBy: nonAlphaNumeric).joined(separator: "")
    }
    
    public static func sortStringsByLength(list: [String]) -> [String] {
        return list.sorted(by: { $0.count < $1.count })
    }
    
    public var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    
    public static func alphaSortIgnoreThe(x : String?, y : String?, comparisonResult: ComparisonResult? = ComparisonResult.orderedAscending) -> Bool {
        var x = x
        var y = y
        if (x.isEmptyOrWhitespace) {
            return false
        } else if (y.isEmptyOrWhitespace) {
            return true
        }
        if (x!.hasPrefix("The ")) {
            x = String(x![x!.index(x!.startIndex, offsetBy: 4)...])
        }
        if (y!.hasPrefix("The ")) {
            y = String(y![y!.index(x!.startIndex, offsetBy: 4)...])
        }
        
        return x!.caseInsensitiveCompare(y!) == comparisonResult
    }
    
    public func localizedOrSelf(table: String? = nil, bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: self, value: self, table: table)
    }
}

extension Optional where Wrapped: Swift.Collection {
    public var isEmptyOrWhitespace: Bool {
        self?.isEmpty ?? true
    }
}

extension String {
    public func formattedHTMLString(
        baseColor: Color = .black
    ) -> AttributedString {
        var html = trimmingCharacters(in: .whitespacesAndNewlines)

        if html.hasPrefix("\""), html.hasSuffix("\"") {
            html.removeFirst()
            html.removeLast()
        }

        html = html
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        var result = AttributedString()
        var isBold = false

        let pattern = #"(<[^>]+>|[^<]+)"#
        let regex = try? NSRegularExpression(pattern: pattern)

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)

        regex?.enumerateMatches(in: html, range: nsRange) { match, _, _ in
            guard
                let match,
                let range = Range(match.range, in: html)
            else { return }

            let token = String(html[range])
            let lower = token.lowercased()

            switch lower {
            case "<strong>", "<b>":
                isBold = true

            case "</strong>", "</b>":
                isBold = false

            case "<br>", "<br/>", "<br />", "</p>":
                result.append(AttributedString("\n\n"))

            default:
                guard !token.hasPrefix("<") else { return }

                var piece = AttributedString(token.htmlEntityDecoded)
                piece.foregroundColor = baseColor

                if isBold {
                    piece.font = .system(.body).bold()
                }

                result.append(piece)
            }
        }

        return result
    }

    private var htmlEntityDecoded: String {
        self
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
