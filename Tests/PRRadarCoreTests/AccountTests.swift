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
