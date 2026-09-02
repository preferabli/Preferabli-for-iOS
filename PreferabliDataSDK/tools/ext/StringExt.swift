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

private enum HTMLListType {
    case unordered
    case ordered(currentNumber: Int)
}

private enum HTMLHeadingLevel {
    case h1
    case h2
    case h3
}

extension String {
    public func formattedHTMLString(
        baseColor: Color = .black,
        linkColor: Color,
        regularFont: Font,
        boldFont: Font,
        heading1Font: Font,
        heading2Font: Font,
        heading3Font: Font
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

        var boldDepth = 0
        var underlineDepth = 0
        var strikethroughDepth = 0
        var ignoredContentDepth = 0

        var currentHeading: HTMLHeadingLevel?
        var currentLinkURL: URL?
        var listStack: [HTMLListType] = []
        var listItemDepth = 0

        func selectedFont() -> Font {
            switch currentHeading {
            case .h1:
                return heading1Font

            case .h2:
                return heading2Font

            case .h3:
                return heading3Font

            case nil:
                return boldDepth > 0
                    ? boldFont
                    : regularFont
            }
        }

        func makePiece(
            _ text: String,
            font: Font
        ) -> AttributedString {
            var piece = AttributedString(text)
            piece.foregroundColor = baseColor
            piece.font = font
            return piece
        }

        func trailingNewlineCount() -> Int {
            result.characters
                .reversed()
                .prefix { $0.isNewline }
                .count
        }

        func appendNewline() {
            guard !result.characters.isEmpty else {
                return
            }

            guard trailingNewlineCount() == 0 else {
                return
            }

            result.append(
                makePiece(
                    "\n",
                    font: regularFont
                )
            )
        }

        func appendParagraphBreak() {
            guard !result.characters.isEmpty else {
                return
            }

            let currentTrailingNewlines = trailingNewlineCount()

            guard currentTrailingNewlines < 2 else {
                return
            }

            result.append(
                makePiece(
                    String(
                        repeating: "\n",
                        count: 2 - currentTrailingNewlines
                    ),
                    font: regularFont
                )
            )
        }

        func appendListItemPrefix() {
            if !result.characters.isEmpty {
                appendNewline()
            }

            let indentation = String(
                repeating: "    ",
                count: max(0, listStack.count - 1)
            )

            let prefix: String

            if let lastIndex = listStack.indices.last {
                switch listStack[lastIndex] {
                case .unordered:
                    prefix = "\(indentation)• "

                case .ordered(let currentNumber):
                    let nextNumber = currentNumber + 1

                    listStack[lastIndex] = .ordered(
                        currentNumber: nextNumber
                    )

                    prefix = "\(indentation)\(nextNumber). "
                }
            } else {
                prefix = "• "
            }

            result.append(
                makePiece(
                    prefix,
                    font: regularFont
                )
            )
        }

        func trimTrailingNewlines() {
            while result.characters.last?.isNewline == true {
                result.characters.removeLast()
            }
        }

        func parsedTag(from token: String) -> (
            name: String,
            isClosing: Bool
        )? {
            let lowercasedToken = token
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard lowercasedToken.hasPrefix("<") else {
                return nil
            }

            let isClosing = lowercasedToken.hasPrefix("</")
            let pattern = #"^</?\s*([a-z0-9]+)"#

            guard
                let regex = try? NSRegularExpression(
                    pattern: pattern,
                    options: [.caseInsensitive]
                ),
                let match = regex.firstMatch(
                    in: lowercasedToken,
                    range: NSRange(
                        lowercasedToken.startIndex..<lowercasedToken.endIndex,
                        in: lowercasedToken
                    )
                ),
                match.numberOfRanges > 1,
                let nameRange = Range(
                    match.range(at: 1),
                    in: lowercasedToken
                )
            else {
                return nil
            }

            return (
                name: String(lowercasedToken[nameRange]),
                isClosing: isClosing
            )
        }

        func hyperlinkURL(from anchorTag: String) -> URL? {
            let pattern = #"\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#

            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else {
                return nil
            }

            let range = NSRange(
                anchorTag.startIndex..<anchorTag.endIndex,
                in: anchorTag
            )

            guard let match = regex.firstMatch(
                in: anchorTag,
                range: range
            ) else {
                return nil
            }

            var href: String?

            for captureIndex in 1..<match.numberOfRanges {
                let captureRange = match.range(at: captureIndex)

                guard
                    captureRange.location != NSNotFound,
                    let swiftRange = Range(
                        captureRange,
                        in: anchorTag
                    )
                else {
                    continue
                }

                href = String(anchorTag[swiftRange])
                break
            }

            guard let href else {
                return nil
            }

            let decodedHref = href
                .htmlEntityDecoded
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard
                !decodedHref.isEmpty,
                let url = URL(string: decodedHref),
                let scheme = url.scheme?.lowercased()
            else {
                return nil
            }

            let supportedSchemes: Set<String> = [
                "http",
                "https",
                "mailto",
                "tel",
                "tastefuliapp"
            ]

            guard supportedSchemes.contains(scheme) else {
                return nil
            }

            return url
        }

        let pattern = #"(<[^>]+>|[^<]+)"#

        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return makePiece(
                html.htmlEntityDecoded,
                font: regularFont
            )
        }

