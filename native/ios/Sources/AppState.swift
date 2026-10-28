import Foundation
import SwiftUI
import UIKit
import UserNotifications
import AgentCore

@MainActor
public final class AppState: ObservableObject {
    // Workspace State
    @Published public var chats: [ChatThread] = []
    @Published public var groups: [ChatGroup] = []
    @Published public var activeChatId: String? = nil
    @Published public var memories: [MemoryItem] = []
    @Published public var customAgents: [AgentPreset] = []
    @Published public var customWorkflows: [WorkflowPreset] = []
    @Published public var customConnectors: [MCPConnectorItem] = []
    @Published public var connectors: [MCPConnectorItem] = MCPConnectorItem.defaultConnectors
    @Published public var registrySearchResults: [MCPConnectorItem] = []
    @Published public var isSearchingRegistry: Bool = false
    @Published public var settings: AppSettings = AppSettings()

    // Composer, Attachments & Pickers (Starts NOT connected to any repo)
    @Published public var draftMessage: String = ""
    @Published public var pendingAttachments: [ChatAttachmentItem] = []
    @Published public var selectedRepo: GitHubRepo? = nil
    @Published public var selectedBranchName: String = "main"
    @Published public var availableRepos: [GitHubRepo] = []
    @Published public var availableBranches: [GitHubBranch] = []
    @Published public var currentRepoTree: [GitHubTreeItem] = []
    @Published public var workflowRuns: [GitHubWorkflowRunItem] = []

    // Auth & Accounts
    @Published public var githubUsername: String? = nil
    @Published public var githubToken: String? = nil
    @Published public var openRouterKey: String? = nil
    @Published public var openRouterBalanceUSD: Double = 0.0
    @Published public var isSendingMessage: Bool = false
    @Published public var isLoadingRepoData: Bool = false
    @Published public var statusBannerText: String? = nil

    // GitHub Device Flow State
    @Published public var activeDeviceFlow: GitHubDeviceFlowStart? = nil
    @Published public var isPollingDeviceFlow: Bool = false

    // Build Update Check
    @Published public var latestBuildRelease: GitHubBuildReleaseInfo? = nil

    // Live Web Preview State (Build 5 — Answer 30)
    @Published public var isLivePreviewPresented: Bool = false
    @Published public var livePreviewTitle: String = "Live Preview"
    @Published public var livePreviewHTML: String? = nil
    @Published public var livePreviewURLString: String = "https://2c2bhdhw9z-cell.github.io/MAIPA-G2/"

    // Navigation & Drawers
    @Published public var isSideMenuOpen: Bool = false
    @Published public var isFilesSheetPresented: Bool = false
    @Published public var isBuildsSheetPresented: Bool = false
    @Published public var isRepoPickerPresented: Bool = false
    @Published public var isBranchPickerPresented: Bool = false
    @Published public var isModelPickerPresented: Bool = false
    @Published public var isGroupPickerPresented: Bool = false
    @Published public var isSettingsPresented: Bool = false
    @Published public var isGitHubSignInPresented: Bool = false
    @Published public var isOpenRouterSignInPresented: Bool = false
    @Published public var isConnectionsSheetPresented: Bool = false

    public let githubService = GitHubService()
    public let openRouterService = OpenRouterService()
    private var pendingPKCEVerifier: String? = nil

    private let keychainGitHubTokenKey = "maipag.github.token"
    private let keychainGitHubUserKey = "maipag.github.username"
    private let keychainOpenRouterKey = "maipag.openrouter.key"

    public init() {
        loadFromDiskAndKeychain()
        Task {
            await initialBootRefresh()
        }
    }

    public var activeChat: ChatThread? {
        guard let id = activeChatId else { return nil }
        return chats.first(where: { $0.id == id })
    }

