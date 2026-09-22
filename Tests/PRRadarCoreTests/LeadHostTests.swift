import XCTest
@testable import PRRadarCore

/// Leads are keyed per host as well as per repo, because the app can be logged
/// in to github.com and an Enterprise host at the same time.
final class LeadHostTests: XCTestCase {

    // MARK: - Keys

    func testKeyCarriesTheHostAndIsLowercased() {
        XCTAssertEqual(Leads.key(host: "GitHub.com", repo: "Acme/Repo"),
                       "github.com/acme/repo")
    }

    /// The failure this exists to prevent: one lead list quietly shared by two
    /// different repositories that happen to spell their owner and name alike.
    func testSameRepoOnTwoHostsIsTwoKeys() {
        XCTAssertNotEqual(Leads.key(host: "github.com", repo: "acme/app"),
                          Leads.key(host: "ghe.acme.com", repo: "acme/app"))
    }

    func testLeadsAreNotSharedAcrossHosts() {
        let all = Leads.add("alice", to: "acme/app", host: "github.com", in: [:])
        XCTAssertEqual(Leads.leads(for: "acme/app", host: "github.com", in: all), ["alice"])
        XCTAssertEqual(Leads.leads(for: "acme/app", host: "ghe.acme.com", in: all), [])
    }

    // MARK: - The pre-host key

    /// Anything stored before hosts existed was keyed `owner/repo`, and has to
    /// keep working until it is next edited — otherwise upgrading silently
    /// drops every lead and every gated PR stops being gated.
    func testUnqualifiedKeyStillReads() {
        let all = ["acme/app": ["alice"]]
        XCTAssertEqual(Leads.leads(for: "Acme/App", host: "github.com", in: all), ["alice"])
    }

    /// A qualified entry wins, so a repo edited once is never read from the old
    /// key again.
    func testQualifiedKeyBeatsTheOldOne() {
        let all = ["acme/app": ["alice"], "github.com/acme/app": ["bob"]]
        XCTAssertEqual(Leads.leads(for: "acme/app", host: "github.com", in: all), ["bob"])
    }

    /// Editing migrates: the new key is written and the old one cleared, so the
    /// two cannot disagree afterwards.
    func testEditingMigratesOffTheOldKey() {
        var all = ["acme/app": ["alice"]]
        all = Leads.add("bob", to: "acme/app", host: "github.com", in: all)
        XCTAssertEqual(all["github.com/acme/app"], ["alice", "bob"])

        all = Leads.remove("alice", from: "acme/app", host: "github.com", in: all)
        XCTAssertNil(all["acme/app"])
        XCTAssertEqual(all["github.com/acme/app"], ["bob"])
    }

    /// Removing the last lead from a migrating list must not leave the old key
    /// behind to be read back as live.
    func testRemovingTheLastLeadClearsBothKeys() {
        var all = ["acme/app": ["alice"]]
        all = Leads.remove("alice", from: "acme/app", host: "github.com", in: all)
        XCTAssertNil(all["acme/app"])
        XCTAssertNil(all["github.com/acme/app"])
        XCTAssertEqual(Leads.leads(for: "acme/app", host: "github.com", in: all), [])
    }

    // MARK: - The inbox

    func testInboxGatesOnItsOwnHost() {
        let leads = ["ghe.acme.com/acme/app": ["alice"]]
        XCTAssertEqual(MyPRInbox(leads: leads, host: "ghe.acme.com").host, "ghe.acme.com")
        XCTAssertEqual(MyPRInbox(leads: leads).host, Leads.defaultHost)
    }

    // MARK: - Host of an account id

    func testHostIsReadOffAnAccountID() {
        XCTAssertEqual(Accounts.host(ofID: "github.com/octocat"), "github.com")
        XCTAssertEqual(Accounts.host(ofID: "ghe.acme.com/octocat"), "ghe.acme.com")
    }

    /// The stand-in account used when `gh` cannot be asked carries no id, and a
    /// repo seen through it is a github.com repo until something says otherwise.
    func testAnEmptyIDFallsBackToTheDefaultHost() {
        XCTAssertEqual(Accounts.host(ofID: ""), Leads.defaultHost)
        XCTAssertEqual(Accounts.host(ofID: "/octocat"), Leads.defaultHost)
    }

    // MARK: - RepoRef

    func testRefLabelHidesTheDefaultHostOnly() {
        XCTAssertEqual(RepoRef(repo: "acme/app").label, "acme/app")
        XCTAssertEqual(RepoRef(repo: "acme/app", host: "ghe.acme.com").label,
                       "acme/app (ghe.acme.com)")
    }

    func testRefIDMatchesTheLeadKey() {
        let ref = RepoRef(repo: "Acme/App", host: "GitHub.com")
        XCTAssertEqual(ref.id, Leads.key(host: "GitHub.com", repo: "Acme/App"))
    }

    /// Two hosts, one spelling: they must not collapse into one row.
    func testRefsOnTwoHostsAreDistinct() {
        let a = RepoRef(repo: "acme/app", host: "github.com")
        let b = RepoRef(repo: "acme/app", host: "ghe.acme.com")
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(Set([a, b]).count, 2)
    }
}
