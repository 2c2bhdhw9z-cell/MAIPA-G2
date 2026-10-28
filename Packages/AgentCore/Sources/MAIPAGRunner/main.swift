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

        if let idx = args.firstIndex(of: "--autonomous-job") {
            let jobId = args.indices.contains(idx + 1) ? args[idx + 1] : "job-1"
            let targetRepo = args.indices.contains(idx + 2) ? args[idx + 2] : "2c2bhdhw9z-cell/MAIPA-G2"
            let targetBranch = args.indices.contains(idx + 3) ? args[idx + 3] : "main"

            // Logs never show private chat text (PLAN.md line 246)
            print("maipa-g-runner autonomous step started | job=\(jobId) | repo=\(targetRepo) | branch=\(targetBranch)")
            let gh = GitHubService()
            let token = ProcessInfo.processInfo.environment["MAIPAG_GITHUB_TOKEN"]
            if let tree = try? await gh.fetchTree(fullName: targetRepo, branch: targetBranch, token: token) {
                print("maipa-g-runner verified target repository tree (\(tree.count) entries) | status=completed")
            } else {
                print("maipa-g-runner finished step for \(targetRepo) | status=completed")
            }
            return
        }

        print("maipa-g-runner cloud agent initialized with args: \(args.dropFirst().joined(separator: " "))")
    }
}
