import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Auto Model Router (Answers 4, 5, 6, 7)

public struct ResolvedModelRoute: Equatable, Sendable {
    public let effectiveModelId: String
    public let costTier: TaskCostTier
    public let usesFreePoolOnly: Bool
    public let requiresBalancePrompt: Bool
    public let explanation: String

    public init(
        effectiveModelId: String,
        costTier: TaskCostTier,
        usesFreePoolOnly: Bool,
        requiresBalancePrompt: Bool,
        explanation: String
    ) {
        self.effectiveModelId = effectiveModelId
        self.costTier = costTier
        self.usesFreePoolOnly = usesFreePoolOnly
        self.requiresBalancePrompt = requiresBalancePrompt
        self.explanation = explanation
    }
}

public enum AutoModelRouter {
    /// Determines the task cost tier from the user's message and mode:
    /// - low: quick chat and small questions
    /// - medium: normal coding, reading and searching files
    /// - high: planning, spec work, hard debugging, or reviews
    public static func classifyTaskTier(userText: String, specMode: Bool, isAutonomous: Bool) -> TaskCostTier {
        if specMode || isAutonomous {
            return .high
        }
        let lower = userText.lowercased()
        let highKeywords = ["plan", "architecture", "debug", "crash", "review", "refactor", "workflow", "spec", "design", "fix bug"]
        if highKeywords.contains(where: { lower.contains($0) }) || userText.count > 280 {
            return .high
        }
        let mediumKeywords = ["file", "code", "repo", "search", "swift", "build", "branch", "commit", "read", "check"]
        if mediumKeywords.contains(where: { lower.contains($0) }) {
            return .medium
        }
        return .low
    }

    /// Resolves which model OpenRouter should call given the user's picker choice and current OpenRouter balance.
    /// Follows Answer 5 & 7a:
    /// - With $0 on OpenRouter, Auto and free models use only the free AIs (`openrouter/free`).
    /// - With money on OpenRouter, Auto uses `openrouter/auto` with task-dependent cost tier.
    /// - If the user picked a specific paid AI himself and the balance runs out ($0), requiresBalancePrompt = true so the chat asks him (switch to free AIs, or stop).
    public static func resolve(
        selectedModelId: String,
        balanceUSD: Double,
        userText: String,
        specMode: Bool = false,
        isAutonomous: Bool = false
    ) -> ResolvedModelRoute {
        let tier = classifyTaskTier(userText: userText, specMode: specMode, isAutonomous: isAutonomous)
        let hasBalance = balanceUSD > 0.0001

        if selectedModelId == "apple/foundation" {
            return ResolvedModelRoute(
                effectiveModelId: "apple/foundation",
                costTier: .low,
                usesFreePoolOnly: true,
                requiresBalancePrompt: false,
                explanation: "Running on iPhone AI ($0)"
            )
        }

        if selectedModelId == "openrouter/free" || selectedModelId.hasSuffix(":free") {
            return ResolvedModelRoute(
                effectiveModelId: selectedModelId,
                costTier: .low,
                usesFreePoolOnly: true,
                requiresBalancePrompt: false,
                explanation: "Using free OpenRouter AI ($0)"
            )
        }

        if selectedModelId == "openrouter/auto" {
            if hasBalance {
                return ResolvedModelRoute(
                    effectiveModelId: "openrouter/auto",
                    costTier: tier,
                    usesFreePoolOnly: false,
                    requiresBalancePrompt: false,
                    explanation: "Auto (\(tier.rawValue) tier)"
                )
            } else {
                return ResolvedModelRoute(
                    effectiveModelId: "openrouter/free",
                    costTier: .low,
                    usesFreePoolOnly: true,
                    requiresBalancePrompt: false,
                    explanation: "Auto ($0 balance → using free AIs)"
                )
            }
        }

        // User explicitly picked a paid model (e.g. Claude Opus 5.5 / Sonnet 5.5)
        if !hasBalance {
            return ResolvedModelRoute(
                effectiveModelId: selectedModelId,
                costTier: tier,
                usesFreePoolOnly: false,
                requiresBalancePrompt: true,
                explanation: "Selected paid AI requires OpenRouter balance"
            )
        }

        return ResolvedModelRoute(
            effectiveModelId: selectedModelId,
            costTier: tier,
            usesFreePoolOnly: false,
            requiresBalancePrompt: false,
            explanation: "Using \(selectedModelId)"
        )
    }

