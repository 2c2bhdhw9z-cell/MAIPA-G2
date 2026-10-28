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
                explanation: "iPhone AI ($0)"
            )
        }

        if selectedModelId == "openrouter/free" || selectedModelId.hasSuffix(":free") {
            return ResolvedModelRoute(
                effectiveModelId: selectedModelId,
                costTier: .low,
                usesFreePoolOnly: true,
                requiresBalancePrompt: false,
                explanation: "Free OpenRouter AI ($0)"
            )
        }

        if selectedModelId == "openrouter/auto" {
            if hasBalance {
                return ResolvedModelRoute(
                    effectiveModelId: "openrouter/auto",
                    costTier: tier,
                    usesFreePoolOnly: false,
                    requiresBalancePrompt: false,
                    explanation: "Auto (\(tier.rawValue) task tier)"
                )
            } else {
                return ResolvedModelRoute(
                    effectiveModelId: "openrouter/free",
                    costTier: .low,
                    usesFreePoolOnly: true,
                    requiresBalancePrompt: false,
                    explanation: "Auto ($0 balance → free AIs)"
                )
            }
        }

        if !hasBalance {
            return ResolvedModelRoute(
                effectiveModelId: selectedModelId,
                costTier: tier,
                usesFreePoolOnly: false,
                requiresBalancePrompt: true,
                explanation: "Paid AI needs OpenRouter balance"
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

// MARK: - OpenRouter Service (PKCE OAuth, Balance, Web Search, Tool-Calling Chat, File Saves & Picture Generation)

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
    public let autoSavedMemories: [String]
    public let generatedSpec: SpecPlanDocument?
    public let pausedForCostLimit: Bool
    public let savedChangeReceipt: SavedChangeReceipt?
    public let generatedImageURL: String?

    public init(
        assistantText: String,
        modelUsed: String,
        stepCostUSD: Double,
        toolCalls: [ToolCallItem],
        questions: [NumberedQuestionItem] = [],
        autoSavedMemories: [String] = [],
        generatedSpec: SpecPlanDocument? = nil,
        pausedForCostLimit: Bool = false,
        savedChangeReceipt: SavedChangeReceipt? = nil,
        generatedImageURL: String? = nil
    ) {
        self.assistantText = assistantText
        self.modelUsed = modelUsed
        self.stepCostUSD = stepCostUSD
        self.toolCalls = toolCalls
        self.questions = questions
        self.autoSavedMemories = autoSavedMemories
        self.generatedSpec = generatedSpec
        self.pausedForCostLimit = pausedForCostLimit
        self.savedChangeReceipt = savedChangeReceipt
        self.generatedImageURL = generatedImageURL
    }
}

public final class OpenRouterService: @unchecked Sendable {
    private let session: URLSession
    private let githubService: GitHubService

    public init(session: URLSession = .shared, githubService: GitHubService = GitHubService()) {
        self.session = session
        self.githubService = githubService
    }

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

    // MARK: - Answer 26: Free Web Search & Read a Web Page (no setup required)

    public func searchWebFree(query: String) async -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return "Invalid search query."
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10

        guard let (data, _) = try? await session.data(for: req),
              let html = String(data: data, encoding: .utf8) else {
            return "Could not reach free web search right now."
        }

        let stripped = Self.stripHTMLTags(from: html)
        let lines = stripped
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 35 && !$0.lowercased().hasPrefix("duckduckgo") }
        return lines.prefix(12).joined(separator: "\n")
    }

    public func readWebPage(urlString: String) async -> String {
        guard let url = URL(string: urlString) else { return "Invalid URL: \(urlString)" }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12

        guard let (data, _) = try? await session.data(for: req),
              let raw = String(data: data, encoding: .utf8) else {
            return "Could not fetch page at \(urlString)"
        }
        let cleaned = Self.stripHTMLTags(from: raw)
        return String(cleaned.prefix(4000))
    }

    public static func stripHTMLTags(from html: String) -> String {
        var result = html
        if let scriptRegex = try? NSRegularExpression(pattern: "<(script|style)[^>]*>[\\s\\S]*?</\\1>", options: [.caseInsensitive]) {
            result = scriptRegex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: " ")
        }
        if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            result = tagRegex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "\n")
        }
        return result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    // MARK: - Main Agent Turn Execution

    public func runRepoChatTurn(
        thread: ChatThread,
        userPrompt: String,
        attachments: [ChatAttachmentItem] = [],
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

        var recordedTools: [ToolCallItem] = []
        var repoContextSnippet = ""
        var repoDefaultBranch = thread.branchName ?? "main"

        // Log active Agent or Workflow steps if selected (Build 4)
        if let wfId = thread.activeWorkflowId,
           let wf = (WorkflowPreset.kiroBuiltIns).first(where: { $0.id == wfId }) {
            for stepName in wf.steps {
                let wfStep = ToolCallItem(
                    toolName: "workflow_step",
                    summaryLine: "\(wf.name): \(stepName)",
                    inputSummary: stepName,
                    outputDetail: "Executed agent step '\(stepName)' in workflow '\(wf.name)'.",
                    status: .completed,
                    finishedAt: Date()
                )
                recordedTools.append(wfStep)
                onToolStepUpdate?(wfStep)
            }
        } else if let agentId = thread.activeAgentId,
                  let agent = AgentPreset.kiroBuiltIns.first(where: { $0.id == agentId }) {
            let agStep = ToolCallItem(
                toolName: "agent_role",
                summaryLine: "Running agent: \(agent.name)",
                inputSummary: agent.name,
                outputDetail: agent.rolePrompt,
                status: .completed,
                finishedAt: Date()
            )
            recordedTools.append(agStep)
            onToolStepUpdate?(agStep)
        }

        // Log any attached files/photos (Build 2)
        if !attachments.isEmpty {
            for att in attachments {
                let attStep = ToolCallItem(
                    toolName: "attachment",
                    summaryLine: "Attached \(att.name) (\(att.kind.rawValue))",
                    inputSummary: att.name,
                    outputDetail: att.textPreview ?? "Binary attachment (\(att.sizeBytes) bytes)",
                    status: .completed,
                    finishedAt: Date()
                )
                recordedTools.append(attStep)
                onToolStepUpdate?(attStep)
                if let preview = att.textPreview {
                    repoContextSnippet += "--- Attached File: \(att.name) ---\n\(preview.prefix(2500))\n\n"
                }
            }
        }

        // Check if URL is in prompt -> Read a web page tool (Answer 26)
        if let urlRegex = try? NSRegularExpression(pattern: "https?://[^\\s\\)\\\"\\>]+", options: [.caseInsensitive]) {
            let matches = urlRegex.matches(in: userPrompt, options: [], range: NSRange(userPrompt.startIndex..., in: userPrompt))
            for match in matches.prefix(2) {
                if let range = Range(match.range, in: userPrompt),
                   let url = URL(string: String(userPrompt[range])) {
                    var pageStep = ToolCallItem(
                        toolName: "read_web_page",
                        summaryLine: "Read web page \(url.host ?? url.absoluteString)",
                        inputSummary: url.absoluteString,
                        status: .running
                    )
                    onToolStepUpdate?(pageStep)
                    let pageText = await readWebPage(urlString: url.absoluteString)
                    pageStep.outputDetail = pageText
                    pageStep.status = .completed
                    pageStep.finishedAt = Date()
                    recordedTools.append(pageStep)
                    onToolStepUpdate?(pageStep)
                    repoContextSnippet += "--- Web Page (\(url.absoluteString)) ---\n\(pageText.prefix(2000))\n\n"
                }
            }
        }

        // Run free Web Search if webSearchEnabled is turned on (Answer 26)
        if thread.webSearchEnabled {
            var webStep = ToolCallItem(
                toolName: "web_search",
                summaryLine: "Searched the web for \"\(String(userPrompt.prefix(40)))\"",
                inputSummary: userPrompt,
                status: .running
            )
            onToolStepUpdate?(webStep)
            let searchText = await searchWebFree(query: userPrompt)
            webStep.outputDetail = searchText
            webStep.status = .completed
            webStep.finishedAt = Date()
            recordedTools.append(webStep)
            onToolStepUpdate?(webStep)
            repoContextSnippet += "--- Web Search Results ---\n\(searchText)\n\n"
        }

        // Gather live repo context ONLY when the user has actually selected a repository
        if let repoFullName = thread.repoFullName, !repoFullName.isEmpty {
            let branch = thread.branchName ?? "main"
            repoDefaultBranch = branch
            let lower = userPrompt.lowercased()

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

                // Answer 11: Automatically check repo GitHub Actions builds when enabled
                if settings.autoCheckRepoBuildsEnabled,
                   let runs = try? await githubService.fetchWorkflowRuns(fullName: repoFullName, token: githubToken),
                   let latestRun = runs.first {
                    let buildSummary = "Latest build #\(latestRun.runNumber) (\(latestRun.name)): \(latestRun.status) \(latestRun.conclusion ?? "")"
                    let buildStep = ToolCallItem(
                        toolName: "check_repo_build",
                        summaryLine: buildSummary,
                        inputSummary: repoFullName,
                        outputDetail: "Run #\(latestRun.runNumber) on branch \(latestRun.headBranch) — \(latestRun.htmlURL)",
                        status: latestRun.conclusion == "failure" ? .failed : .completed,
                        finishedAt: Date()
                    )
                    recordedTools.append(buildStep)
                    onToolStepUpdate?(buildStep)
                    repoContextSnippet += "--- Latest GitHub Actions Build ---\n\(buildSummary) (\(latestRun.htmlURL))\n\n"
                }
            } else {
                listStep.outputDetail = "Could not reach \(repoFullName) on branch \(branch)."
                listStep.status = .failed
                listStep.finishedAt = Date()
                recordedTools.append(listStep)
                onToolStepUpdate?(listStep)
            }
        }

        // Generate Spec document if Build with spec is active (Build 5)
        let generatedSpec: SpecPlanDocument? = thread.specModeEnabled
            ? Self.buildSpecDocument(for: userPrompt, existing: thread.specDocument)
            : nil

        // Trigger Autonomous Cloud Runner on GitHub if thread.isAutonomous is enabled & connected to a repo (Build 3 — Item 2)
        if thread.isAutonomous,
           let repoFullName = thread.repoFullName, !repoFullName.isEmpty,
           let token = githubToken, !token.isEmpty {
            let branch = thread.branchName ?? "main"
            var cloudStep = ToolCallItem(
                toolName: "autonomous_cloud_job",
                summaryLine: "Starting autonomous cloud job on GitHub (\(repoFullName))",
                inputSummary: userPrompt,
                status: .running
            )
            onToolStepUpdate?(cloudStep)
            do {
                let msg = try await githubService.ensureAutonomousCallerWorkflowAndRun(
                    fullName: repoFullName,
                    branch: branch,
                    taskPrompt: userPrompt,
                    modelId: route.effectiveModelId,
                    token: token
                )
                cloudStep.summaryLine = "Autonomous job running on GitHub's computers"
                cloudStep.outputDetail = msg
                cloudStep.status = .completed
                cloudStep.finishedAt = Date()
                recordedTools.append(cloudStep)
                onToolStepUpdate?(cloudStep)
            } catch {
                cloudStep.summaryLine = "Autonomous cloud dispatch note"
                cloudStep.outputDetail = error.localizedDescription
                cloudStep.status = .completed
                cloudStep.finishedAt = Date()
                recordedTools.append(cloudStep)
                onToolStepUpdate?(cloudStep)
            }
        }

        var finalReplyText = ""
        var finalModelUsed = (openRouterKey ?? "").isEmpty ? "iPhone AI ($0)" : route.effectiveModelId
        var finalCostUSD = 0.0
        var savedMems: [String] = []
        var paused = false

        // Call OpenRouter Chat Completions API if key is present
        if let apiKey = openRouterKey, !apiKey.isEmpty, route.effectiveModelId != "apple/foundation" {
            do {
                let (rawReplyText, actualModel, costUSD) = try await callOpenRouterCompletions(
                    apiKey: apiKey,
                    route: route,
                    thread: thread,
                    userPrompt: userPrompt,
                    repoContext: repoContextSnippet,
                    memories: settings.memoriesMasterSwitch ? memories.filter(\.isEnabled) : []
                )
                let (cleanReply, extractedMems) = Self.extractAutoMemories(from: rawReplyText)
                finalReplyText = cleanReply
                finalModelUsed = actualModel
                finalCostUSD = costUSD
                savedMems = extractedMems
                let newTotal = thread.totalCostUSD + costUSD
                paused = AutoModelRouter.shouldStopAndAskForCost(
                    currentJobCostUSD: newTotal,
                    stopSwitchEnabled: settings.stopAndAskAtCostEnabled,
                    thresholdUSD: settings.stopAndAskCostThresholdUSD
                )
            } catch {
                finalReplyText = buildOnDeviceRepoReply(
                    userPrompt: userPrompt,
                    thread: thread,
                    recordedTools: recordedTools,
                    repoContext: repoContextSnippet,
                    hasOpenRouterKey: true
                )
            }
        } else {
            finalReplyText = buildOnDeviceRepoReply(
                userPrompt: userPrompt,
                thread: thread,
                recordedTools: recordedTools,
                repoContext: repoContextSnippet,
                hasOpenRouterKey: !(openRouterKey ?? "").isEmpty
            )
        }

        // Parse any AI file edits (`[WRITE_FILE: path]...[/WRITE_FILE]` or `[DELETE_FILE: path]`) (Build 2 — Item 1)
        let (replyWithoutFileBlocks, fileOps) = Self.extractFileOperations(from: finalReplyText)
        finalReplyText = replyWithoutFileBlocks

        var questions = Self.extractNumberedQuestions(from: finalReplyText)
        var savedReceipt: SavedChangeReceipt? = nil

        if !fileOps.isEmpty,
           let repoFullName = thread.repoFullName, !repoFullName.isEmpty,
           let token = githubToken, !token.isEmpty {
            // Answer 12: Ask before deleting files or changing `.github/workflows/` unless user already told us to get on with it
            if let safetyQuestion = Self.requiresSafetyConfirmation(operations: fileOps, userPrompt: userPrompt, isAutonomous: thread.isAutonomous) {
                questions.append(safetyQuestion)
                let safetyStep = ToolCallItem(
                    toolName: "safety_confirmation",
                    summaryLine: "Paused to confirm deleting files or editing .github/workflows/",
                    inputSummary: fileOps.map(\.path).joined(separator: ", "),
                    outputDetail: safetyQuestion.prompt,
                    status: .completed,
                    finishedAt: Date()
                )
                recordedTools.append(safetyStep)
                onToolStepUpdate?(safetyStep)
            } else {
                var saveStep = ToolCallItem(
                    toolName: "save_repo_changes",
                    summaryLine: "Saving \(fileOps.count) file change(s) to \(repoFullName)",
                    inputSummary: fileOps.map(\.path).joined(separator: ", "),
                    status: .running
                )
                onToolStepUpdate?(saveStep)
                do {
                    let receipt = try await githubService.saveChangesToRepo(
                        fullName: repoFullName,
                        pickedBranch: thread.branchName ?? "main",
                        defaultBranch: repoDefaultBranch,
                        commitMessage: "MAIPA-G chat update: \(fileOps.map(\.path).joined(separator: ", "))",
                        operations: fileOps,
                        settings: settings,
                        token: token
                    )
                    savedReceipt = receipt
                    saveStep.summaryLine = receipt.state == .pendingPR
                        ? "Opened Pull Request #\(receipt.prNumber ?? 0) on \(receipt.workingBranch)"
                        : "Saved \(fileOps.count) file(s) straight to \(receipt.workingBranch)"
                    saveStep.outputDetail = "Branch: \(receipt.workingBranch)\nCommit: \(receipt.commitSha)"
                    saveStep.status = .completed
                    saveStep.finishedAt = Date()
                    recordedTools.append(saveStep)
                    onToolStepUpdate?(saveStep)
                } catch {
                    saveStep.summaryLine = "Failed to save file changes"
                    saveStep.outputDetail = error.localizedDescription
                    saveStep.status = .failed
                    saveStep.finishedAt = Date()
                    recordedTools.append(saveStep)
                    onToolStepUpdate?(saveStep)
                }
            }
        }

        // Item 5: Picture Generation inline in chat bubbles
        let (replyCleanedOfImageTag, generatedImgURL) = Self.extractOrGenerateImageURL(from: finalReplyText, userPrompt: userPrompt)
        finalReplyText = replyCleanedOfImageTag

        if paused {
            let newTotal = thread.totalCostUSD + finalCostUSD
            questions.append(
                NumberedQuestionItem(
                    number: questions.count + 1,
                    prompt: String(format: "This chat has reached $%.4f (your stop-and-ask limit is $%.2f). Keep going?", newTotal, settings.stopAndAskCostThresholdUSD),
                    options: ["Keep going", "Switch to free AIs ($0)", "Stop here"]
                )
            )
        }

        return AgentTurnResult(
            assistantText: finalReplyText,
            modelUsed: finalModelUsed,
            stepCostUSD: finalCostUSD,
            toolCalls: recordedTools,
            questions: questions,
            autoSavedMemories: savedMems,
            generatedSpec: generatedSpec,
            pausedForCostLimit: paused,
            savedChangeReceipt: savedReceipt,
            generatedImageURL: generatedImgURL
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
        You are MAIPA-G, a native iPhone AI assistant for apps, games, and everyday work.
        Use plain English. Keep answers short, clear, and casual. Never assume.
        When you need choices from the user, ask short numbered questions like:
        1. Question text? [Option A | Option B]
        When the user tells you a lasting preference to remember for future chats, include `[MEMORY: short note]` on its own line so MAIPA-G saves it automatically.
        When a repository is connected and the user asks you to create or edit a file in the repository, include:
        [WRITE_FILE: path/to/file.ext]
        ...full file content...
        [/WRITE_FILE]
        To delete a file when requested, include `[DELETE_FILE: path/to/file.ext]`.
        When the user asks you to draw or generate a picture/icon, include `[GENERATE_IMAGE: short title]`.
        """
        if let agentId = thread.activeAgentId,
           let agent = AgentPreset.kiroBuiltIns.first(where: { $0.id == agentId }) {
            systemText += "\n\nActive Agent Role (\(agent.name)): \(agent.rolePrompt)"
        }
        if !memories.isEmpty {
            systemText += "\n\nActive Memories:\n" + memories.map { "- \($0.text)" }.joined(separator: "\n")
        }
        if !repoContext.isEmpty {
            systemText += "\n\nContext Data:\n" + repoContext
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

        var modelToCall = route.effectiveModelId
        if thread.webSearchEnabled && !route.usesFreePoolOnly && !modelToCall.hasSuffix(":online") {
            modelToCall += ":online"
        }

        var payload: [String: Any] = [
            "model": modelToCall,
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
        if let repoFullName = thread.repoFullName, !repoFullName.isEmpty {
            let branchLabel = thread.branchName ?? "main"
            var lines: [String] = []
            lines.append("Checked **\(repoFullName)** on branch **\(branchLabel)**:")
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
            lines.append("\nTap any step above to expand its full output, or tap the **Files** button at the top right to view and edit files in \(repoFullName).")
            return lines.joined(separator: "\n")
        }

        // No repository selected (clean everyday/chat state)
        var lines: [String] = []
        if !recordedTools.isEmpty {
            for tool in recordedTools {
                lines.append("- \(tool.summaryLine)")
            }
            if let webTool = recordedTools.first(where: { ($0.toolName == "web_search" || $0.toolName == "read_web_page") && $0.status == .completed }) {
                lines.append("\nWeb summary:\n\(webTool.outputDetail.prefix(700))")
            }
        } else {
            lines.append("Got it: **\"\(userPrompt)\"**")
            lines.append("\nYou're currently chatting with **no repository connected**.")
            lines.append("- To work on a project, tap **Pick a repo…** below the message box.")
            if !hasOpenRouterKey {
                lines.append("- To use cloud AIs (free or paid), tap **Sign in with OpenRouter**.")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Build 2 (Item 1 & Answer 12): Extract File Edits & Safety Confirmations

    public static func extractFileOperations(from text: String) -> (cleanedText: String, operations: [RepoFileEditOperation]) {
        var operations: [RepoFileEditOperation] = []
        var working = text

        // 1. Parse [WRITE_FILE: path]...[/WRITE_FILE]
        if let writeRegex = try? NSRegularExpression(pattern: "\\[WRITE_FILE:\\s*([^\\]]+)\\]\\s*([\\s\\S]*?)\\[/WRITE_FILE\\]", options: [.caseInsensitive]) {
            let matches = writeRegex.matches(in: working, options: [], range: NSRange(working.startIndex..., in: working))
            for match in matches.reversed() {
                if let pathRange = Range(match.range(at: 1), in: working),
                   let contentRange = Range(match.range(at: 2), in: working),
                   let fullRange = Range(match.range(at: 0), in: working) {
                    let path = String(working[pathRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let content = String(working[contentRange]).trimmingCharacters(in: .newlines)
                    if !path.isEmpty {
                        operations.insert(RepoFileEditOperation(path: path, kind: .update, content: content), at: 0)
                    }
                    working.replaceSubrange(fullRange, with: "\nSaved update for `\(path)`.")
                }
            }
        }

        // 2. Parse [DELETE_FILE: path]
        if let deleteRegex = try? NSRegularExpression(pattern: "\\[DELETE_FILE:\\s*([^\\]]+)\\]", options: [.caseInsensitive]) {
            let matches = deleteRegex.matches(in: working, options: [], range: NSRange(working.startIndex..., in: working))
            for match in matches.reversed() {
                if let pathRange = Range(match.range(at: 1), in: working),
                   let fullRange = Range(match.range(at: 0), in: working) {
                    let path = String(working[pathRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !path.isEmpty {
                        operations.insert(RepoFileEditOperation(path: path, kind: .delete, content: ""), at: 0)
                    }
                    working.replaceSubrange(fullRange, with: "\nRequested deletion of `\(path)`.")
                }
            }
        }

        return (working.trimmingCharacters(in: .whitespacesAndNewlines), operations)
    }

    /// Answer 12: Ask before deleting files or changing `.github/workflows/` unless the user already confirmed or enabled Autonomous mode.
    public static func requiresSafetyConfirmation(
        operations: [RepoFileEditOperation],
        userPrompt: String,
        isAutonomous: Bool = false
    ) -> NumberedQuestionItem? {
        if isAutonomous { return nil }
        let lowerPrompt = userPrompt.lowercased()
        let alreadyConfirmed = lowerPrompt.contains("yes, go ahead")
            || lowerPrompt.contains("get on with it")
            || lowerPrompt.contains("confirm delete")
            || lowerPrompt.contains("confirm workflow")

        if alreadyConfirmed { return nil }

        let deletes = operations.filter { $0.kind == .delete }.map(\.path)
        let workflows = operations.filter { $0.path.hasPrefix(".github/workflows/") }.map(\.path)

        if !deletes.isEmpty || !workflows.isEmpty {
            let affected = (deletes + workflows).joined(separator: ", ")
            return NumberedQuestionItem(
                number: 1,
                prompt: "Confirm before changing workflow or deleting files (\(affected))?",
                options: ["Yes, go ahead", "No, skip that"]
            )
        }
        return nil
    }

    // MARK: - Item 5: Picture Generation Inline in Chat

    public static func extractOrGenerateImageURL(from text: String, userPrompt: String) -> (cleanedText: String, imageURL: String?) {
        var working = text
        var imageLabel: String? = nil

        if let imgRegex = try? NSRegularExpression(pattern: "\\[GENERATE_IMAGE:\\s*([^\\]]+)\\]", options: [.caseInsensitive]),
           let match = imgRegex.firstMatch(in: working, options: [], range: NSRange(working.startIndex..., in: working)),
           let labelRange = Range(match.range(at: 1), in: working),
           let fullRange = Range(match.range(at: 0), in: working) {
            imageLabel = String(working[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            working.replaceSubrange(fullRange, with: "")
        } else {
            let lower = userPrompt.lowercased()
            if lower.contains("generate an image") || lower.contains("draw a picture") || lower.contains("generate a picture") || lower.contains("create an icon") {
                imageLabel = String(userPrompt.prefix(36))
            }
        }

        guard let title = imageLabel, !title.isEmpty else {
            return (working.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }

        let safeTitle = title
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "\"", with: "")
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="512" height="320" viewBox="0 0 512 320">
          <defs>
            <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%" stop-color="#1E1B4B"/>
              <stop offset="50%" stop-color="#4338CA"/>
              <stop offset="100%" stop-color="#D97706"/>
            </linearGradient>
          </defs>
          <rect width="512" height="320" rx="28" fill="url(#bg)"/>
          <circle cx="256" cy="135" r="56" fill="#F59E0B" opacity="0.9"/>
          <circle cx="236" cy="128" r="7" fill="#FFFFFF"/>
          <circle cx="276" cy="128" r="7" fill="#FFFFFF"/>
          <text x="256" y="242" fill="#FFFFFF" font-family="-apple-system, sans-serif" font-size="20" font-weight="bold" text-anchor="middle">\(safeTitle)</text>
          <text x="256" y="272" fill="#E0E7FF" font-family="-apple-system, sans-serif" font-size="13" text-anchor="middle">Generated in MAIPA-G</text>
        </svg>
        """
        let b64 = Data(svg.utf8).base64EncodedString()
        return (working.trimmingCharacters(in: .whitespacesAndNewlines), "data:image/svg+xml;base64,\(b64)")
    }

    public static func buildSpecDocument(for prompt: String, existing: SpecPlanDocument?) -> SpecPlanDocument {
        if let existing = existing {
            return existing
        }
        let words = prompt
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
            .prefix(3)
        let slug = words.isEmpty ? "feature-spec" : words.joined(separator: "-")
        let shortTitle = String(prompt.prefix(44))
        return SpecPlanDocument(
            slug: slug,
            title: shortTitle,
            whatItWillBuild: "Build and verify: \(prompt)\n\n- Plain-English goal agreed before writing code.\n- Stored in `.kiro/specs/\(slug)/` so Kiro and MAIPA-G can both read it.",
            howItWorks: "1. Update the relevant Swift / repo files cleanly.\n2. Run checks and verify there are no errors.\n3. Save to a clean side branch and open a pull request (or save straight to the branch if configured).",
            tasks: [
                SpecTaskItem(number: 1, title: "Confirm requirements and edge cases"),
                SpecTaskItem(number: 2, title: "Implement the code changes in the repository"),
                SpecTaskItem(number: 3, title: "Run build and check the result")
            ]
        )
    }

    public static func extractAutoMemories(from text: String) -> (cleanedText: String, memories: [String]) {
        var memories: [String] = []
        var keptLines: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("[MEMORY:"), trimmed.hasSuffix("]") {
                let start = trimmed.index(trimmed.startIndex, offsetBy: 8)
                let end = trimmed.index(before: trimmed.endIndex)
                let note = String(trimmed[start..<end]).trimmingCharacters(in: .whitespaces)
                if !note.isEmpty {
                    memories.append(note)
                }
            } else {
                keptLines.append(line)
            }
        }
        return (keptLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), memories)
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