        let fullRange = NSRange(
            html.startIndex..<html.endIndex,
            in: html
        )

        regex.enumerateMatches(
            in: html,
            range: fullRange
        ) { match, _, _ in
            guard
                let match,
                let swiftRange = Range(
                    match.range,
                    in: html
                )
            else {
                return
            }

            let token = String(html[swiftRange])

            if let tag = parsedTag(from: token) {
                let ignoredContentTags: Set<String> = [
                    "head",
                    "script",
                    "style"
                ]

                if ignoredContentTags.contains(tag.name) {
                    if tag.isClosing {
                        ignoredContentDepth = max(
                            0,
                            ignoredContentDepth - 1
                        )
                    } else {
                        ignoredContentDepth += 1
                    }

                    return
                }

                guard ignoredContentDepth == 0 else {
                    return
                }

                switch tag.name {
                case "strong", "b":
                    if tag.isClosing {
                        boldDepth = max(
                            0,
                            boldDepth - 1
                        )
                    } else {
                        boldDepth += 1
                    }

                case "u":
                    if tag.isClosing {
                        underlineDepth = max(
                            0,
                            underlineDepth - 1
                        )
                    } else {
                        underlineDepth += 1
                    }

                case "s", "del", "strike":
                    if tag.isClosing {
                        strikethroughDepth = max(
                            0,
                            strikethroughDepth - 1
                        )
                    } else {
                        strikethroughDepth += 1
                    }

                case "i", "em":
                    // Goli does not have an italic font.
                    // Keep the text but ignore italic styling.
                    break

                case "a":
                    if tag.isClosing {
                        currentLinkURL = nil
                    } else {
                        currentLinkURL = hyperlinkURL(
                            from: token
                        )
                    }

                case "h1":
                    if tag.isClosing {
                        currentHeading = nil
                        appendParagraphBreak()
                    } else {
                        if !result.characters.isEmpty {
                            appendParagraphBreak()
                        }

                        currentHeading = .h1
                    }

                case "h2":
                    if tag.isClosing {
                        currentHeading = nil
                        appendParagraphBreak()
                    } else {
                        if !result.characters.isEmpty {
                            appendParagraphBreak()
                        }

                        currentHeading = .h2
                    }

                case "h3":
                    if tag.isClosing {
                        currentHeading = nil
                        appendParagraphBreak()
                    } else {
                        if !result.characters.isEmpty {
                            appendParagraphBreak()
                        }

                        currentHeading = .h3
                    }

                case "br":
                    appendNewline()

                case "p", "div":
                    if listItemDepth > 0 {
                        if tag.isClosing {
                            appendNewline()
                        }
                    } else {
                        if tag.isClosing {
                            appendParagraphBreak()
                        } else if !result.characters.isEmpty {
                            appendParagraphBreak()
                        }
                    }

                case "ul":
                    if tag.isClosing {
                        if !listStack.isEmpty {
                            listStack.removeLast()
                        }

                        appendParagraphBreak()
                    } else {
                        listStack.append(.unordered)
                    }

                case "ol":
                    if tag.isClosing {
                        if !listStack.isEmpty {
                            listStack.removeLast()
                        }

                        appendParagraphBreak()
                    } else {
                        listStack.append(
                            .ordered(currentNumber: 0)
                        )
                    }

                case "li":
                    if tag.isClosing {
                        listItemDepth = max(
                            0,
                            listItemDepth - 1
                        )
                        appendNewline()
                    } else {
                        appendListItemPrefix()
                        listItemDepth += 1
                    }

                default:
                    break
                }

                return
            }

            guard ignoredContentDepth == 0 else {
                return
            }

            let decodedText = token.htmlEntityDecoded

            guard !decodedText.isEmpty else {
                return
            }

            var piece = makePiece(
                decodedText,
                font: selectedFont()
            )

            if underlineDepth > 0 || currentLinkURL != nil {
                piece.underlineStyle = .single
            }

            if strikethroughDepth > 0 {
                piece.strikethroughStyle = .single
            }

            if let currentLinkURL {
                piece.link = currentLinkURL
                piece.foregroundColor = linkColor
            }

            result.append(piece)
        }

