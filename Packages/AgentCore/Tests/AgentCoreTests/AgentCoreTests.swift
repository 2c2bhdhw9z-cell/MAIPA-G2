import XCTest
@testable import AgentCore

final class AgentCoreTests: XCTestCase {
    func testPKCEChallengeMatchesRFC7636Vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let challenge = PKCEHelper.generateCodeChallenge(from: verifier)
        XCTAssertEqual(challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testNewChatStartsNotConnectedToARepo() {
        let chat = ChatThread()
        XCTAssertNil(chat.repoFullName)
        XCTAssertNil(chat.branchName)
        XCTAssertFalse(chat.isAutonomous)
        XCTAssertEqual(chat.thinkingLevel, .medium)
    }

    func testDefaultSettingsHideUnconnectedConnectorsOnHome() {
        let settings = AppSettings()
        XCTAssertFalse(settings.showUnconnectedConnectorsOnHome)
        XCTAssertTrue(settings.hiddenConnectorIds.contains("google-drive"))
        XCTAssertTrue(settings.hiddenConnectorIds.contains("google-docs"))
        XCTAssertTrue(settings.hiddenConnectorIds.contains("notion"))
        XCTAssertTrue(settings.hiddenConnectorIds.contains("google-sheets"))
        XCTAssertGreaterThanOrEqual(MCPConnectorItem.defaultConnectors.count, 30)
    }

    func testAutoRouterUsesFreeModelsWhenBalanceIsZero() {
        let route = AutoModelRouter.resolve(
            selectedModelId: "openrouter/auto",
            balanceUSD: 0.0,
            userText: "Read README.md"
        )
        XCTAssertEqual(route.effectiveModelId, "openrouter/free")
        XCTAssertTrue(route.usesFreePoolOnly)
        XCTAssertFalse(route.requiresBalancePrompt)
    }

    func testAutoRouterUsesPaidAutoTierWhenFunded() {
        let route = AutoModelRouter.resolve(
            selectedModelId: "openrouter/auto",
            balanceUSD: 5.00,
            userText: "Plan the architecture and debug the crash",
            specMode: true
        )
        XCTAssertEqual(route.effectiveModelId, "openrouter/auto")
        XCTAssertEqual(route.costTier, .high)
        XCTAssertFalse(route.usesFreePoolOnly)
    }

    func testPaidModelPromptsUserWhenBalanceRunsOut() {
        let route = AutoModelRouter.resolve(
            selectedModelId: "anthropic/claude-opus-4.1",
            balanceUSD: 0.0,
            userText: "Write Swift code"
        )
        XCTAssertTrue(route.requiresBalancePrompt)
    }

    func testStopAndAskCostSwitch() {
        XCTAssertFalse(AutoModelRouter.shouldStopAndAskForCost(currentJobCostUSD: 2.5, stopSwitchEnabled: false, thresholdUSD: 1.0))
        XCTAssertFalse(AutoModelRouter.shouldStopAndAskForCost(currentJobCostUSD: 0.45, stopSwitchEnabled: true, thresholdUSD: 1.0))
        XCTAssertTrue(AutoModelRouter.shouldStopAndAskForCost(currentJobCostUSD: 1.05, stopSwitchEnabled: true, thresholdUSD: 1.0))
    }

    func testBranchSavePolicyRespectsContinuumAndSideBranches() {
        let gh = GitHubService()
        let settings = AppSettings()
        // Normal repo on main branch uses a side branch + PR (returns false for straight-to-branch)
        XCTAssertFalse(gh.shouldSaveStraightToBranch(fullName: "2c2bhdhw9z-cell/MAIPA-G2", pickedBranch: "main", defaultBranch: "main", settings: settings))
        // Continuum repo saves straight to master
        XCTAssertTrue(gh.shouldSaveStraightToBranch(fullName: "2c2bhdhw9z-cell/Continuum-", pickedBranch: "master", defaultBranch: "master", settings: settings))
    }

    func testExtractAutoMemoriesAndNumberedQuestions() {
        let sample = """
        Here is the plan:
        [MEMORY: Prefer dark mode and no unused Google connectors]
        1. Which branch should we target? [main | dev]
        """
        let (cleaned, mems) = OpenRouterService.extractAutoMemories(from: sample)
        XCTAssertEqual(mems, ["Prefer dark mode and no unused Google connectors"])
        let questions = OpenRouterService.extractNumberedQuestions(from: cleaned)
        XCTAssertEqual(questions.count, 1)
        XCTAssertEqual(questions[0].number, 1)
        XCTAssertEqual(questions[0].options, ["main", "dev"])
    }
}
