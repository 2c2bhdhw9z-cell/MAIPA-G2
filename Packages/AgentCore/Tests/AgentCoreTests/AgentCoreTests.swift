import XCTest
@testable import AgentCore

final class AgentCoreTests: XCTestCase {
    func testPKCEChallengeMatchesRFC7636Vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let challenge = PKCEHelper.generateCodeChallenge(from: verifier)
        XCTAssertEqual(challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testAutoModelRouterUsesFreeModelsAtZeroBalance() {
        let route = AutoModelRouter.resolve(
            selectedModelId: "openrouter/auto",
            balanceUSD: 0.0,
            userText: "Explain how this repo works"
        )
        XCTAssertEqual(route.effectiveModelId, "openrouter/free")
        XCTAssertTrue(route.usesFreePoolOnly)
        XCTAssertFalse(route.requiresBalancePrompt)
    }

    func testAutoModelRouterUsesAutoAndTaskTierWhenFunded() {
        let lowRoute = AutoModelRouter.resolve(
            selectedModelId: "openrouter/auto",
            balanceUSD: 5.00,
            userText: "Hi there"
        )
        XCTAssertEqual(lowRoute.effectiveModelId, "openrouter/auto")
        XCTAssertEqual(lowRoute.costTier, .low)

        let highRoute = AutoModelRouter.resolve(
            selectedModelId: "openrouter/auto",
            balanceUSD: 5.00,
            userText: "Plan the architecture and debug the crash in the build workflow"
        )
        XCTAssertEqual(highRoute.effectiveModelId, "openrouter/auto")
        XCTAssertEqual(highRoute.costTier, .high)
    }

    func testExplicitPaidModelWithZeroBalancePromptsUser() {
        let route = AutoModelRouter.resolve(
            selectedModelId: "anthropic/claude-opus-4.1",
            balanceUSD: 0.0,
            userText: "Review this file"
        )
        XCTAssertTrue(route.requiresBalancePrompt)
    }

    func testStopAndAskCostSwitchBehavior() {
        // Default: switch is off -> never stops
        XCTAssertFalse(
            AutoModelRouter.shouldStopAndAskForCost(
                currentJobCostUSD: 5.0,
                stopSwitchEnabled: false,
                thresholdUSD: 1.0
            )
        )
        // Switch on at $1.00 -> triggers at >= $1.00
        XCTAssertFalse(
            AutoModelRouter.shouldStopAndAskForCost(
                currentJobCostUSD: 0.45,
                stopSwitchEnabled: true,
                thresholdUSD: 1.0
            )
        )
        XCTAssertTrue(
            AutoModelRouter.shouldStopAndAskForCost(
                currentJobCostUSD: 1.00,
                stopSwitchEnabled: true,
                thresholdUSD: 1.0
            )
        )
    }

    func testNumberedQuestionExtractor() {
        let sample = """
        Before I change that file, please let me know:
        1. Which branch should I target? [main | develop]
        2. Should I run the build right away? [Yes | No]
        """
        let extracted = OpenRouterService.extractNumberedQuestions(from: sample)
        XCTAssertEqual(extracted.count, 2)
        XCTAssertEqual(extracted[0].number, 1)
        XCTAssertEqual(extracted[0].options, ["main", "develop"])
        XCTAssertEqual(extracted[1].number, 2)
        XCTAssertEqual(extracted[1].options, ["Yes", "No"])
    }
}