        trimTrailingNewlines()

        return result
    }

    private var htmlEntityDecoded: String {
        var decoded = self

        let namedEntities: [String: String] = [
            "&amp;": "&",
            "&quot;": "\"",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " ",
            "&bull;": "•",
            "&copy;": "©",
            "&reg;": "®",
            "&trade;": "™",
            "&hellip;": "…",
            "&ndash;": "–",
            "&mdash;": "—",
            "&lsquo;": "‘",
            "&rsquo;": "’",
            "&ldquo;": "“",
            "&rdquo;": "”",
            "&euro;": "€",
            "&pound;": "£",
            "&yen;": "¥",
            "&cent;": "¢",
            "&deg;": "°",
            "&plusmn;": "±",
            "&times;": "×",
            "&divide;": "÷"
        ]

        for (entity, replacement) in namedEntities {
            decoded = decoded.replacingOccurrences(
                of: entity,
                with: replacement,
                options: [.caseInsensitive]
            )
        }

        decoded = decoded.decodingNumericHTMLEntities()

        return decoded
    }

    private func decodingNumericHTMLEntities() -> String {
        let pattern = #"&#(?:x([0-9a-fA-F]+)|([0-9]+));"#

        guard let regex = try? NSRegularExpression(
            pattern: pattern
        ) else {
            return self
        }

        var output = self

        let matches = regex.matches(
            in: output,
            range: NSRange(
                output.startIndex..<output.endIndex,
                in: output
            )
        )

        for match in matches.reversed() {
            guard
                let fullRange = Range(
                    match.range(at: 0),
                    in: output
                )
            else {
                continue
            }

            let hexValue: String?

            if match.range(at: 1).location != NSNotFound,
               let range = Range(
                   match.range(at: 1),
                   in: output
               ) {
                hexValue = String(output[range])
            } else {
                hexValue = nil
            }

            let decimalValue: String?

            if match.range(at: 2).location != NSNotFound,
               let range = Range(
                   match.range(at: 2),
                   in: output
               ) {
                decimalValue = String(output[range])
            } else {
                decimalValue = nil
            }

            let scalarValue: UInt32?

            if let hexValue {
                scalarValue = UInt32(
                    hexValue,
                    radix: 16
                )
            } else if let decimalValue {
                scalarValue = UInt32(
                    decimalValue,
                    radix: 10
                )
            } else {
                scalarValue = nil
            }

            guard
                let scalarValue,
                let scalar = UnicodeScalar(scalarValue)
            else {
                continue
            }

            output.replaceSubrange(
                fullRange,
                with: String(Character(scalar))
            )
        }

        return output
    }
}
