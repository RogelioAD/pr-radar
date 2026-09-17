import XCTest
@testable import PRRadarCore

final class AccountTests: XCTestCase {

    /// Shape of `gh auth status --json hosts`, trimmed to the fields read.
    private func json(_ body: String) -> Data { Data(body.utf8) }

    private let twoAccounts = """
    {"hosts":{"github.com":[
      {"state":"success","active":true,"host":"github.com","login":"work"},
      {"state":"success","active":false,"host":"github.com","login":"personal"}
    ]}}
    """

    // MARK: - Parsing

    func testParsesEveryAccountNotJustTheActiveOne() {
        let accounts = Accounts.parse(statusJSON: json(twoAccounts))
        XCTAssertEqual(accounts.map(\.login), ["work", "personal"])
    }

    func testActiveAccountLeadsSoAnUpgradeKeepsTheFamiliarListFirst() {
        let accounts = Accounts.parse(statusJSON: json(twoAccounts))
        XCTAssertEqual(accounts.first?.login, "work")
        XCTAssertTrue(accounts.first?.isActive == true)
    }

    func testRemainingAccountsAreAlphabeticalNotInGHsOrder() {
        let accounts = Accounts.parse(statusJSON: json("""
        {"hosts":{"github.com":[
          {"state":"success","active":false,"host":"github.com","login":"zeta"},
          {"state":"success","active":true,"host":"github.com","login":"active"},
          {"state":"success","active":false,"host":"github.com","login":"alpha"}
        ]}}
        """))
        XCTAssertEqual(accounts.map(\.login), ["active", "alpha", "zeta"])
    }

    // MARK: - Health

    func testAReportedFailureIsUnhealthy() {
        let accounts = Accounts.parse(statusJSON: json("""
        {"hosts":{"github.com":[
          {"state":"error","active":true,"host":"github.com","login":"expired"}
        ]}}
        """))
        XCTAssertEqual(accounts.first?.isHealthy, false)
    }

    /// An unfamiliar state is not evidence of a working token. Treating anything
    /// but a reported success as unhealthy is what keeps a future `gh` wording
    /// from silently promoting a broken account to a working one.
    func testAnUnrecognisedStateIsUnhealthy() {
        let accounts = Accounts.parse(statusJSON: json("""
        {"hosts":{"github.com":[
          {"state":"reauthentication_required","active":true,"host":"github.com","login":"stale"}
        ]}}
        """))
        XCTAssertEqual(accounts.first?.isHealthy, false)
    }

    func testAMissingStateIsUnhealthyRatherThanDroppingTheAccount() {
        let accounts = Accounts.parse(statusJSON: json("""
        {"hosts":{"github.com":[{"active":true,"host":"github.com","login":"partial"}]}}
        """))
        XCTAssertEqual(accounts.map(\.login), ["partial"])
        XCTAssertEqual(accounts.first?.isHealthy, false)
    }

    func testAMissingActiveFlagIsNotActive() {
        let accounts = Accounts.parse(statusJSON: json("""
        {"hosts":{"github.com":[{"state":"success","host":"github.com","login":"unknown"}]}}
        """))
        XCTAssertEqual(accounts.first?.isActive, false)
    }

    // MARK: - Hosts

    func testHostComesFromTheKeySoAnEntryMissingItStillMatchesItsToken() {
        let accounts = Accounts.parse(statusJSON: json("""
        {"hosts":{"ghe.example.com":[{"state":"success","active":true,"login":"someone"}]}}
        """))
        XCTAssertEqual(accounts.first?.host, "ghe.example.com")
    }

    func testTheSameLoginOnTwoHostsIsTwoAccounts() {
        let accounts = Accounts.parse(statusJSON: json("""
        {"hosts":{
          "github.com":[{"state":"success","active":true,"host":"github.com","login":"sam"}],
          "ghe.example.com":[{"state":"success","active":false,"host":"ghe.example.com","login":"sam"}]
        }}
        """))
        XCTAssertEqual(Set(accounts.map(\.id)).count, 2)
    }

