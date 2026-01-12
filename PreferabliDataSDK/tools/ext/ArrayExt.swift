//
//  ArrayExt.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 12/11/25.
//

extension Array {
    public func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var result: [[Element]] = []
        var i = 0
        
        while i < count {
            let end = Swift.min(i + size, count)
            result.append(Array(self[i..<end]))
            i = end
        }
        return result
    }
}
