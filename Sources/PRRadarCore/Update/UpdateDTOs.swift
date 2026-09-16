import Foundation

public struct LatestReleasePayload: Decodable {
    public let repository: ReleaseRepository?
}

public struct ReleaseRepository: Decodable {
    public let latestRelease: ReleaseNode?
}

public struct ReleaseNode: Decodable {
    public let tagName: String?
    public let name: String?
    public let url: String?
    public let publishedAt: Date?
}
