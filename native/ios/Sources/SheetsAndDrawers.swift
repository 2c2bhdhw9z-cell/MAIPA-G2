import SwiftUI
import AgentCore

// MARK: - Side Menu View (Chats in groups, searchable, Agents, Workflows, Memories, Settings)

public struct SideMenuView: View {
    @ObservedObject public var state: AppState
    public let accentColor: Color
    @State private var searchText: String = ""
    @State private var selectedSection: SideMenuTab = .chats
    @State private var newGroupName: String = ""
    @State private var newMemoryText: String = ""

    public enum SideMenuTab: String, CaseIterable {
        case chats = "Chats"
        case agents = "Agents"
        case workflows = "Workflows"
        case memories = "Memories"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("MAIPA-G")
                    .font(.headline.weight(.bold))
                Spacer()
                Button {
                    state.createNewChat()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("New")
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Search chats, agents, memories…", text: $searchText)
                    .font(.caption)
            }
            .padding(9)
            .background(Color(UIColor.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 16)

            // Tab Switcher
            Picker("Section", selection: $selectedSection) {
                ForEach(SideMenuTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            // Content List
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    switch selectedSection {
                    case .chats:
                        chatsListSection
                    case .agents:
                        agentsListSection
                    case .workflows:
                        workflowsListSection
                    case .memories:
                        memoriesListSection
                    }
                }
                .padding(.horizontal, 16)
            }

            Divider()

            // Bottom Settings Button
            Button {
                state.isSideMenuOpen = false
                state.isSettingsPresented = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Settings")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("OpenRouter, GitHub, colours, cost limit")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
    }

    private var chatsListSection: some View {
        let filtered = state.chats.filter {
            searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText)
        }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(filtered) { chat in
                Button {
                    state.activeChatId = chat.id
                    state.isSideMenuOpen = false
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(chat.title)
                                .font(.subheadline.weight(state.activeChatId == chat.id ? .semibold : .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(chat.repoFullName ?? "No repo")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("·")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "$%.4f", chat.totalCostUSD))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(state.activeChatId == chat.id ? accentColor.opacity(0.16) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private var agentsListSection: some View {
        let allAgents = AgentPreset.kiroBuiltIns + state.customAgents
        let filtered = allAgents.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) || $0.summary.localizedCaseInsensitiveContains(searchText)
        }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(filtered) { agent in
                VStack(alignment: .leading, spacing: 4) {
                    Text(agent.name)
                        .font(.subheadline.weight(.semibold))
                    Text(agent.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var workflowsListSection: some View {
        let allWorkflows = WorkflowPreset.kiroBuiltIns + state.customWorkflows
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(allWorkflows) { wf in
                VStack(alignment: .leading, spacing: 4) {
                    Text(wf.name)
                        .font(.subheadline.weight(.semibold))
                    Text(wf.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(wf.steps.joined(separator: " → "))
                        .font(.caption2)
                        .foregroundStyle(accentColor)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var memoriesListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Use memories in new chats", isOn: $state.settings.memoriesMasterSwitch)
                .font(.caption.weight(.semibold))

            HStack {
                TextField("Add a memory…", text: $newMemoryText)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let trimmed = newMemoryText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    state.memories.insert(MemoryItem(text: trimmed, isEnabled: true, source: .user), at: 0)
                    newMemoryText = ""
                    state.saveWorkspaceLocallyAndSync()
                }
                .font(.caption.bold())
            }

            if state.memories.isEmpty {
                Text("Memories start empty. Tap ★ on any chat message or add one above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($state.memories) { $mem in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mem.text)
                                .font(.caption)
                            Text(mem.source.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $mem.isEnabled)
                            .labelsHidden()
                    }
                    .padding(8)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}

// MARK: - Repo Files Browser Sheet (Top-right Files button)

public struct RepoFilesSheet: View {
    @ObservedObject public var state: AppState
    public let accentColor: Color
    @Environment(\.dismiss) private var dismiss
    @State private var filterText: String = ""
    @State private var selectedFilePath: String? = nil
    @State private var selectedFileContent: String = ""
    @State private var isLoadingFile: Bool = false

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let filePath = selectedFilePath {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button {
                                selectedFilePath = nil
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("Back to files")
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                            Spacer()
                            Text(filePath)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        Divider()

                        if isLoadingFile {
                            ProgressView("Reading \(filePath)…")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView([.vertical, .horizontal]) {
                                Text(selectedFileContent)
                                    .font(.system(size: 12, design: .monospaced))
                                    .padding(14)
                            }
                        }
                    }
                } else {
                    List {
                        let blobs = state.currentRepoTree.filter {
                            $0.type == "blob" && (filterText.isEmpty || $0.path.localizedCaseInsensitiveContains(filterText))
                        }
                        if blobs.isEmpty {
                            Text(state.selectedRepo == nil ? "Pick a repository first." : "No files found.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(blobs) { item in
                                Button {
                                    Task {
                                        await openFile(item.path)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "doc.text")
                                            .foregroundStyle(accentColor)
                                        Text(item.path)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if let sz = item.size {
                                            Text("\(sz) B")
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .searchable(text: $filterText, prompt: "Filter files in \(state.selectedRepo?.name ?? "repo")")
                }
            }
            .navigationTitle(state.selectedRepo?.fullName ?? "Repository Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if let repo = state.selectedRepo, state.currentRepoTree.isEmpty {
                    await state.refreshBranchesAndTree(for: repo.fullName, branch: state.selectedBranchName)
                }
            }
        }
    }

    private func openFile(_ path: String) async {
        guard let repo = state.selectedRepo else { return }
        selectedFilePath = path
        isLoadingFile = true
        defer { isLoadingFile = false }
        do {
            selectedFileContent = try await state.githubService.fetchFileContent(
                fullName: repo.fullName,
                path: path,
                branch: state.selectedBranchName,
                token: state.githubToken
            )
        } catch {
            selectedFileContent = "Could not load file: \(error.localizedDescription)"
        }
    }
}

// MARK: - Repo Picker, Branch Picker, and AI Model Picker Sheets

public struct RepoPickerSheet: View {
    @ObservedObject public var state: AppState
    public let accentColor: Color
    @Environment(\.dismiss) private var dismiss
    @State private var search: String = ""

    public var body: some View {
        NavigationStack {
            List {
                let filtered = state.availableRepos.filter {
                    search.isEmpty || $0.fullName.localizedCaseInsensitiveContains(search)
                }
                ForEach(filtered) { repo in
                    Button {
                        Task {
                            await state.selectRepository(repo)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(repo.fullName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("Default branch: \(repo.defaultBranch)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if state.selectedRepo?.fullName == repo.fullName {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(accentColor)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search repositories")
            .navigationTitle("Pick a Repository")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh") {
                        Task { await state.refreshRepositories() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

public struct BranchPickerSheet: View {
    @ObservedObject public var state: AppState
    public let accentColor: Color
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            List {
                ForEach(state.availableBranches) { branch in
                    Button {
                        Task {
                            await state.selectBranch(branch.name)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.branch")
                                .foregroundStyle(accentColor)
                            Text(branch.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if state.selectedBranchName == branch.name {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pick a Branch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

public struct ModelPickerSheet: View {
    @ObservedObject public var state: AppState
    public let accentColor: Color
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            List {
                Section("AI Model") {
                    ForEach(AIModelOption.defaultCatalog) { model in
                        Button {
                            if let idx = state.chats.firstIndex(where: { $0.id == state.activeChatId }) {
                                state.chats[idx].selectedModelId = model.id
                                state.saveWorkspaceLocallyAndSync()
                            }
                            dismiss()
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(model.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        if model.isFree {
                                            Text("FREE")
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green.opacity(0.2))
                                                .foregroundStyle(.green)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    Text(model.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if state.activeChat?.selectedModelId == model.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pick AI Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - GitHub, OpenRouter, Connections, and Settings Sheets

public struct GitHubSignInSheet: View {
    @ObservedObject public var state: AppState
    public let accentColor: Color
    @Environment(\.dismiss) private var dismiss
    @State private var manualToken: String = ""

    public var body: some View {
        NavigationStack {
            Form {
                Section("One-Tap GitHub Sign-In (No keys to copy)") {
                    if let user = state.githubUsername {
                        HStack {
                            Text("Connected as")
                            Spacer()
                            Text(user).bold()
                        }
                        Button("Disconnect GitHub", role: .destructive) {
                            state.disconnectGitHub()
                        }
                    } else {
                        Button {
                            Task {
                                await state.startGitHubDeviceFlowSignIn()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "person.badge.key.fill")
                                Text("Connect GitHub in Browser")
                                    .fontWeight(.semibold)
                            }
                        }

                        if let flow = state.activeDeviceFlow {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("1. Tap Copy Code & Open GitHub:")
                                    .font(.caption)
                                Text(flow.userCode)
                                    .font(.title2.monospaced().bold())
                                    .foregroundStyle(accentColor)
                                Button("Copy Code & Open GitHub") {
                                    UIPasteboard.general.string = flow.userCode
                                    if let url = URL(string: flow.verificationUri) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(accentColor)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }

                Section("Or Connect via GitHub App Manifest") {
                    Button("Open GitHub App Setup Page") {
                        if let url = URL(string: "https://2c2bhdhw9z-cell.github.io/MAIPA-G2/?mode=github-manifest") {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section("Fallback Token (Optional)") {
                    SecureField("Paste token only if needed", text: $manualToken)
                    Button("Save Token") {
                        Task {
                            await state.completeGitHubSignIn(withToken: manualToken)
                            dismiss()
                        }
                    }
                    .disabled(manualToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Connect GitHub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

public struct OpenRouterSignInSheet: View {
    @ObservedObject public var state: AppState
    public let accentColor: Color
    @Environment(\.dismiss) private var dismiss
    @State private var manualKey: String = ""

    public var body: some View {
        NavigationStack {
            Form {
                Section("Sign in with OpenRouter") {
                    Text("Sign in once and tap Allow, with no key to copy. When your balance is $0, Auto uses only the free AIs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        Task {
                            await state.startOpenRouterOneTapSignIn()
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Sign in with OpenRouter")
                                .fontWeight(.semibold)
                        }
                    }
                }

                Section("Current Balance") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(state.openRouterKey != nil ? "Connected" : "Using Free Pool ($0)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Balance")
                        Spacer()
                        Text(String(format: "$%.2f", state.openRouterBalanceUSD))
                            .font(.body.monospacedDigit())
                    }
                    if state.openRouterKey != nil {
                        Button("Sign Out of OpenRouter", role: .destructive) {
                            state.signOutOpenRouter()
                        }
                    }
                }

                Section("Fallback Key (Optional)") {
                    SecureField("sk-or-v1-...", text: $manualKey)
                    Button("Save OpenRouter Key") {
                        state.saveOpenRouterAPIKey(manualKey)
                        dismiss()
                    }
                    .disabled(manualKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("OpenRouter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

public struct ConnectionsRegistrySheet: View {
    @ObservedObject public var state: AppState
    public let accentColor: Color
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    public var body: some View {
        NavigationStack {
            List {
                Section("Popular MCP Connectors") {
                    let filtered = state.connectors.filter {
                        query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query)
                    }
                    ForEach(filtered) { item in
                        Button {
                            if item.id == "github" {
                                dismiss()
                                state.isGitHubSignInPresented = true
                            } else if let idx = state.connectors.firstIndex(where: { $0.id == item.id }) {
                                state.connectors[idx].isConnected.toggle()
                            }
                        } label: {
                            HStack {
                                Image(systemName: item.iconName)
                                    .foregroundStyle(accentColor)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(item.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.isConnected ? "Connected ✓" : "Connect")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(item.isConnected ? accentColor : .secondary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search 40,000+ MCP connectors…")
            .navigationTitle("Connections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

public struct SettingsSheetView: View {
    @ObservedObject public var state: AppState
    public let accentColor: Color
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            Form {
                Section("Accounts") {
                    Button {
                        dismiss()
                        state.isOpenRouterSignInPresented = true
                    } label: {
                        HStack {
                            Text("OpenRouter")
                            Spacer()
                            Text(state.openRouterKey != nil ? String(format: "Connected ($%.2f)", state.openRouterBalanceUSD) : "Sign in")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        dismiss()
                        state.isGitHubSignInPresented = true
                    } label: {
                        HStack {
                            Text("GitHub")
                            Spacer()
                            Text(state.githubUsername ?? "Connect")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Money & Cost Control (Answer 7b)") {
                    Toggle("Stop and ask when a job has cost $__", isOn: $state.settings.stopAndAskAtCostEnabled)
                    if state.settings.stopAndAskAtCostEnabled {
                        HStack {
                            Text("Stop limit ($ USD)")
                            Spacer()
                            TextField("1.00", value: $state.settings.stopAndAskCostThresholdUSD, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                }

                Section("Appearance & Colours (Answer 31)") {
                    Picker("Theme", selection: $state.settings.themeMode) {
                        ForEach(AppThemeMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    ForEach(AccentColorOption.options) { opt in
                        Button {
                            state.settings.accentHex = opt.hex
                            state.saveWorkspaceLocallyAndSync()
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(hex: opt.hex))
                                    .frame(width: 18, height: 18)
                                Text(opt.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if state.settings.accentHex.uppercased() == opt.hex.uppercased() {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color(hex: opt.hex))
                                }
                            }
                        }
                    }
                }

                Section("Effects & Mascot Switches (Answers 32 & 33)") {
                    Toggle("Show mascot on Home screen", isOn: $state.settings.showMascotOnHome)
                    Toggle("Gentle mascot floating effect", isOn: $state.settings.mascotMotionEnabled)
                    Toggle("Smooth chat message transitions", isOn: $state.settings.smoothChatTransitionsEnabled)
                    Toggle("Tool step expand animations", isOn: $state.settings.toolStepAnimationsEnabled)
                }

                Section("Workflows & Notifications (Answers 15 & 18)") {
                    Toggle("Notifications when a job finishes or needs you", isOn: $state.settings.notificationsEnabled)
                    Picker("Start workflows", selection: $state.settings.workflowChoice) {
                        ForEach(WorkflowTriggerChoice.allCases, id: \.self) { ch in
                            Text(ch.displayName).tag(ch)
                        }
                    }
                }

                Section("MAIPA-G Build & Updates") {
                    HStack {
                        Text("Installed build")
                        Spacer()
                        Text("Build \(state.currentBuildNumberString)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if let release = state.latestBuildRelease {
                        HStack {
                            Text("Latest GitHub build")
                            Spacer()
                            Text(release.title)
                                .font(.caption)
                                .foregroundStyle(accentColor)
                        }
                        Button("Download Newest MAIPA-G.ipa") {
                            if let url = URL(string: release.ipaDownloadURL) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        state.saveWorkspaceLocallyAndSync()
                        dismiss()
                    }
                }
            }
        }
    }
}
