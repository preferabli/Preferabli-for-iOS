//
//  SParams.swift
//  Preferabli
//
//  Created by Nicholas Bortolussi on 9/5/25.
//

// One shape for your params
typealias SParams = [String: Sendable]

enum ParamError: Error, CustomStringConvertible {
    case unsupportedValue(String, keyPath: String)
    var description: String {
        switch self {
        case .unsupportedValue(let type, let keyPath):
            return "Unsupported JSON value of type \(type) at \(keyPath)"
        }
    }
}

// JSON-normalization (recursive)
private func toJSONAny(_ v: Sendable, keyPath: String = "$") throws -> Any {
    switch v {
    case let s as String: return s
    case let b as Bool:   return b

    // Numbers
    case let n as Int:    return n
    case let n as Int8:   return Int(n)
    case let n as Int16:  return Int(n)
    case let n as Int32:  return Int(n)
    case let n as Int64:  return n
    case let n as UInt:   return n
    case let n as UInt8:  return Int(n)
    case let n as UInt16: return Int(n)
    case let n as UInt32: return Int(n)
    case let n as UInt64: return n
    case let n as Double: return n
    case let n as Float:  return Double(n)

    // Null
    case is NSNull:       return NSNull()

    // Arrays
    case let arr as [Sendable]:
        return try arr.enumerated().map { idx, el in
            try toJSONAny(el, keyPath: "\(keyPath)[\(idx)]")
        }

    // Dictionaries
    case let dict as [String: Sendable]:
        var out: [String: Any] = [:]
        for (k, val) in dict {
            out[k] = try toJSONAny(val, keyPath: "\(keyPath).\(k)")
        }
        return out

    default:
        throw ParamError.unsupportedValue("\(type(of: v))", keyPath: keyPath)
    }
}

private func toJSONAnyDict(_ params: SParams) throws -> [String: Any] {
    try toJSONAny(params) as! [String: Any]
}

// Query normalization (flat keys only; arrays joined by comma)
private func toQueryDict(_ params: SParams) throws -> [String: String] {
    var out: [String: String] = [:]
    for (k, v) in params {
        switch v {
        case let s as String: out[k] = s
        case let b as Bool: out[k] = b ? "true" : "false"
        case let n as Int: out[k] = String(n)
        case let n as Int64: out[k] = String(n)
        case let n as UInt: out[k] = String(n)
        case let n as UInt64: out[k] = String(n)
        case let n as Double: out[k] = String(n)
        case let n as Float: out[k] = String(n)
        case is NSNull: out[k] = ""
        case let arr as [Sendable]:
            // simple convention: join as comma list (adjust to your API’s expectations)
            out[k] = try arr.map { try toQueryLeaf($0) }.joined(separator: ",")
        default:
            throw ParamError.unsupportedValue("\(type(of: v))", keyPath: "$.\(k)")
        }
    }
    return out
}

private func toQueryLeaf(_ v: Sendable) throws -> String {
    switch v {
    case let s as String: return s
    case let b as Bool: return b ? "true" : "false"
    case let n as Int: return String(n)
    case let n as Int64: return String(n)
    case let n as UInt: return String(n)
    case let n as UInt64: return String(n)
    case let n as Double: return String(n)
    case let n as Float: return String(n)
    default:
        throw ParamError.unsupportedValue("\(type(of: v))", keyPath: "$[]")
    }
}