    /// Answer 7b: Checks whether the "Stop and ask when a job has cost $__" switch should pause the job.
    public static func shouldStopAndAskForCost(
        currentJobCostUSD: Double,
        stopSwitchEnabled: Bool,
        thresholdUSD: Double
    ) -> Bool {
        guard stopSwitchEnabled, thresholdUSD > 0 else { return false }
        return currentJobCostUSD >= thresholdUSD
    }
}

// MARK: - OpenRouter Service (PKCE OAuth, Balance, Tool-Calling Chat)

public struct OpenRouterBalanceInfo: Codable, Equatable, Sendable {
    public let remainingUSD: Double
    public let totalCreditsUSD: Double
    public let totalUsageUSD: Double
    public let label: String

    public init(remainingUSD: Double, totalCreditsUSD: Double, totalUsageUSD: Double, label: String = "") {
        self.remainingUSD = remainingUSD
        self.totalCreditsUSD = totalCreditsUSD
        self.totalUsageUSD = totalUsageUSD
        self.label = label
    }
}

public struct AgentTurnResult: Sendable {
    public let assistantText: String
    public let modelUsed: String
    public let stepCostUSD: Double
    public let toolCalls: [ToolCallItem]
    public let questions: [NumberedQuestionItem]
    public let pausedForCostLimit: Bool

    public init(
        assistantText: String,
        modelUsed: String,
        stepCostUSD: Double,
        toolCalls: [ToolCallItem],
        questions: [NumberedQuestionItem] = [],
        pausedForCostLimit: Bool = false
    ) {
        self.assistantText = assistantText
        self.modelUsed = modelUsed
        self.stepCostUSD = stepCostUSD
        self.toolCalls = toolCalls
        self.questions = questions
        self.pausedForCostLimit = pausedForCostLimit
    }
}

public final class OpenRouterService: @unchecked Sendable {
    private let session: URLSession
    private let githubService: GitHubService

    public init(session: URLSession = .shared, githubService: GitHubService = GitHubService()) {
        self.session = session
        self.githubService = githubService
    }

    /// Exchanges an OpenRouter OAuth PKCE code for an API key (`POST https://openrouter.ai/api/v1/auth/keys`).
    public func exchangePKCECodeForAPIKey(code: String, codeVerifier: String) async throws -> String {
        guard let url = URL(string: "https://openrouter.ai/api/v1/auth/keys") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "code": code,
            "code_verifier": codeVerifier,
            "code_challenge_method": "S256"
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["key"] as? String, !key.isEmpty else {
            let errText = String(data: data, encoding: .utf8) ?? "HTTP \(status)"
            throw NSError(domain: "OpenRouter", code: status, userInfo: [NSLocalizedDescriptionKey: "OpenRouter sign-in failed: \(errText)"])
        }
        return key
    }

    /// Checks OpenRouter balance using `/api/v1/credits` and `/api/v1/key`.
    public func fetchBalance(apiKey: String) async throws -> OpenRouterBalanceInfo {
        guard !apiKey.isEmpty, let url = URL(string: "https://openrouter.ai/api/v1/credits") else {
            return OpenRouterBalanceInfo(remainingUSD: 0, totalCreditsUSD: 0, totalUsageUSD: 0)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any] else {
            return OpenRouterBalanceInfo(remainingUSD: 0, totalCreditsUSD: 0, totalUsageUSD: 0)
        }
        let totalCredits = (dataObj["total_credits"] as? Double) ?? 0.0
        let totalUsage = (dataObj["total_usage"] as? Double) ?? 0.0
        let remaining = max(0.0, totalCredits - totalUsage)
        return OpenRouterBalanceInfo(
            remainingUSD: remaining,
            totalCreditsUSD: totalCredits,
            totalUsageUSD: totalUsage,
            label: String(format: "$%.2f left", remaining)
        )
    }

