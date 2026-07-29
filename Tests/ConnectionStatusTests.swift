import XCTest

/// The status lines in Settings are only honest if they are derived from what
/// the last real call returned. These tests pin that derivation — especially the
/// mapping of `KuberaMCP`'s status strings, which are the app's only channel for
/// what the MCP endpoint said — plus the merge rules that let a single
/// credential be replaced without disturbing the others.
///
/// Every credential value below is synthetic.
final class ConnectionStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_785_000_000)

    // MARK: - REST error mapping

    func testUnauthorizedMapsToAuthFailed() {
        XCTAssertEqual(ConnectionStatus.rest(from: KuberaAPI.APIError.unauthorized), .authFailed)
    }

    func testRateLimitMapsToRateLimited() {
        XCTAssertEqual(ConnectionStatus.rest(from: KuberaAPI.APIError.rateLimited), .rateLimited)
    }

    func testOtherAPIErrorKeepsItsDescription() {
        let status = ConnectionStatus.rest(from: KuberaAPI.APIError.badResponse(status: 503))
        XCTAssertEqual(status, .failed("Kubera API error (HTTP 503)."))
    }

    func testTransportFailureMapsToConnectionCopy() {
        let status = ConnectionStatus.rest(from: URLError(.notConnectedToInternet))
        XCTAssertEqual(status, .failed("Could not reach Kubera. Check your connection."))
    }

    // MARK: - History status-line mapping
    //
    // The literals below are copied from KuberaMCP's setHistoryStatus calls.

    func testHistoryPointsLineParsesCount() {
        let line = "History: 182 points from Kubera's API."
        XCTAssertEqual(
            ConnectionStatus.history(fromStatusLine: line, hasToken: true),
            .connected(points: 182)
        )
    }

    func testNoTokenLineIsDegradedNotFailed() {
        let line = "No MCP token saved — growth builds from the on-device log instead."
        XCTAssertEqual(ConnectionStatus.history(fromStatusLine: line, hasToken: false), .localLogOnly)
    }

    func testMissingTokenBeatsAStaleSuccessLine() {
        // The status line survives in shared defaults after the token is
        // removed; without a token the only truthful state is the local log.
        let line = "History: 182 points from Kubera's API."
        XCTAssertEqual(ConnectionStatus.history(fromStatusLine: line, hasToken: false), .localLogOnly)
    }

    func testNoStatusLineWithTokenIsUnknown() {
        XCTAssertEqual(ConnectionStatus.history(fromStatusLine: nil, hasToken: true), .unknown)
    }

    func testNetworkFailureLineMapsToReachabilityCopy() {
        let line = "History fetch failed: network error."
        XCTAssertEqual(
            ConnectionStatus.history(fromStatusLine: line, hasToken: true),
            .failed("Could not reach Kubera.")
        )
    }

    func testInvalidTokenLineMapsToRejectionCopy() {
        let line = "History fetch failed (HTTP 401): Kubera MCP: Invalid Token"
        XCTAssertEqual(
            ConnectionStatus.history(fromStatusLine: line, hasToken: true),
            .failed("Kubera rejected this MCP token.")
        )
    }

    /// The mistake the old three-field screen invited: pasting the REST key into
    /// the token field. It has to name itself.
    func testInvalidApiKeyLineSaysItIsTheWrongCredential() {
        let line = "History fetch failed (HTTP 400): Kubera MCP: Invalid apiKey"
        XCTAssertEqual(
            ConnectionStatus.history(fromStatusLine: line, hasToken: true),
            .failed("That looks like your API key, not an MCP token.")
        )
    }

    func testMissingHeaderLineMapsToEmptyFieldCopy() {
        let line = "History fetch failed (HTTP 400): Kubera MCP: missing authorization header"
        XCTAssertEqual(
            ConnectionStatus.history(fromStatusLine: line, hasToken: true),
            .failed("The token field came through empty.")
        )
    }

    func testUnreadablePayloadLineMapsToPayloadCopy() {
        let line = "History fetch failed: Kubera answered but the payload was unreadable (body: {})."
        XCTAssertEqual(
            ConnectionStatus.history(fromStatusLine: line, hasToken: true),
            .failed("Kubera answered but the history payload was unreadable.")
        )
    }

    func testUnmappedServerErrorKeepsKuberasOwnText() {
        let line = "History fetch failed (HTTP 500): Kubera MCP: something new"
        XCTAssertEqual(
            ConnectionStatus.history(fromStatusLine: line, hasToken: true),
            .failed("Kubera MCP: something new")
        )
    }

    // MARK: - Independence of the two surfaces

    func testHistoryFailureLeavesRestUntouched() {
        var status = ConnectionStatus(rest: .connected(at: now), history: .connected(points: 10))
        status.history = ConnectionStatus.history(
            fromStatusLine: "History fetch failed (HTTP 401): Kubera MCP: Invalid Token",
            hasToken: true
        )
        XCTAssertEqual(status.rest, .connected(at: now))
        XCTAssertEqual(status.restLine(now: now).role, .positive)
        XCTAssertEqual(status.historyLine.role, .negative)
    }

    func testMissingTokenIsNotAnError() {
        let status = ConnectionStatus(rest: .connected(at: now), history: .localLogOnly)
        XCTAssertEqual(status.headline, "Connected")
        XCTAssertEqual(status.headlineRole, .positive)
        XCTAssertEqual(status.historyLine.role, .dim, "the on-device log is a supported mode")
    }

    func testBrokenRestNeedsAttention() {
        let status = ConnectionStatus(rest: .authFailed, history: .connected(points: 5))
        XCTAssertEqual(status.headline, "Needs attention")
        XCTAssertEqual(status.headlineRole, .negative)
    }

    func testBrokenHistoryAloneNeedsAttention() {
        let status = ConnectionStatus(
            rest: .connected(at: now),
            history: .failed("Kubera rejected this MCP token.")
        )
        XCTAssertEqual(status.headline, "Needs attention")
    }

    func testFreshStatusIsNotChecked() {
        XCTAssertEqual(ConnectionStatus().headline, "Not checked yet")
        XCTAssertEqual(ConnectionStatus().headlineRole, .dim)
    }

    // MARK: - Display

    func testRestLineReportsRelativeFreshness() {
        let status = ConnectionStatus(rest: .connected(at: now.addingTimeInterval(-240)))
        let line = status.restLine(now: now)
        XCTAssertEqual(line.state, "connected")
        XCTAssertEqual(line.detail, "balances updated 4 min ago")
    }

    func testRelativeTimeBands() {
        XCTAssertEqual(ConnectionStatus.relativeTime(from: now, to: now), "just now")
        XCTAssertEqual(ConnectionStatus.relativeTime(from: now.addingTimeInterval(-59), to: now), "just now")
        XCTAssertEqual(ConnectionStatus.relativeTime(from: now.addingTimeInterval(-60), to: now), "1 min ago")
        XCTAssertEqual(ConnectionStatus.relativeTime(from: now.addingTimeInterval(-7200), to: now), "2 h ago")
        XCTAssertEqual(ConnectionStatus.relativeTime(from: now.addingTimeInterval(-172_800), to: now), "2 d ago")
        // Clock skew between the device and a cached timestamp must not read as
        // "-1 min ago".
        XCTAssertEqual(ConnectionStatus.relativeTime(from: now.addingTimeInterval(30), to: now), "just now")
    }

    func testHistoryLineSingularPoint() {
        let status = ConnectionStatus(history: .connected(points: 1))
        XCTAssertEqual(status.historyLine.detail, "1 point from Kubera")
    }

    func testStatusSurvivesCodingRoundTrip() throws {
        let status = ConnectionStatus(rest: .connected(at: now), history: .failed("nope"))
        let data = try JSONEncoder().encode(status)
        XCTAssertEqual(try JSONDecoder().decode(ConnectionStatus.self, from: data), status)
    }

    // MARK: - Masking

    func testMaskKeyShowsBothEnds() {
        XCTAssertEqual(CredentialMask.key("kbra_pk_EXAMPLE_0001"), "kbra••••0001")
    }

    func testMaskKeyHidesShortValuesEntirely() {
        XCTAssertEqual(CredentialMask.key("kbra1234"), "••••")
        XCTAssertEqual(CredentialMask.key(""), "••••")
    }

    func testMaskSecretRevealsNothingAndCapsLength() {
        XCTAssertEqual(CredentialMask.secret("abc"), String(repeating: "•", count: 8))
        XCTAssertEqual(CredentialMask.secret(String(repeating: "x", count: 200)).count, 16)
        XCTAssertEqual(CredentialMask.secret(nil), "Not set")
        XCTAssertEqual(CredentialMask.secret(""), "Not set")
    }

    // MARK: - Input sanitizing

    func testTokenEntryStripsBasicPrefixAndWhitespace() {
        XCTAssertEqual(CredentialInput.sanitizedToken("  Basic EXAMPLE_TOKEN_0001 "), "EXAMPLE_TOKEN_0001")
        XCTAssertEqual(CredentialInput.sanitizedToken("basic  EXAMPLE_TOKEN_0001"), "EXAMPLE_TOKEN_0001")
        XCTAssertEqual(CredentialInput.sanitizedToken("EXAMPLE_TOKEN_0001\n"), "EXAMPLE_TOKEN_0001")
    }

    func testTokenEntryLeavesAnEmbeddedBasicAlone() {
        XCTAssertEqual(CredentialInput.sanitizedToken("TOKEN_basic_0001"), "TOKEN_basic_0001")
    }

    // MARK: - Credential merge semantics
    //
    // Editing one credential must leave the others exactly as stored: the
    // connect screen shows masked placeholders, so an untouched field carries no
    // value to write.

    private var stored: KuberaCredentials {
        KuberaCredentials(
            apiKey: "kbra_pk_EXAMPLE_0001",
            secret: "EXAMPLE_SECRET_0001",
            mcpToken: "EXAMPLE_TOKEN_0001"
        )
    }

    func testReplacingOnlyTheSecretKeepsKeyAndToken() throws {
        let merged = try XCTUnwrap(KuberaCredentials.merged(
            into: stored,
            apiKey: .unchanged,
            secret: .set("EXAMPLE_SECRET_0002"),
            mcpToken: .unchanged
        ))
        XCTAssertEqual(merged.apiKey, stored.apiKey)
        XCTAssertEqual(merged.secret, "EXAMPLE_SECRET_0002")
        XCTAssertEqual(merged.mcpToken, stored.mcpToken)
    }

    func testClearingTheTokenNilsItAndKeepsTheRest() throws {
        let merged = try XCTUnwrap(KuberaCredentials.merged(
            into: stored,
            apiKey: .unchanged,
            secret: .unchanged,
            mcpToken: .cleared
        ))
        XCTAssertNil(merged.mcpToken)
        XCTAssertEqual(merged.apiKey, stored.apiKey)
        XCTAssertEqual(merged.secret, stored.secret)
    }

    func testAddingATokenSanitizesItAtEntry() throws {
        let merged = try XCTUnwrap(KuberaCredentials.merged(
            into: stored,
            apiKey: .unchanged,
            secret: .unchanged,
            mcpToken: .set(" Basic EXAMPLE_TOKEN_0002 ")
        ))
        XCTAssertEqual(merged.mcpToken, "EXAMPLE_TOKEN_0002")
    }

    func testSettingAnEmptyTokenIsTheSameAsClearingIt() throws {
        let merged = try XCTUnwrap(KuberaCredentials.merged(
            into: stored,
            apiKey: .unchanged,
            secret: .unchanged,
            mcpToken: .set("   ")
        ))
        XCTAssertNil(merged.mcpToken)
    }

    func testRequiredValuesAreTrimmed() throws {
        let merged = try XCTUnwrap(KuberaCredentials.merged(
            into: stored,
            apiKey: .set("  kbra_pk_EXAMPLE_0002\n"),
            secret: .unchanged,
            mcpToken: .unchanged
        ))
        XCTAssertEqual(merged.apiKey, "kbra_pk_EXAMPLE_0002")
    }

    func testRequiredCredentialsCannotBeClearedOrBlanked() {
        XCTAssertNil(KuberaCredentials.merged(
            into: stored,
            apiKey: .cleared,
            secret: .unchanged,
            mcpToken: .unchanged
        ))
        XCTAssertNil(KuberaCredentials.merged(
            into: stored,
            apiKey: .unchanged,
            secret: .set("  "),
            mcpToken: .unchanged
        ))
    }

    func testFirstConnectBuildsCredentialsFromNothing() throws {
        let merged = try XCTUnwrap(KuberaCredentials.merged(
            into: nil,
            apiKey: .set("kbra_pk_EXAMPLE_0003"),
            secret: .set("EXAMPLE_SECRET_0003"),
            mcpToken: .cleared
        ))
        XCTAssertEqual(merged.apiKey, "kbra_pk_EXAMPLE_0003")
        XCTAssertEqual(merged.secret, "EXAMPLE_SECRET_0003")
        XCTAssertNil(merged.mcpToken, "connecting without a token is supported")
    }

    func testNothingStoredAndNothingTypedIsNotAWrite() {
        XCTAssertNil(KuberaCredentials.merged(
            into: nil,
            apiKey: .unchanged,
            secret: .unchanged,
            mcpToken: .set("EXAMPLE_TOKEN_0004")
        ))
    }

    func testMergeIsPureAndKeepsTheKeychainShape() throws {
        // A merged item must still decode as the shape already on devices.
        let merged = try XCTUnwrap(KuberaCredentials.merged(
            into: stored,
            apiKey: .unchanged,
            secret: .unchanged,
            mcpToken: .cleared
        ))
        let decoded = try JSONDecoder().decode(
            KuberaCredentials.self,
            from: JSONEncoder().encode(merged)
        )
        XCTAssertEqual(decoded.apiKey, merged.apiKey)
        XCTAssertEqual(decoded.secret, merged.secret)
        XCTAssertNil(decoded.mcpToken)
    }

    // MARK: - Per-field error copy

    func testRestUnauthorizedCopyLandsOnTheCredentialFields() {
        let feedback = CredentialFeedback.forRestError(KuberaAPI.APIError.unauthorized)
        XCTAssertEqual(feedback.field, .keyAndSecret)
        XCTAssertTrue(feedback.text.contains("only shown once"))
    }

    func testRateLimitCopyIsABanner() {
        let feedback = CredentialFeedback.forRestError(KuberaAPI.APIError.rateLimited)
        XCTAssertEqual(feedback.field, .banner)
        XCTAssertEqual(feedback.text, "Kubera's rate limit was hit. Try again in a minute.")
    }

    func testTransportFailureCopyIsABanner() {
        let feedback = CredentialFeedback.forRestError(URLError(.timedOut))
        XCTAssertEqual(feedback.field, .banner)
        XCTAssertEqual(feedback.text, "Could not reach Kubera. Check your connection.")
    }

    func testHistoryFailureCopyLandsOnTheTokenField() {
        let feedback = CredentialFeedback.forHistory(.failed("Kubera rejected this MCP token."))
        XCTAssertEqual(feedback?.field, .mcpToken)
        XCTAssertEqual(feedback?.text, "Kubera rejected this MCP token.")
    }

    func testNoFeedbackWhenHistoryWorksOrIsAbsent() {
        XCTAssertNil(CredentialFeedback.forHistory(.connected(points: 3)))
        XCTAssertNil(CredentialFeedback.forHistory(.localLogOnly))
        XCTAssertNil(CredentialFeedback.forHistory(.unknown))
    }
}