    public var currentBuildNumberString: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }

    /// Connectors shown as pills on the Home screen:
    /// By default (`showUnconnectedConnectorsOnHome == false`), unconnected 3rd-party connectors
    /// (Drive, Docs, Notion, Sheets, etc.) are hidden so they never clutter the Home screen.
    public var homeVisibleThirdPartyConnectors: [MCPConnectorItem] {
        let all = connectors + customConnectors
        return all.filter { item in
            guard item.id != "github" && item.id != "fetch-reader" else { return false }
            guard !settings.hiddenConnectorIds.contains(item.id) else { return false }
            if settings.showUnconnectedConnectorsOnHome {
                return item.isPopular || item.isConnected
            }
            return item.isConnected
        }
    }

    // MARK: - Persistence & Boot

    private var workspaceFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("maipa-g-workspace.json")
    }

    public func loadFromDiskAndKeychain() {
        self.githubToken = KeychainHelper.readString(forKey: keychainGitHubTokenKey)
        self.githubUsername = KeychainHelper.readString(forKey: keychainGitHubUserKey)
        self.openRouterKey = KeychainHelper.readString(forKey: keychainOpenRouterKey)

        if let data = try? Data(contentsOf: workspaceFileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let bundle = try? decoder.decode(PersistedWorkspaceBundle.self, from: data) {
                self.chats = bundle.chats
                self.groups = bundle.groups
                self.memories = bundle.memories
                self.customAgents = bundle.customAgents
                self.customWorkflows = bundle.customWorkflows
                self.customConnectors = bundle.customConnectors
                self.settings = bundle.settings
            }
        }

        // Clean up any old auto-connected default chat that had 0 messages
        for idx in chats.indices {
            if chats[idx].messages.isEmpty && chats[idx].title == "Welcome to MAIPA-G" {
                chats[idx].title = "New chat"
                chats[idx].repoFullName = nil
                chats[idx].branchName = nil
            }
        }

        if chats.isEmpty {
            let initial = ChatThread(
                title: "New chat",
                repoFullName: nil,
                branchName: nil,
                selectedModelId: "openrouter/auto",
                thinkingLevel: .medium
            )
            chats = [initial]
            activeChatId = initial.id
        } else if activeChatId == nil {
            activeChatId = chats.first?.id
        }

        // Ensure selectedRepo starts nil on boot unless the active chat already has messages in a repo
        self.selectedRepo = nil
        updateGitHubConnectorStatus()
    }

    public func saveWorkspaceLocallyAndSync() {
        let bundle = PersistedWorkspaceBundle(
            chats: chats,
            groups: groups,
            memories: memories,
            customAgents: customAgents,
            customWorkflows: customWorkflows,
            customConnectors: customConnectors,
            settings: settings,
            lastSyncedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(bundle) {
            try? data.write(to: workspaceFileURL, options: .atomic)
        }

        if let token = githubToken, !token.isEmpty, let owner = githubUsername, !owner.isEmpty {
            Task {
                try? await githubService.syncWorkspaceToPrivateRepo(bundle: bundle, owner: owner, token: token)
            }
        }
    }

    public func initialBootRefresh() async {
        if let token = githubToken, !token.isEmpty {
            await refreshRepositories()
        }
        if let key = openRouterKey, !key.isEmpty {
            if let bal = try? await openRouterService.fetchBalance(apiKey: key) {
                self.openRouterBalanceUSD = bal.remainingUSD
            }
        }
        if let token = githubToken, !token.isEmpty, let owner = githubUsername, !owner.isEmpty {
            if let remoteBundle = try? await githubService.loadWorkspaceFromPrivateRepo(owner: owner, token: token),
               remoteBundle.chats.count > self.chats.count {
                self.chats = remoteBundle.chats
                self.groups = remoteBundle.groups
                self.memories = remoteBundle.memories
                self.customAgents = remoteBundle.customAgents
                self.customWorkflows = remoteBundle.customWorkflows
                self.customConnectors = remoteBundle.customConnectors
                self.settings = remoteBundle.settings
            }
        }
        self.latestBuildRelease = try? await githubService.fetchLatestMAIPAGRelease(token: githubToken)
    }

    // MARK: - GitHub Repos, Branches, Tree & Actions (Never auto-selects a repo on boot)

    public func refreshRepositories() async {
        guard let token = githubToken, !token.isEmpty else {
            self.availableRepos = []
            return
        }
        isLoadingRepoData = true
        defer { isLoadingRepoData = false }
        do {
            let repos = try await githubService.fetchRepositories(token: token)
            self.availableRepos = repos
            // Sync selectedRepo object only if the active chat explicitly has a repoFullName set by the user
            if let activeRepoName = activeChat?.repoFullName,
               let matched = repos.first(where: { $0.fullName == activeRepoName }) {
                self.selectedRepo = matched
                self.selectedBranchName = activeChat?.branchName ?? matched.defaultBranch
            }
        } catch {
            // Keep existing list on transient offline error
        }
    }

    public func selectRepository(_ repo: GitHubRepo) async {
        self.selectedRepo = repo
        self.selectedBranchName = repo.defaultBranch
        if let idx = chats.firstIndex(where: { $0.id == activeChatId }) {
            chats[idx].repoFullName = repo.fullName
            chats[idx].branchName = repo.defaultBranch
        }
        await refreshBranchesAndTree(for: repo.fullName, branch: repo.defaultBranch)
        await refreshWorkflowRuns()
        saveWorkspaceLocallyAndSync()
    }

    public func selectBranch(_ branchName: String) async {
        self.selectedBranchName = branchName
        if let idx = chats.firstIndex(where: { $0.id == activeChatId }) {
            chats[idx].branchName = branchName
        }
        if let repo = selectedRepo {
            await refreshBranchesAndTree(for: repo.fullName, branch: branchName)
        }
        saveWorkspaceLocallyAndSync()
    }

    public func clearSelectedRepo() {
        self.selectedRepo = nil
        self.currentRepoTree = []
        self.availableBranches = []
        self.workflowRuns = []
        if let idx = chats.firstIndex(where: { $0.id == activeChatId }) {
            chats[idx].repoFullName = nil
            chats[idx].branchName = nil
        }
        saveWorkspaceLocallyAndSync()
    }

    public func switchActiveChat(to chatId: String) {
        self.activeChatId = chatId
        if let chat = chats.first(where: { $0.id == chatId }) {
            if let repoName = chat.repoFullName,
               let repo = availableRepos.first(where: { $0.fullName == repoName }) {
                self.selectedRepo = repo
                self.selectedBranchName = chat.branchName ?? repo.defaultBranch
                Task {
                    await refreshBranchesAndTree(for: repo.fullName, branch: self.selectedBranchName)
                }
            } else {
                self.selectedRepo = nil
                self.currentRepoTree = []
                self.availableBranches = []
            }
        }
        self.isSideMenuOpen = false
    }

    public func refreshBranchesAndTree(for fullName: String, branch: String) async {
        if let branches = try? await githubService.fetchBranches(fullName: fullName, token: githubToken) {
            self.availableBranches = branches
        }
        if let tree = try? await githubService.fetchTree(fullName: fullName, branch: branch, token: githubToken) {
            self.currentRepoTree = tree
        }
    }

    public func refreshWorkflowRuns() async {
        guard let repo = selectedRepo else {
            self.workflowRuns = []
            return
        }
        if let runs = try? await githubService.fetchWorkflowRuns(fullName: repo.fullName, token: githubToken) {
            self.workflowRuns = runs
        }
    }

    public func triggerRepoBuildOnGitHub() async {
        guard let repo = selectedRepo, let token = githubToken, !token.isEmpty else {
            statusBannerText = "Connect GitHub and pick a repo first to start a build."
            return
        }
        do {
            try await githubService.triggerWorkflowDispatch(
                fullName: repo.fullName,
                workflowFileName: "ios.yml",
                ref: selectedBranchName,
                token: token
            )
            statusBannerText = "Started GitHub Actions build on \(repo.fullName) (\(selectedBranchName))."
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await refreshWorkflowRuns()
        } catch {
            statusBannerText = "Could not trigger ios.yml build: \(error.localizedDescription)"
        }
    }

    // MARK: - Build 2: Saving Code Changes, PR "Add it" / "Throw away", and 1-Tap Undo

    public func saveRepoFileChanges(operations: [RepoFileEditOperation], commitMessage: String) async throws -> SavedChangeReceipt {
        guard let repo = selectedRepo else {
            throw GitHubServiceError.notConnected
        }
        guard let token = githubToken, !token.isEmpty else {
            throw GitHubServiceError.notConnected
        }
        let receipt = try await githubService.saveChangesToRepo(
            fullName: repo.fullName,
            pickedBranch: selectedBranchName,
            defaultBranch: repo.defaultBranch,
            commitMessage: commitMessage,
            operations: operations,
            settings: settings,
            token: token
        )
        if let cIdx = chats.firstIndex(where: { $0.id == activeChatId }) {
            chats[cIdx].lastSavedReceipt = receipt
            let summaryText = receipt.state == .pendingPR
                ? "Opened Pull Request #\(receipt.prNumber ?? 0) on side branch `\(receipt.workingBranch)`. Tap **Add it** below to merge into `\(receipt.baseBranch)` and delete the side branch, or **Throw away** to close it."
                : "Saved changes (`\(String(receipt.commitSha.prefix(7)))`) straight to `\(receipt.workingBranch)`. Tap **Undo** anytime to take back this change."
            let sysMsg = ChatMessage(
                role: .assistant,
                text: summaryText,
                modelUsed: "MAIPA-G Git",
                savedChangeReceipt: receipt
            )
            chats[cIdx].messages.append(sysMsg)
        }
        await refreshBranchesAndTree(for: repo.fullName, branch: selectedBranchName)
        saveWorkspaceLocallyAndSync()
        return receipt
    }

    public func approveAndMergePR(receipt: SavedChangeReceipt, inChatId chatId: String, messageId: String) async {
        guard let token = githubToken, !token.isEmpty else { return }
        do {
            try await githubService.mergeAndTidyPullRequest(receipt: receipt, token: token)
            updateReceiptState(inChatId: chatId, messageId: messageId, newState: .merged)
            statusBannerText = "Merged into \(receipt.baseBranch) and deleted branch \(receipt.workingBranch)."
            await refreshBranchesAndTree(for: receipt.repoFullName, branch: receipt.baseBranch)
        } catch {
            statusBannerText = "Merge failed: \(error.localizedDescription)"
        }
    }

    public func discardPR(receipt: SavedChangeReceipt, inChatId chatId: String, messageId: String) async {
        guard let token = githubToken, !token.isEmpty else { return }
        do {
            try await githubService.closeAndTidyPullRequest(receipt: receipt, token: token)
            updateReceiptState(inChatId: chatId, messageId: messageId, newState: .thrownAway)
            statusBannerText = "Closed PR and deleted branch \(receipt.workingBranch)."
        } catch {
            statusBannerText = "Could not discard PR: \(error.localizedDescription)"
        }
    }

    public func undoLastSavedChange(inChatId chatId: String) async {
        guard let token = githubToken, !token.isEmpty,
              let cIdx = chats.firstIndex(where: { $0.id == chatId }),
              let receipt = chats[cIdx].lastSavedReceipt else { return }
        do {
            try await githubService.undoLastSavedChange(receipt: receipt, token: token)
            chats[cIdx].lastSavedReceipt?.state = .undone
            for mIdx in chats[cIdx].messages.indices {
                if chats[cIdx].messages[mIdx].savedChangeReceipt?.id == receipt.id {
                    chats[cIdx].messages[mIdx].savedChangeReceipt?.state = .undone
                }
            }
            statusBannerText = "Undid last saved change on \(receipt.repoFullName)."
            await refreshBranchesAndTree(for: receipt.repoFullName, branch: selectedBranchName)
            saveWorkspaceLocallyAndSync()
        } catch {
            statusBannerText = "Undo failed: \(error.localizedDescription)"
        }
    }

    private func updateReceiptState(inChatId chatId: String, messageId: String, newState: SavedChangeReceipt.ResolutionState) {
        guard let cIdx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        if chats[cIdx].lastSavedReceipt != nil {
            chats[cIdx].lastSavedReceipt?.state = newState
        }
        if let mIdx = chats[cIdx].messages.firstIndex(where: { $0.id == messageId }) {
            chats[cIdx].messages[mIdx].savedChangeReceipt?.state = newState
        }
        saveWorkspaceLocallyAndSync()
    }

    // MARK: - Build 5: MCP Connectors Management (Hide Unused, Search 40,000+ Registry, Add Custom)

    public func isConnectorHidden(_ id: String) -> Bool {
        settings.hiddenConnectorIds.contains(id)
    }

    public func toggleHideConnector(_ id: String) {
        if let idx = settings.hiddenConnectorIds.firstIndex(of: id) {
            settings.hiddenConnectorIds.remove(at: idx)
        } else {
            settings.hiddenConnectorIds.append(id)
        }
        saveWorkspaceLocallyAndSync()
    }

    public func searchMCPRegistry(query: String) async {
        isSearchingRegistry = true
        defer { isSearchingRegistry = false }
        if let items = try? await githubService.searchOfficialMCPRegistry(query: query) {
            self.registrySearchResults = items
        }
    }

    public func addCustomConnector(name: String, serverURL: String, summary: String) {
        let item = MCPConnectorItem(
            id: "custom-\(UUID().uuidString.prefix(8))",
            name: name,
            iconName: "link.circle.fill",
            category: .officialRegistry,
            summary: summary.isEmpty ? serverURL : summary,
            serverURL: serverURL,
            isPopular: true,
            isConnected: true
        )
        customConnectors.insert(item, at: 0)
        saveWorkspaceLocallyAndSync()
    }

    // MARK: - One-Tap Sign-In Flows (OpenRouter PKCE & GitHub)

    public func startOpenRouterOneTapSignIn() async {
        let verifier = PKCEHelper.generateCodeVerifier()
        let challenge = PKCEHelper.generateCodeChallenge(from: verifier)
        self.pendingPKCEVerifier = verifier

        let callbackURL = "https://2c2bhdhw9z-cell.github.io/MAIPA-G2/callback.html"
        let encodedCallback = callbackURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? callbackURL
        guard let authURL = URL(string: "https://openrouter.ai/auth?callback_url=\(encodedCallback)&code_challenge=\(challenge)&code_challenge_method=S256") else {
            return
        }

        do {
            let returnedURL = try await WebAuthCoordinator.shared.startWebAuth(url: authURL, callbackScheme: "maipag")
            await handleIncomingOAuthURL(returnedURL)
        } catch {
            self.isOpenRouterSignInPresented = true
        }
    }

    public func handleIncomingOAuthURL(_ url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = components.queryItems ?? []

        if let code = items.first(where: { $0.name == "code" })?.value {
            if let verifier = pendingPKCEVerifier {
                do {
                    let apiKey = try await openRouterService.exchangePKCECodeForAPIKey(code: code, codeVerifier: verifier)
                    saveOpenRouterAPIKey(apiKey)
                    self.pendingPKCEVerifier = nil
                    return
                } catch {
                    statusBannerText = error.localizedDescription
                }
            }
        }
    }

    public func saveOpenRouterAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.openRouterKey = trimmed
        KeychainHelper.saveString(trimmed, forKey: keychainOpenRouterKey)
        Task {
            if let bal = try? await openRouterService.fetchBalance(apiKey: trimmed) {
                self.openRouterBalanceUSD = bal.remainingUSD
            }
        }
    }

    public func signOutOpenRouter() {
        self.openRouterKey = nil
        self.openRouterBalanceUSD = 0.0
        KeychainHelper.deleteValue(forKey: keychainOpenRouterKey)
    }

    public func startGitHubDeviceFlowSignIn() async {
        do {
            let flow = try await githubService.startDeviceFlow()
            self.activeDeviceFlow = flow
            self.isPollingDeviceFlow = true

            let intervalSeconds = UInt64(max(flow.interval, 5))
            for _ in 0..<80 {
                if !isPollingDeviceFlow { break }
                try? await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
                if let token = try? await githubService.pollDeviceFlowOnce(deviceCode: flow.deviceCode) {
                    await completeGitHubSignIn(withToken: token)
                    self.activeDeviceFlow = nil
                    self.isPollingDeviceFlow = false
                    self.isGitHubSignInPresented = false
                    break
                }
            }
        } catch {
            self.statusBannerText = error.localizedDescription
        }
    }

    public func completeGitHubSignIn(withToken token: String) async {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        self.githubToken = cleaned
        KeychainHelper.saveString(cleaned, forKey: keychainGitHubTokenKey)
        if let username = try? await githubService.fetchAuthenticatedUsername(token: cleaned) {
            self.githubUsername = username
            KeychainHelper.saveString(username, forKey: keychainGitHubUserKey)
        }
        updateGitHubConnectorStatus()
        await refreshRepositories()
        saveWorkspaceLocallyAndSync()
    }

    public func disconnectGitHub() {
        self.githubToken = nil
        self.githubUsername = nil
        self.availableRepos = []
        self.selectedRepo = nil
        self.currentRepoTree = []
        KeychainHelper.deleteValue(forKey: keychainGitHubTokenKey)
        KeychainHelper.deleteValue(forKey: keychainGitHubUserKey)
        updateGitHubConnectorStatus()
    }

    private func updateGitHubConnectorStatus() {
        let connected = !(githubToken ?? "").isEmpty
        if let idx = connectors.firstIndex(where: { $0.id == "github" }) {
            connectors[idx].isConnected = connected
        }
    }

    // MARK: - Chat Actions (Starts NOT connected to a repo unless user picked one)

    public func createNewChat(inGroupId groupId: String? = nil) {
        let newChat = ChatThread(
            title: "New chat",
            groupId: groupId,
            repoFullName: selectedRepo?.fullName,
            branchName: selectedRepo != nil ? selectedBranchName : nil,
            selectedModelId: "openrouter/auto",
            thinkingLevel: .medium,
            isAutonomous: false
        )
        chats.insert(newChat, at: 0)
        activeChatId = newChat.id
        isSideMenuOpen = false
        saveWorkspaceLocallyAndSync()
    }

    public func deleteChat(_ chatId: String) {
        chats.removeAll(where: { $0.id == chatId })
        if activeChatId == chatId {
            activeChatId = chats.first?.id
        }
        if chats.isEmpty {
            createNewChat()
        } else {
            saveWorkspaceLocallyAndSync()
        }
    }

    public func sendCurrentMessage(overrideText: String? = nil) async {
        let text = (overrideText ?? draftMessage).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty, !isSendingMessage else { return }
        let promptToSend = text.isEmpty ? "Inspect attached files" : text
        let attachmentsSnapshot = pendingAttachments

        if overrideText == nil {
            draftMessage = ""
            pendingAttachments = []
        }

        if activeChatId == nil {
            createNewChat()
        }
        guard let chatId = activeChatId,
              let chatIdx = chats.firstIndex(where: { $0.id == chatId }) else { return }

        // Handle quick answers to paid balance prompt
        if promptToSend.contains("Switch to free AIs ($0)") {
            chats[chatIdx].selectedModelId = "openrouter/free"
        }

        let userMsg = ChatMessage(role: .user, text: promptToSend, attachments: attachmentsSnapshot)
        chats[chatIdx].messages.append(userMsg)
        if chats[chatIdx].messages.count == 1 {
            chats[chatIdx].title = String(promptToSend.prefix(38))
        }
        chats[chatIdx].updatedAt = Date()

        let placeholderId = UUID().uuidString
        let placeholderMsg = ChatMessage(
            id: placeholderId,
            role: .assistant,
            text: "Working…",
            modelUsed: chats[chatIdx].selectedModelId
        )
        chats[chatIdx].messages.append(placeholderMsg)
        isSendingMessage = true

        // Request background execution time on iPhone so switching apps doesn't cut off a turn (Answer 18)
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "MAIPAGChatTurn") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }

        let threadSnapshot = chats[chatIdx]
        let result = await openRouterService.runRepoChatTurn(
            thread: threadSnapshot,
            userPrompt: promptToSend,
            attachments: attachmentsSnapshot,
            memories: memories,
            settings: settings,
            openRouterKey: openRouterKey,
            openRouterBalanceUSD: openRouterBalanceUSD,
            githubToken: githubToken,
            onToolStepUpdate: { step in
                Task { @MainActor in
                    guard let cIdx = self.chats.firstIndex(where: { $0.id == chatId }),
                          let mIdx = self.chats[cIdx].messages.firstIndex(where: { $0.id == placeholderId }) else { return }
                    if let existingStepIdx = self.chats[cIdx].messages[mIdx].toolCalls.firstIndex(where: { $0.id == step.id }) {
                        self.chats[cIdx].messages[mIdx].toolCalls[existingStepIdx] = step
                    } else {
                        self.chats[cIdx].messages[mIdx].toolCalls.append(step)
                    }
                }
            }
        )

        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
        }

        // Save any AI auto-memories (Answer 24)
        for memNote in result.autoSavedMemories {
            let mem = MemoryItem(text: memNote, isEnabled: true, source: .ai)
            memories.insert(mem, at: 0)
        }

        if let cIdx = chats.firstIndex(where: { $0.id == chatId }),
           let mIdx = chats[cIdx].messages.firstIndex(where: { $0.id == placeholderId }) {
            chats[cIdx].messages[mIdx].text = result.assistantText
            chats[cIdx].messages[mIdx].modelUsed = result.modelUsed
            chats[cIdx].messages[mIdx].costUSD = result.stepCostUSD
            chats[cIdx].messages[mIdx].toolCalls = result.toolCalls
            chats[cIdx].messages[mIdx].questions = result.questions
            chats[cIdx].messages[mIdx].autoSavedMemories = result.autoSavedMemories
            chats[cIdx].messages[mIdx].stopAndAskTriggered = result.pausedForCostLimit
            if let spec = result.generatedSpec, chats[cIdx].specDocument == nil {
                chats[cIdx].specDocument = spec
            }
            chats[cIdx].totalCostUSD += result.stepCostUSD
            chats[cIdx].updatedAt = Date()
        }

        isSendingMessage = false
        saveWorkspaceLocallyAndSync()

        if settings.notificationsEnabled && UIApplication.shared.applicationState != .active {
            postLocalNotification(
                title: "MAIPA-G finished a step",
                body: result.questions.isEmpty ? "Your chat reply is ready." : "MAIPA-G has a question for you."
            )
        }
    }

    // MARK: - Spec Mode Approval Steps (Item 6 & Answer 25)

    public func approveNextSpecStage(inChatId chatId: String) async {
        guard let cIdx = chats.firstIndex(where: { $0.id == chatId }),
              var spec = chats[cIdx].specDocument else { return }

        switch spec.stage {
        case .whatItWillBuild:
            spec.whatApproved = true
            spec.stage = .howItWorks
        case .howItWorks:
            spec.howApproved = true
            spec.stage = .taskChecklist
        case .taskChecklist:
            spec.tasksApproved = true
            spec.stage = .building
            // Save spec to `.kiro/specs/<slug>/plan.md` if connected to a repo (Answer 25)
            if let repo = selectedRepo, let token = githubToken, !token.isEmpty {
                let specMarkdown = """
                # \(spec.title)

                ## What it'll build
                \(spec.whatItWillBuild)

                ## How it works
                \(spec.howItWorks)

                ## Tasks
                \(spec.tasks.map { "- [\($0.isCompleted ? "x" : " ")] \($0.number). \($0.title)" }.joined(separator: "\n"))
                """
                let op = RepoFileEditOperation(
                    path: ".kiro/specs/\(spec.slug)/plan.md",
                    kind: .create,
                    content: specMarkdown
                )
                _ = try? await saveRepoFileChanges(operations: [op], commitMessage: "Save spec .kiro/specs/\(spec.slug)/plan.md")
            }
        case .building:
            break
        }
        chats[cIdx].specDocument = spec
        saveWorkspaceLocallyAndSync()
    }

    public func toggleSpecTask(taskId: String, inChatId chatId: String) {
        guard let cIdx = chats.firstIndex(where: { $0.id == chatId }),
              let tIdx = chats[cIdx].specDocument?.tasks.firstIndex(where: { $0.id == taskId }) else { return }
        chats[cIdx].specDocument?.tasks[tIdx].isCompleted.toggle()
        saveWorkspaceLocallyAndSync()
    }

    public func toggleStarMemory(for message: ChatMessage, inChatId chatId: String) {
        guard let cIdx = chats.firstIndex(where: { $0.id == chatId }),
              let mIdx = chats[cIdx].messages.firstIndex(where: { $0.id == message.id }) else { return }
        let newState = !chats[cIdx].messages[mIdx].isStarredAsMemory
        chats[cIdx].messages[mIdx].isStarredAsMemory = newState
        if newState {
            let mem = MemoryItem(text: message.text, isEnabled: true, source: .star)
            memories.insert(mem, at: 0)
        }
        saveWorkspaceLocallyAndSync()
    }

    public func postLocalNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(req)
        }
    }
}
