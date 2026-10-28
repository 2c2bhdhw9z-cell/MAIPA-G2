import Foundation
import SwiftUI
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
    @Published public var connectors: [MCPConnectorItem] = MCPConnectorItem.defaultConnectors
    @Published public var settings: AppSettings = AppSettings()

    // Composer & Pickers
    @Published public var draftMessage: String = ""
    @Published public var selectedRepo: GitHubRepo? = nil
    @Published public var selectedBranchName: String = "main"
    @Published public var availableRepos: [GitHubRepo] = []
    @Published public var availableBranches: [GitHubBranch] = []
    @Published public var currentRepoTree: [GitHubTreeItem] = []

    // Auth & Accounts
    @Published public var githubUsername: String? = nil
    @Published public var githubToken: String? = nil
    @Published public var openRouterKey: String? = nil
    @Published public var openRouterBalanceUSD: Double = 0.0
    @Published public var isSendingMessage: Bool = false
    @Published public var isLoadingRepoData: Bool = false
    @Published public var statusBannerText: String? = nil

    // GitHub Device Flow State (for 1-tap no-key sign-in)
    @Published public var activeDeviceFlow: GitHubDeviceFlowStart? = nil
    @Published public var isPollingDeviceFlow: Bool = false

    // Build Update Check
    @Published public var latestBuildRelease: GitHubBuildReleaseInfo? = nil

    // Navigation & Drawers
    @Published public var isSideMenuOpen: Bool = false
    @Published public var isFilesSheetPresented: Bool = false
    @Published public var isRepoPickerPresented: Bool = false
    @Published public var isBranchPickerPresented: Bool = false
    @Published public var isModelPickerPresented: Bool = false
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
                self.settings = bundle.settings
            }
        }

        if chats.isEmpty {
            let initial = ChatThread(
                title: "Welcome to MAIPA-G",
                repoFullName: "2c2bhdhw9z-cell/MAIPA-G2",
                branchName: "main",
                selectedModelId: "openrouter/auto",
                thinkingLevel: .medium
            )
            chats = [initial]
            activeChatId = initial.id
        } else if activeChatId == nil {
            activeChatId = chats.first?.id
        }

        updateGitHubConnectorStatus()
    }

    public func saveWorkspaceLocallyAndSync() {
        let bundle = PersistedWorkspaceBundle(
            chats: chats,
            groups: groups,
            memories: memories,
            customAgents: customAgents,
            customWorkflows: customWorkflows,
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
        await refreshRepositories()
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
                self.settings = remoteBundle.settings
            }
        }
        self.latestBuildRelease = try? await githubService.fetchLatestMAIPAGRelease(token: githubToken)
    }

    // MARK: - GitHub Repos, Branches, and Tree

    public func refreshRepositories() async {
        isLoadingRepoData = true
        defer { isLoadingRepoData = false }
        do {
            let repos = try await githubService.fetchRepositories(token: githubToken)
            self.availableRepos = repos
            if selectedRepo == nil {
                if let maipa = repos.first(where: { $0.fullName.lowercased().contains("maipa-g") }) ?? repos.first {
                    await selectRepository(maipa)
                }
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
        if let idx = chats.firstIndex(where: { $0.id == activeChatId }) {
            chats[idx].repoFullName = nil
        }
        saveWorkspaceLocallyAndSync()
    }

    public func refreshBranchesAndTree(for fullName: String, branch: String) async {
        if let branches = try? await githubService.fetchBranches(fullName: fullName, token: githubToken) {
            self.availableBranches = branches
        }
        if let tree = try? await githubService.fetchTree(fullName: fullName, branch: branch, token: githubToken) {
            self.currentRepoTree = tree
        }
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

    // MARK: - Chat Actions

    public func createNewChat(inGroupId groupId: String? = nil) {
        let newChat = ChatThread(
            title: "New chat",
            groupId: groupId,
            repoFullName: selectedRepo?.fullName ?? "2c2bhdhw9z-cell/MAIPA-G2",
            branchName: selectedBranchName,
            selectedModelId: "openrouter/auto",
            thinkingLevel: .medium,
            isAutonomous: false
        )
        chats.insert(newChat, at: 0)
        activeChatId = newChat.id
        isSideMenuOpen = false
        saveWorkspaceLocallyAndSync()
    }

    public func sendCurrentMessage(overrideText: String? = nil) async {
        let text = (overrideText ?? draftMessage).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSendingMessage else { return }
        if overrideText == nil {
            draftMessage = ""
        }

        if activeChatId == nil {
            createNewChat()
        }
        guard let chatId = activeChatId,
              let chatIdx = chats.firstIndex(where: { $0.id == chatId }) else { return }

        let userMsg = ChatMessage(role: .user, text: text)
        chats[chatIdx].messages.append(userMsg)
        if chats[chatIdx].messages.count == 1 {
            chats[chatIdx].title = String(text.prefix(38))
        }
        chats[chatIdx].updatedAt = Date()

        // Create placeholder assistant message so tool steps update live
        let placeholderId = UUID().uuidString
        let placeholderMsg = ChatMessage(
            id: placeholderId,
            role: .assistant,
            text: "Working…",
            modelUsed: chats[chatIdx].selectedModelId
        )
        chats[chatIdx].messages.append(placeholderMsg)
        isSendingMessage = true

        let threadSnapshot = chats[chatIdx]
        let result = await openRouterService.runRepoChatTurn(
            thread: threadSnapshot,
            userPrompt: text,
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

        if let cIdx = chats.firstIndex(where: { $0.id == chatId }),
           let mIdx = chats[cIdx].messages.firstIndex(where: { $0.id == placeholderId }) {
            chats[cIdx].messages[mIdx].text = result.assistantText
            chats[cIdx].messages[mIdx].modelUsed = result.modelUsed
            chats[cIdx].messages[mIdx].costUSD = result.stepCostUSD
            chats[cIdx].messages[mIdx].toolCalls = result.toolCalls
            chats[cIdx].messages[mIdx].questions = result.questions
            chats[cIdx].messages[mIdx].stopAndAskTriggered = result.pausedForCostLimit
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
