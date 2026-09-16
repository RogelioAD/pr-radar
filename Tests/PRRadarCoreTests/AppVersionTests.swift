import XCTest
@testable import PRRadarCore

final class AppVersionTests: XCTestCase {

    func v(_ s: String) -> AppVersion { AppVersion(s)! }

    // MARK: - Parsing

    func testParsesPlainVersion() {
        XCTAssertEqual(v("1.2.3").components, [1, 2, 3])
        XCTAssertNil(v("1.2.3").preRelease)
    }

    /// Real GitHub tags look like `v2.101.0`.
    func testStripsTagPrefix() {
        XCTAssertEqual(v("v2.101.0").components, [2, 101, 0])
        XCTAssertEqual(v("V1.0.0").components, [1, 0, 0])
    }

    func testParsesPreRelease() {
        XCTAssertEqual(v("1.2.0-beta.1").components, [1, 2, 0])
        XCTAssertEqual(v("1.2.0-beta.1").preRelease, "beta.1")
    }

    func testIgnoresBuildMetadata() {
        XCTAssertEqual(v("1.2.3+build.55").components, [1, 2, 3])
        XCTAssertNil(v("1.2.3+build.55").preRelease)
    }

    func testTwoComponentVersions() {
        XCTAssertEqual(v("1.4").components, [1, 4])
    }

    func testRejectsNonsense() {
        for bad in ["", "   ", "abc", "1.x.3", "v", "1..3", "1.2.3.beta"] {
            XCTAssertNil(AppVersion(bad), "should reject \(bad.debugDescription)")
        }
    }

    func testDescriptionRoundTrips() {
        XCTAssertEqual(v("v1.2.3").description, "1.2.3")
        XCTAssertEqual(v("1.2.0-beta.1").description, "1.2.0-beta.1")
    }

    // MARK: - Comparison

    /// The trap: lexicographically "1.10.0" sorts before "1.9.0".
    func testDoubleDigitComponentsCompareNumerically() {
        XCTAssertGreaterThan(v("1.10.0"), v("1.9.0"))
        XCTAssertGreaterThan(v("2.101.0"), v("2.99.0"))
        XCTAssertLessThan(v("1.2.9"), v("1.2.10"))
    }

    func testOrdersByMajorThenMinorThenPatch() {
        XCTAssertGreaterThan(v("2.0.0"), v("1.99.99"))
        XCTAssertGreaterThan(v("1.3.0"), v("1.2.99"))
        XCTAssertGreaterThan(v("1.2.4"), v("1.2.3"))
    }

    /// The bundle says "1.0.0" while a tag says "v1.0" — they must be equal.
    func testMissingComponentsCountAsZero() {
        XCTAssertEqual(v("1.2"), v("1.2.0"))
        XCTAssertEqual(v("1"), v("1.0.0"))
        XCTAssertFalse(v("1.2") < v("1.2.0"))
        XCTAssertFalse(v("1.2.0") < v("1.2"))
    }

    func testPreReleasePrecedesItsRelease() {
        XCTAssertLessThan(v("1.2.0-beta"), v("1.2.0"))
        XCTAssertGreaterThan(v("1.2.0"), v("1.2.0-rc.1"))
    }

    func testPreReleasesOrderAmongThemselves() {
        XCTAssertLessThan(v("1.2.0-alpha"), v("1.2.0-beta"))
    }

    func testTagAndBundleVersionCompareAcrossFormats() {
        XCTAssertGreaterThan(v("v1.1.0"), v("1.0.0"),
                             "a prefixed tag must beat a bare bundle version")
        XCTAssertEqual(v("v1.0.0"), v("1.0.0"))
    }
}

final class UpdateCheckTests: XCTestCase {

    func testNewerReleaseIsOffered() {
        let status = UpdateCheck.evaluate(
            current: "1.0.0", latestTag: "v1.1.0",
            releaseURL: "https://github.com/RogelioAD/pr-radar/releases/tag/v1.1.0")
        XCTAssertEqual(status.newerVersion?.description, "1.1.0")
        XCTAssertEqual(status.url?.absoluteString,
                       "https://github.com/RogelioAD/pr-radar/releases/tag/v1.1.0")
    }

    func testSameVersionIsUpToDate() {
        XCTAssertEqual(
            UpdateCheck.evaluate(current: "1.0.0", latestTag: "v1.0.0",
                                 releaseURL: "https://example.com"),
            .upToDate)
    }

    /// Running a build newer than the latest release — normal while developing.
    func testNewerLocalBuildIsUpToDate() {
        XCTAssertEqual(
            UpdateCheck.evaluate(current: "1.2.0", latestTag: "v1.1.0",
                                 releaseURL: "https://example.com"),
            .upToDate)
    }

    /// The repo has no releases yet, which is the state today.
    func testNoReleasesIsUpToDate() {
        XCTAssertEqual(
            UpdateCheck.evaluate(current: "1.0.0", latestTag: nil, releaseURL: nil),
            .upToDate)
    }

    /// A broken check must never read as "you are current".
    func testUnparseableInputsAreUnknown() {
        XCTAssertEqual(
            UpdateCheck.evaluate(current: nil, latestTag: "v1.1.0",
                                 releaseURL: "https://example.com"),
            .unknown)
        XCTAssertEqual(
            UpdateCheck.evaluate(current: "1.0.0", latestTag: "garbage",
                                 releaseURL: "https://example.com"),
            .unknown)
    }

    /// A newer version with no usable link is not actionable, so not offered.
    func testNewerVersionWithoutAUsableURLIsUnknown() {
        XCTAssertEqual(
            UpdateCheck.evaluate(current: "1.0.0", latestTag: "v1.1.0", releaseURL: nil),
            .unknown)
    }

    func testDoubleDigitReleaseIsDetected() {
        let status = UpdateCheck.evaluate(current: "1.9.0", latestTag: "v1.10.0",
                                          releaseURL: "https://example.com")
        XCTAssertEqual(status.newerVersion?.description, "1.10.0",
                       "string comparison would have missed this")
    }
}

/// Guards the Comparable contract itself, which the padded comparison can
/// easily violate.
extension AppVersionTests {
    func testEqualityAndOrderingAgree() {
        let pairs = [("1.2", "1.2.0"), ("1", "1.0.0"), ("v1.0", "1.0.0"),
                     ("1.2.3", "1.2.3"), ("1.2.0-beta", "1.2.0-beta")]
        for (a, b) in pairs {
            let left = v(a), right = v(b)
            XCTAssertEqual(left, right, "\(a) should equal \(b)")
            XCTAssertFalse(left < right, "\(a) < \(b) contradicts equality")
            XCTAssertFalse(right < left, "\(b) < \(a) contradicts equality")
        }
    }

    func testStrictOrderingIsAntisymmetric() {
        let ordered = ["1.0.0-alpha", "1.0.0", "1.0.1", "1.1.0", "1.9.0",
                       "1.10.0", "2.0.0"].map { v($0) }
        for (index, lower) in ordered.enumerated() {
            for higher in ordered[(index + 1)...] {
                XCTAssertLessThan(lower, higher)
                XCTAssertFalse(higher < lower)
                XCTAssertNotEqual(lower, higher)
            }
        }
    }

    func testSortingProducesReleaseOrder() {
        let shuffled = ["1.10.0", "1.0.0", "2.0.0", "1.9.0", "1.0.0-beta"].map { v($0) }
        XCTAssertEqual(shuffled.sorted().map(\.description),
                       ["1.0.0-beta", "1.0.0", "1.9.0", "1.10.0", "2.0.0"])
    }
}
