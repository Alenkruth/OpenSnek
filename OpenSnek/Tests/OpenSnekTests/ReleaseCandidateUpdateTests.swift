import Foundation
import XCTest
@testable import OpenSnek

/// Exercises channel selection and installation feeds for release candidates.
final class ReleaseCandidateUpdateTests: XCTestCase {
    func testReleaseCandidatePreferenceDefaultsOff() throws {
        let suite = "OpenSnek.RCUpdates.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(ReleaseUpdateChecker.includesReleaseCandidates(defaults: defaults))
        defaults.set(true, forKey: ReleaseUpdateChecker.includeReleaseCandidatesDefaultsKey)
        XCTAssertTrue(ReleaseUpdateChecker.includesReleaseCandidates(defaults: defaults))
    }

    func testRCBuildAutomaticallyFollowsRCsAndStableBuildRequiresOptIn() {
        XCTAssertEqual(mode("1.4.1-rc.1"), .includingReleaseCandidates)
        XCTAssertEqual(mode("1.4.0"), .newerThanCurrent)
        XCTAssertEqual(mode("1.4.0", optedIn: true), .includingReleaseCandidates)
        XCTAssertEqual(mode("0.0.0-dev", optedIn: true), .includingReleaseCandidates)
        XCTAssertEqual(ReleaseUpdateChecker.checkMode(currentVersion: "0.0.0-dev", includeReleaseCandidates: true, usesDryRun: true), .latestReleaseDryRun)
    }

    func testSelectsNewestRCNumericallyRegardlessOfPublicationOrder() {
        let releases = [release("1.4.1-rc.2"), release("1.4.0"), release("1.4.1-rc.10"), release("1.4.1-rc.1")]
        let selected = ReleaseUpdateChecker.selectUpdate(releases: releases, currentVersion: "1.4.1-rc.2", mode: .includingReleaseCandidates)
        XCTAssertEqual(selected?.latestVersion, "1.4.1-rc.10")
        XCTAssertEqual(selected?.appcastURL.absoluteString, "https://github.com/gh123man/OpenSnek/releases/download/v1.4.1-rc.10/appcast.xml")
    }

    func testStableUsersStayStableUnlessOptedIn() {
        let releases = [release("1.4.1-rc.1"), release("1.4.0")]
        XCTAssertNil(ReleaseUpdateChecker.selectUpdate(releases: releases, currentVersion: "1.4.0", mode: .newerThanCurrent))
        XCTAssertEqual(ReleaseUpdateChecker.selectUpdate(releases: releases, currentVersion: "1.4.0", mode: .includingReleaseCandidates)?.latestVersion, "1.4.1-rc.1")
    }

    func testStableGraduationAndNoDowngrades() {
        let releases = [release("1.4.1-rc.10"), release("1.4.1")]
        XCTAssertEqual(ReleaseUpdateChecker.selectUpdate(releases: releases, currentVersion: "1.4.1-rc.10", mode: .includingReleaseCandidates)?.latestVersion, "1.4.1")
        XCTAssertNil(ReleaseUpdateChecker.selectUpdate(releases: releases, currentVersion: "1.4.1", mode: .includingReleaseCandidates))
        XCTAssertNil(ReleaseUpdateChecker.selectUpdate(releases: releases, currentVersion: "1.5.0-rc.1", mode: .includingReleaseCandidates))
    }

    func testSkipsDraftsOtherPrereleasesAndIncompleteUploads() {
        let releases = [release("1.5.0-rc.1", draft: true), release("1.5.0-beta.1"), release("1.5.0-rc.2", complete: false), release("1.4.1-rc.1")]
        XCTAssertEqual(ReleaseUpdateChecker.selectUpdate(releases: releases, currentVersion: "1.4.0", mode: .includingReleaseCandidates)?.latestVersion, "1.4.1-rc.1")
    }

    func testReleaseAPIResponseDecodesAndSelectsRC() throws {
        let data = Data(
            """
            [{"tag_name":"v1.4.1-rc.2","html_url":"https://github.com/gh123man/OpenSnek/releases/tag/v1.4.1-rc.2",
              "draft":false,"prerelease":true,"assets":[{"name":"appcast.xml"},{"name":"OpenSnek-1.4.1-rc.2.zip"}]}]
            """.utf8)
        let releases = try JSONDecoder().decode([ReleaseUpdateChecker.LatestReleaseResponse].self, from: data)
        let selected = ReleaseUpdateChecker.selectUpdate(releases: releases, currentVersion: "1.4.1-rc.1", mode: .includingReleaseCandidates)
        XCTAssertEqual(selected?.latestVersion, "1.4.1-rc.2")
    }

    private func mode(_ version: String, optedIn: Bool = false) -> ReleaseUpdateCheckMode { ReleaseUpdateChecker.checkMode(currentVersion: version, includeReleaseCandidates: optedIn, usesDryRun: false) }

    private func release(_ version: String, draft: Bool = false, complete: Bool = true) -> ReleaseUpdateChecker.LatestReleaseResponse {
        ReleaseUpdateChecker.LatestReleaseResponse(tag_name: "v\(version)", html_url: "https://github.com/gh123man/OpenSnek/releases/tag/v\(version)", draft: draft, prerelease: version.contains("-"), assets: complete ? [.init(name: "appcast.xml"), .init(name: "OpenSnek-\(version).zip")] : [])
    }
}
