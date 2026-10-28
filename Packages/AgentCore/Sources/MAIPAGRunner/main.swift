import Foundation
import AgentCore

@main
struct MAIPAGRunnerMain {
    static func main() async {
        let args = CommandLine.arguments
        if args.contains("--self-test") || args.count == 1 {
            let verifier = PKCEHelper.generateCodeVerifier()
            let challenge = PKCEHelper.generateCodeChallenge(from: verifier)
            let zeroRoute = AutoModelRouter.resolve(selectedModelId: "openrouter/auto", balanceUSD: 0.0, userText: "Hello")
            print("maipa-g-runner ready | pkce=\(!challenge.isEmpty) | auto-zero=\(zeroRoute.effectiveModelId)")
            return
        }
        print("maipa-g-runner cloud agent initialized with args: \(args.dropFirst().joined(separator: " "))")
    }
}