    // MARK: - Degrading

    /// Both return empty so `discover()` falls back to the active account. An
    /// empty account list must never reach the UI: it would render as "nothing
    /// is waiting on you", which is the one thing a broken lookup must not say.
    func testMalformedPayloadParsesToNothing() {
        XCTAssertTrue(Accounts.parse(statusJSON: json("not json at all")).isEmpty)
    }

    func testNoHostsParsesToNothing() {
        XCTAssertTrue(Accounts.parse(statusJSON: json(#"{"hosts":{}}"#)).isEmpty)
    }

    // MARK: - Scoping

    private struct Row: Equatable {
        let account: String
        let number: Int
    }

    private let rows = [
        Row(account: "work", number: 1),
        Row(account: "personal", number: 2),
        Row(account: "work", number: 3),
    ]

    func testNilAccountReturnsEverything() {
        XCTAssertEqual(AccountScope.apply(nil, to: rows, accountOf: \.account), rows)
    }

    func testFiltersToOneAccount() {
        let filtered = AccountScope.apply("work", to: rows, accountOf: \.account)
        XCTAssertEqual(filtered.map(\.number), [1, 3])
    }

    func testFilteringPreservesOrder() {
        let filtered = AccountScope.apply("work", to: rows, accountOf: \.account)
        XCTAssertEqual(filtered, [rows[0], rows[2]])
    }

    func testAnUnknownAccountMatchesNothingRatherThanEverything() {
        XCTAssertTrue(AccountScope.apply("nobody", to: rows, accountOf: \.account).isEmpty)
    }
}

// MARK: - Partial rounds

extension AccountTests {

    func testNothingFailedIsNotPartial() {
        XCTAssertFalse(AccountScope.isPartial(failed: [], scope: nil))
        XCTAssertFalse(AccountScope.isPartial(failed: [], scope: "github.com/work"))
    }

    func testUnscopedAnyFailureIsPartialBecauseTheListClaimsEverything() {
        XCTAssertTrue(AccountScope.isPartial(failed: ["github.com/personal"], scope: nil))
    }

    func testScopedToTheFailedAccountIsPartial() {
        XCTAssertTrue(AccountScope.isPartial(failed: ["github.com/personal"],
                                             scope: "github.com/personal"))
    }

    /// The case that decides whether the warning is worth obeying: looking at
    /// one account while a *different* one is unreachable changes nothing on
    /// screen, and warning anyway teaches the mark to be ignored.
    func testScopedToAHealthyAccountIsNotPartial() {
        XCTAssertFalse(AccountScope.isPartial(failed: ["github.com/personal"],
                                              scope: "github.com/work"))
    }
}

// MARK: - Scopes

extension AccountTests {

    private func account(scopes: String?) -> Account? {
        let field = scopes.map { "\"scopes\":\"\($0)\"," } ?? ""
        return Accounts.parse(statusJSON: Data("""
        {"hosts":{"github.com":[
          {"state":"success","active":true,"host":"github.com",\(field)"login":"a"}
        ]}}
        """.utf8)).first
    }

    func testScopesAreSplitOnTheComma() {
        XCTAssertEqual(account(scopes: "gist, read:org, repo")?.scopes,
                       ["gist", "read:org", "repo"])
    }

    func testReadOrgPresentMeansTeamsAreDiscoverable() {
        XCTAssertEqual(account(scopes: "read:org, repo")?.canReadTeams, true)
    }

    func testReadOrgAbsentMeansTeamsAreNot() {
        XCTAssertEqual(account(scopes: "gist, repo")?.canReadTeams, false)
    }

    /// Unknown is not absent. `gh` not reporting scopes must not produce a
    /// warning about a shortfall that may not exist — the opposite of how an
    /// unknown auth state is treated, and for a different consequence.
    func testUnreportedScopesAreUnknownNotMissing() {
        XCTAssertNil(account(scopes: nil)?.canReadTeams)
        XCTAssertNil(Accounts.activeFallback.canReadTeams)
    }

    /// Splitting on the comma rather than substring-searching the whole string
    /// is what keeps a scope whose name contains another's from reading as both.
    func testAScopeContainingAnothersNameDoesNotCount() {
        XCTAssertEqual(account(scopes: "gist, no-read:org-here, repo")?.canReadTeams,
                       false)
    }

    func testWhitespaceAndEmptyEntriesAreDropped() {
        XCTAssertEqual(account(scopes: "  repo ,, read:org  ")?.scopes,
                       ["repo", "read:org"])
    }
}

// MARK: - Merging across accounts

final class AccountMergeTests: XCTestCase {

    private struct Row: Identifiable, Equatable {
        let id: String
        let from: String
    }

    private func rows(_ from: String, _ ids: [String]) -> [Row] {
        ids.map { Row(id: $0, from: from) }
    }

    func testConcatenatesInAccountOrder() {
        let merged = AccountMerge.merge([rows("a", ["1", "2"]), rows("b", ["3"])])
        XCTAssertEqual(merged.map(\.id), ["1", "2", "3"])
    }

    func testOrderWithinAnAccountIsPreserved() {
        let merged = AccountMerge.merge([rows("a", ["9", "1", "5"])])
        XCTAssertEqual(merged.map(\.id), ["9", "1", "5"])
    }

    /// The case the type exists for: a review asked of a team both identities
    /// belong to arrives once per account with the same owner/repo#number. Left
    /// in, it inflates the badge and hands SwiftUI two rows with one id.
    func testARowSeenByTwoAccountsAppearsOnce() {
        let merged = AccountMerge.merge([rows("a", ["1", "2"]), rows("b", ["2", "3"])])
        XCTAssertEqual(merged.map(\.id), ["1", "2", "3"])
    }

    func testTheFirstAccountKeepsASharedRow() {
        let merged = AccountMerge.merge([rows("a", ["2"]), rows("b", ["2"])])
        XCTAssertEqual(merged.map(\.from), ["a"])
    }

    /// Load-bearing for the strip: the per-account counts only sum to the "All"
    /// count because a shared row is counted once, by its first account.
    func testMergedCountIsNotTheSumWhenARowIsShared() {
        let merged = AccountMerge.merge([rows("a", ["1", "2"]), rows("b", ["2"])])
        XCTAssertEqual(merged.count, 2)
    }

    func testEmptyAccountsContributeNothingAndBreakNothing() {
        let merged = AccountMerge.merge([rows("a", []), rows("b", ["1"]), rows("c", [])])
        XCTAssertEqual(merged.map(\.id), ["1"])
    }

    func testNoAccountsMergesToNothing() {
        XCTAssertTrue(AccountMerge.merge([[Row]]()).isEmpty)
    }

    func testADuplicateWithinOneAccountIsAlsoDropped() {
        let merged = AccountMerge.merge([rows("a", ["1", "1", "2"])])
        XCTAssertEqual(merged.map(\.id), ["1", "2"])
    }
}

// MARK: - Display names

extension AccountTests {

    func testAShortLoginIsLeftAlone() {
        XCTAssertEqual(Accounts.shortLogin("octocat"), "octocat")
    }

    func testALoginAtTheLimitIsLeftAlone() {
        XCTAssertEqual(Accounts.shortLogin(String(repeating: "x", count: 14)).count, 14)
    }

    /// Capped rather than allowed to truncate the repo name beside it.
    func testALongLoginIsCappedAndMarked() {
        let capped = Accounts.shortLogin("averylonggithublogin")
        XCTAssertEqual(capped.count, 14)
        XCTAssertTrue(capped.hasSuffix("…"))
    }
}
