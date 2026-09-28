import Foundation

/// A GraphQL variable.
///
/// A small closed union rather than `Any`, so the request body is `Encodable`
/// all the way down and a variable of the wrong shape is a compile error rather
/// than a 400 from GitHub.
public enum GraphQLValue: Encodable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case null
    case array([GraphQLValue])
    case object([String: GraphQLValue])

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let values): try container.encode(values)
        case .object(let values): try container.encode(values)
        }
    }
}

/// The request body. `variables` is omitted when there are none, so every
/// existing read query sends exactly the bytes it always did.
struct GraphQLRequest: Encodable {
    let query: String
    let variables: [String: GraphQLValue]?
}
