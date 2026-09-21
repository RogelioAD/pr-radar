import Foundation

// MARK: - GraphQL envelope

public struct GraphQLResponse<T: Decodable>: Decodable {
    public let data: T?
    public let errors: [GraphQLError]?
}

public struct GraphQLError: Decodable, Error {
    public let message: String
}

// MARK: - Pull request search payload
//
// The PR query uses one aliased `search` per scope, so `data` decodes as a
// dictionary keyed by alias rather than a fixed set of properties.

public struct SearchResult: Decodable {
    public let nodes: [PRNode]
}

/// A search asked only for its total. Shares no shape with `SearchResult`
/// on purpose — asking for `nodes` we would throw away is the kind of query
/// that grows a page of pull requests back into it a year later.
public struct CountResult: Decodable {
    public let issueCount: Int
}

public struct MergedCountPayload: Decodable {
    public let merged: CountResult
}

public struct PRNode: Decodable {
    public let number: Int?
    public let title: String?
    public let url: String?
    public let isDraft: Bool?
    public let author: ActorDTO?
    public let repository: RepoDTO?
    public let requests: TimelineConn?
    public let myReviews: TimelineConn?
    public let myComments: TimelineConn?
}

public struct ActorDTO: Decodable {
    public let login: String
    public let avatarUrl: String?
}

public struct RepoDTO: Decodable {
    public let nameWithOwner: String
}

public struct TimelineConn: Decodable {
    public let nodes: [TimelineNode]
}

public struct TimelineNode: Decodable {
    public let createdAt: Date?
    public let requestedReviewer: ReviewerDTO?
    public let author: ActorDTO?
    public let state: String?
}

/// `requestedReviewer` is a union of User and Team — `typename` says which,
/// and only the matching identity field is populated.
public struct ReviewerDTO: Decodable {
    public let typename: String
    public let login: String?
    public let slug: String?

    enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case login, slug
    }
}

// MARK: - Viewer / team discovery payload

public struct ViewerPayload: Decodable {
    public let viewer: ViewerDTO
}

public struct ViewerDTO: Decodable {
    public let login: String
    public let organizations: OrgConn
}

public struct OrgConn: Decodable {
    public let nodes: [OrgDTO]
}

public struct OrgDTO: Decodable {
    public let login: String
    public let teams: TeamConn
}

public struct TeamConn: Decodable {
    public let nodes: [TeamDTO]
}

public struct TeamDTO: Decodable {
    public let slug: String
}

public struct MembersPayload: Decodable {
    public let repository: MembersRepository?
}

public struct MembersRepository: Decodable {
    public let mentionableUsers: MemberConnection
}

public struct MemberConnection: Decodable {
    public let nodes: [Member]
}

public struct Member: Decodable, Identifiable, Equatable, Sendable {
    public let login: String
    public let name: String?

    public var id: String { login }

    public init(login: String, name: String?) {
        self.login = login
        self.name = name
    }
}
