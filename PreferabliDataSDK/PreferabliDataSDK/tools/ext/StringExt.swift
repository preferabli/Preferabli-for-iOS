//
//  StringExt.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 11/18/16.
//  Copyright © 2023 RingIT, Inc. All rights reserved.
//

import Foundation
import UIKit

extension NSAttributedString {
    public func isEmptyOrWhitespace() -> Bool {
        return length == .zero
    }
}

extension String {
    
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
}

extension Optional where Wrapped: Swift.Collection {
    public var isEmptyOrWhitespace: Bool {
        self?.isEmpty ?? true
    }
}