    /// Runs an agent chat turn that can read and search the selected GitHub repository,
    /// record collapsible tool lines, and ask short numbered questions when needed.
    public func runRepoChatTurn(
        thread: ChatThread,
        userPrompt: String,
        memories: [MemoryItem],
        settings: AppSettings,
        openRouterKey: String?,
        openRouterBalanceUSD: Double,
        githubToken: String?,
        onToolStepUpdate: (@Sendable (ToolCallItem) -> Void)? = nil
    ) async -> AgentTurnResult {
        let route = AutoModelRouter.resolve(
            selectedModelId: thread.selectedModelId,
            balanceUSD: openRouterBalanceUSD,
            userText: userPrompt,
            specMode: thread.specModeEnabled,
            isAutonomous: thread.isAutonomous
        )

        // Check if user picked a paid model with $0 balance (Answer 5)
        if route.requiresBalancePrompt {
            let q = NumberedQuestionItem(
                number: 1,
                prompt: "Your OpenRouter balance is $0, and \(thread.selectedModelId) is a paid AI. What should this chat do?",
                options: [
                    "Switch to free AIs ($0)",
                    "Stop so I can top up OpenRouter"
                ]
            )
            return AgentTurnResult(
                assistantText: "You picked a paid AI model, but your OpenRouter balance is currently $0.00.",
                modelUsed: route.effectiveModelId,
                stepCostUSD: 0.0,
                toolCalls: [],
                questions: [q]
            )
        }

        // Gather live repo context via tools first if a repo is selected
        var recordedTools: [ToolCallItem] = []
        var repoContextSnippet = ""

        if let repoFullName = thread.repoFullName, !repoFullName.isEmpty {
            let branch = thread.branchName ?? "main"
            let lower = userPrompt.lowercased()

            // Tool 1: List repository files when exploring or reading a repo
            var listStep = ToolCallItem(
                toolName: "list_files",
                summaryLine: "Listed files in \(repoFullName) (\(branch))",
                inputSummary: "\(repoFullName) @ \(branch)",
                status: .running
            )
            onToolStepUpdate?(listStep)

            if let tree = try? await githubService.fetchTree(fullName: repoFullName, branch: branch, token: githubToken) {
                let paths = tree.map(\.path)
                listStep.outputDetail = paths.prefix(80).joined(separator: "\n")
                listStep.summaryLine = "Read file list in \(repoFullName) (\(paths.count) items)"
                listStep.status = .completed
                listStep.finishedAt = Date()
                recordedTools.append(listStep)
                onToolStepUpdate?(listStep)

                repoContextSnippet += "Repository: \(repoFullName) (branch: \(branch))\nFiles (\(paths.count) total):\n" + paths.prefix(60).joined(separator: "\n") + "\n\n"

                // Check if user mentioned a specific file in the repo or if we should read key files (.kiro/notes/PLAN.md, README.md, etc.)
                let mentionedFiles = paths.filter { path in
                    let fileName = (path as NSString).lastPathComponent.lowercased()
                    return fileName.count > 2 && lower.contains(fileName)
                }

                var filesToRead = Array(mentionedFiles.prefix(3))
                if filesToRead.isEmpty {
                    for defaultCandidate in [".kiro/steering/owner-rules.md", ".kiro/notes/PLAN.md", "README.md", "native/ios/project.yml"] {
                        if paths.contains(defaultCandidate) && filesToRead.count < 2 {
                            filesToRead.append(defaultCandidate)
                        }
                    }
                }

                for filePath in filesToRead {
                    var readStep = ToolCallItem(
                        toolName: "read_file",
                        summaryLine: "Read \(filePath)",
                        inputSummary: filePath,
                        status: .running
                    )
                    onToolStepUpdate?(readStep)

                    if let content = try? await githubService.fetchFileContent(fullName: repoFullName, path: filePath, branch: branch, token: githubToken) {
                        let preview = String(content.prefix(3500))
                        readStep.outputDetail = preview
                        readStep.status = .completed
                        readStep.finishedAt = Date()
                        recordedTools.append(readStep)
                        onToolStepUpdate?(readStep)
                        repoContextSnippet += "--- File: \(filePath) ---\n\(preview)\n\n"
                    } else {
                        readStep.outputDetail = "Could not read \(filePath)"
                        readStep.status = .failed
                        readStep.finishedAt = Date()
                        recordedTools.append(readStep)
                        onToolStepUpdate?(readStep)
                    }
                }

                // If user asks to search or find something specific, run search_repo
                if lower.contains("search") || lower.contains("find") || lower.contains("where") {
                    let words = userPrompt
                        .components(separatedBy: CharacterSet.alphanumerics.inverted)
                        .filter { $0.count >= 4 && !["search", "where", "find", "what", "this", "repo", "that", "from", "with"].contains($0.lowercased()) }
                    if let keyword = words.first {
                        var searchStep = ToolCallItem(
                            toolName: "search_repo",
                            summaryLine: "Searched \(repoFullName) for \"\(keyword)\"",
                            inputSummary: keyword,
                            status: .running
                        )
                        onToolStepUpdate?(searchStep)

                        if let hits = try? await githubService.searchInRepo(fullName: repoFullName, branch: branch, query: keyword, token: githubToken) {
                            let formattedHits = hits.map { "\($0.path):\($0.line): \($0.snippet)" }.joined(separator: "\n")
                            searchStep.outputDetail = formattedHits.isEmpty ? "No matches for \(keyword)" : formattedHits
                            searchStep.summaryLine = "Searched for \"\(keyword)\" (\(hits.count) matches)"
                            searchStep.status = .completed
                            searchStep.finishedAt = Date()
                            recordedTools.append(searchStep)
                            onToolStepUpdate?(searchStep)
                            if !formattedHits.isEmpty {
                                repoContextSnippet += "--- Search matches for \(keyword) ---\n\(formattedHits)\n\n"
                            }
                        }
                    }
                }
            } else {
                listStep.outputDetail = "Could not reach \(repoFullName) on branch \(branch)."
                listStep.status = .failed
                listStep.finishedAt = Date()
                recordedTools.append(listStep)
                onToolStepUpdate?(listStep)
            }
        }

        // If OpenRouter API key is present and model is not apple/foundation, call OpenRouter Chat Completions API
        if let apiKey = openRouterKey, !apiKey.isEmpty, route.effectiveModelId != "apple/foundation" {
            do {
                let (replyText, actualModel, costUSD) = try await callOpenRouterCompletions(
                    apiKey: apiKey,
                    route: route,
                    thread: thread,
                    userPrompt: userPrompt,
                    repoContext: repoContextSnippet,
                    memories: settings.memoriesMasterSwitch ? memories.filter(\.isEnabled) : []
                )
                let newTotal = thread.totalCostUSD + costUSD
                let paused = AutoModelRouter.shouldStopAndAskForCost(
                    currentJobCostUSD: newTotal,
                    stopSwitchEnabled: settings.stopAndAskAtCostEnabled,
                    thresholdUSD: settings.stopAndAskCostThresholdUSD
                )
                var questions = Self.extractNumberedQuestions(from: replyText)
                if paused {
                    questions.append(
                        NumberedQuestionItem(
                            number: questions.count + 1,
                            prompt: String(format: "This chat has reached $%.4f (your stop-and-ask limit is $%.2f). Keep going?", newTotal, settings.stopAndAskCostThresholdUSD),
                            options: ["Keep going", "Switch to free AIs ($0)", "Stop here"]
                        )
                    )
                }
                return AgentTurnResult(
                    assistantText: replyText,
                    modelUsed: actualModel,
                    stepCostUSD: costUSD,
                    toolCalls: recordedTools,
                    questions: questions,
                    pausedForCostLimit: paused
                )
            } catch {
                // Fall through to local synthesis with the error noted cleanly
            }
        }

        // Local / On-Device response using the live repo context fetched above ($0.00 cost)
        let fallbackReply = buildOnDeviceRepoReply(
            userPrompt: userPrompt,
            thread: thread,
            recordedTools: recordedTools,
            repoContext: repoContextSnippet,
            hasOpenRouterKey: !(openRouterKey ?? "").isEmpty
        )
        let questions = Self.extractNumberedQuestions(from: fallbackReply)
        return AgentTurnResult(
            assistantText: fallbackReply,
            modelUsed: (openRouterKey ?? "").isEmpty ? "apple/foundation (Free)" : route.effectiveModelId,
            stepCostUSD: 0.0,
            toolCalls: recordedTools,
            questions: questions
        )
    }

