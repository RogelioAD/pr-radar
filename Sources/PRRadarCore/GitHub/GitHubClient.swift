import Foundation

public enum GitHubClientError: LocalizedError {
    case badStatus(Int, String)
    case graphQL([String])
    case emptyPayload

    public var errorDescription: String? {
        switch self {
        case .badStatus(let code, let body):
            return "GitHub returned HTTP \(code): \(body.prefix(200))"
        case .graphQL(let messages):
            return "GraphQL error: \(messages.joined(separator: "; "))"
        case .emptyPayload:
            return "GitHub returned an empty payload"
        }
    }
}

public struct GitHubClient {
    private let token: String
    private let endpoint = URL(string: "https://api.github.com/graphql")!
    private let session: URLSession

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    public func run<T: Decodable>(_ query: String, as type: T.Type) async throws -> T {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("PRRadar", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        // Encoding through JSONEncoder keeps the embedded quotes in the
        // GraphQL document correctly escaped.
        request.httpBody = try JSONEncoder().encode(["query": query])

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw GitHubClientError.badStatus(http.statusCode, String(decoding: data, as: UTF8.self))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(GraphQLResponse<T>.self, from: data)
        if let errors = envelope.errors, !errors.isEmpty {
            throw GitHubClientError.graphQL(errors.map(\.message))
        }
        guard let payload = envelope.data else { throw GitHubClientError.emptyPayload }
        return payload
    }

    /// Resolves the viewer's login plus every team they belong to.
    public func fetchViewerAndTeams() async throws -> (login: String, teams: [TeamRef]) {
        // Two steps: `userLogins` needs a literal login, so learn it first.
        let bootstrap = try await run(
            "query { viewer { login organizations(first: 1) { nodes { login teams(first: 1) { nodes { slug } } } } } }",
            as: ViewerPayload.self
        )
        let login = bootstrap.viewer.login

        let payload = try await run(Query.viewerAndTeams(login: login), as: ViewerPayload.self)
        let teams = payload.viewer.organizations.nodes.flatMap { org in
            org.teams.nodes.map { TeamRef(org: org.login, slug: $0.slug) }
        }
        return (login, teams)
    }

    /// Fetches every search scope in a single request.
    public func fetchPullRequests(teams: [TeamRef]) async throws -> [String: SearchResult] {
        try await run(Query.pullRequests(teams: teams), as: [String: SearchResult].self)
    }

    /// The viewer's own open pull requests.
    public func fetchMyPullRequests() async throws -> MyPRSearchResult {
        try await run(Query.myPullRequests(), as: MyPRPayload.self).mine
    }

    /// How many pull requests the viewer has ever merged.
    ///
    /// Its own request rather than another alias on either existing document:
    /// both of those decode as homogeneous dictionaries of `SearchResult`, and
    /// a differently-shaped alias breaks them — the same reason
    /// `myPullRequests` is separate.
    public func fetchMergedCount() async throws -> Int {
        try await run(Query.mergedCount, as: MergedCountPayload.self).merged.issueCount
    }

    /// The latest published release of PR Radar itself.
    public func fetchLatestRelease(repo: String) async throws -> ReleaseNode? {
        guard let query = Query.latestRelease(repo: repo) else { return nil }
        return try await run(query, as: LatestReleasePayload.self)
            .repository?.latestRelease
    }

    /// Members of `repo` whose login or name matches `text`.
    public func searchMembers(repo: String, matching text: String) async throws -> [Member] {
        guard let query = Query.mentionableUsers(repo: repo, matching: text) else { return [] }
        return try await run(query, as: MembersPayload.self)
            .repository?.mentionableUsers.nodes ?? []
    }

    /// Second phase: how far behind each head branch is. Returns an empty
    /// dictionary when there is nothing to compare, and is allowed to fail
    /// independently of the main fetch — callers keep `behindBy` nil rather
    /// than claiming a branch is up to date.
    public func fetchCompares(for items: [MyPullRequest]) async throws -> [String: CompareResult] {
        let targets = items.map { (repo: $0.repo, base: $0.baseRefName, head: $0.headRefName) }
        guard let query = Query.compares(targets) else { return [:] }
        return try await run(query, as: [String: CompareResult].self)
    }
}
