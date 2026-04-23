//
//  StringExt.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 11/18/16.
//  Copyright © 2025 Preferabli, Inc. All rights reserved.
//

import Foundation
import UIKit

extension NSAttributedString {
    public func isEmptyOrWhitespace() -> Bool {
        return length == .zero
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