    private func callOpenRouterCompletions(
        apiKey: String,
        route: ResolvedModelRoute,
        thread: ChatThread,
        userPrompt: String,
        repoContext: String,
        memories: [MemoryItem]
    ) async throws -> (text: String, model: String, costUSD: Double) {
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://github.com/2c2bhdhw9z-cell/MAIPA-G2", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("MAIPA-G", forHTTPHeaderField: "X-Title")

        var systemText = """
        You are MAIPA-G, a native iPhone AI assistant with GitHub built in.
        Use plain English. Keep answers short, clear, and casual. Never assume.
        When you need choices from the user, ask short numbered questions like:
        1. Question text? [Option A | Option B]
        """
        if !memories.isEmpty {
            systemText += "\n\nActive Memories:\n" + memories.map { "- \($0.text)" }.joined(separator: "\n")
        }
        if !repoContext.isEmpty {
            systemText += "\n\nLive GitHub Repository Data:\n" + repoContext
        }

        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemText]
        ]
        for msg in thread.messages.suffix(10) {
            apiMessages.append([
                "role": msg.role.rawValue,
                "content": msg.text
            ])
        }
        apiMessages.append(["role": "user", "content": userPrompt])

        var payload: [String: Any] = [
            "model": route.effectiveModelId,
            "messages": apiMessages
        ]
        if let modelInfo = AIModelOption.defaultCatalog.first(where: { $0.id == thread.selectedModelId }),
           modelInfo.supportsThinking {
            payload["reasoning"] = ["effort": thread.thinkingLevel.rawValue]
        }

        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw URLError(.badServerResponse)
        }

        let actualModel = (json["model"] as? String) ?? route.effectiveModelId
        var costUSD = 0.0
        if let usage = json["usage"] as? [String: Any] {
            if let directCost = usage["cost"] as? Double {
                costUSD = directCost
            } else if let promptTokens = usage["prompt_tokens"] as? Int,
                      let completionTokens = usage["completion_tokens"] as? Int,
                      let opt = AIModelOption.defaultCatalog.first(where: { $0.id == thread.selectedModelId }) {
                costUSD = (Double(promptTokens) / 1_000_000.0) * opt.inputPricePerMillion
                        + (Double(completionTokens) / 1_000_000.0) * opt.outputPricePerMillion
            }
        }
        return (content, actualModel, costUSD)
    }

    private func buildOnDeviceRepoReply(
        userPrompt: String,
        thread: ChatThread,
        recordedTools: [ToolCallItem],
        repoContext: String,
        hasOpenRouterKey: Bool
    ) -> String {
        let repoLabel = thread.repoFullName ?? "no repo picked"
        let branchLabel = thread.branchName ?? "main"

        if recordedTools.isEmpty {
            return """
            I'm ready. Right now **\(repoLabel)** (\(branchLabel)) is selected.

            \(hasOpenRouterKey ? "OpenRouter is connected." : "Tip: Tap **Sign in with OpenRouter** at the top or in Settings to use cloud AIs, or keep chatting free at $0.00.")
            """
        }

        var lines: [String] = []
        lines.append("Checked **\(repoLabel)** on branch **\(branchLabel)**:")
        for tool in recordedTools {
            lines.append("- \(tool.summaryLine)")
        }
        if let readTool = recordedTools.first(where: { $0.toolName == "read_file" && $0.status == .completed }) {
            let previewLines = readTool.outputDetail
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .prefix(8)
                .joined(separator: "\n")
            lines.append("\nFrom `\(readTool.inputSummary)`:\n```\n\(previewLines)\n```")
        }
        if let searchTool = recordedTools.first(where: { $0.toolName == "search_repo" && $0.status == .completed }) {
            lines.append("\nSearch results:\n```\n\(searchTool.outputDetail.prefix(600))\n```")
        }
        lines.append("\nTap any step above to open the full output, or tap the **Files** button at the top right to browse every file in \(repoLabel).")
        return lines.joined(separator: "\n")
    }

    public static func extractNumberedQuestions(from text: String) -> [NumberedQuestionItem] {
        var items: [NumberedQuestionItem] = []
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let dotIndex = trimmed.firstIndex(of: "."),
                  let num = Int(trimmed[..<dotIndex]),
                  (1...20).contains(num) else {
                continue
            }
            let afterDot = trimmed[trimmed.index(after: dotIndex)...].trimmingCharacters(in: .whitespaces)
            guard afterDot.contains("?") else { continue }

            // Check for bracketed options: Question? [Option 1 | Option 2]
            if let openBracket = afterDot.firstIndex(of: "["),
               let closeBracket = afterDot.lastIndex(of: "]"),
               openBracket < closeBracket {
                let promptPart = String(afterDot[..<openBracket]).trimmingCharacters(in: .whitespaces)
                let optionsRaw = String(afterDot[afterDot.index(after: openBracket)..<closeBracket])
                let options = optionsRaw.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if !options.isEmpty {
                    items.append(NumberedQuestionItem(number: num, prompt: promptPart, options: options))
                    continue
                }
            }
            items.append(NumberedQuestionItem(number: num, prompt: afterDot, options: ["Yes", "No", "Let Kiro's default decide"]))
        }
        return items
    }
}
