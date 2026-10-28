import SwiftUI
import AgentCore

public struct HomeView: View {
    @ObservedObject public var state: AppState
    @State private var expandedToolIds: Set<String> = []

    public init(state: AppState) {
        self.state = state
    }

    private var accentColor: Color {
        Color(hex: state.settings.accentHex)
    }

    private var selectedModelOption: AIModelOption {
        let modelId = state.activeChat?.selectedModelId ?? "openrouter/auto"
        return AIModelOption.defaultCatalog.first(where: { $0.id == modelId }) ?? AIModelOption.defaultCatalog[0]
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            NavigationStack {
                VStack(spacing: 0) {
                    topBar

                    if let banner = state.statusBannerText {
                        HStack {
                            Text(banner)
                                .font(.caption)
                                .foregroundStyle(.white)
                            Spacer()
                            Button("Dismiss") {
                                state.statusBannerText = nil
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.85))
                    }

                    // Main Chat or Home Greeting
                    if let chat = state.activeChat, !chat.messages.isEmpty {
                        chatMessagesList(chat: chat)
                    } else {
                        homeZeroStateGreeting
                    }

                    // Composer Box & Repo/Branch Pickers (Kiro + Arena layout)
                    composerSection
                }
                .background(Color(UIColor.systemBackground))
                .toolbar(.hidden, for: .navigationBar)
            }

            // Slide-out Side Menu
            if state.isSideMenuOpen {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            state.isSideMenuOpen = false
                        }
                    }

                SideMenuView(state: state, accentColor: accentColor)
                    .frame(width: 300)
                    .transition(.move(edge: .leading))
            }
        }
        .sheet(isPresented: $state.isFilesSheetPresented) {
            RepoFilesSheet(state: state, accentColor: accentColor)
        }
        .sheet(isPresented: $state.isRepoPickerPresented) {
            RepoPickerSheet(state: state, accentColor: accentColor)
        }
        .sheet(isPresented: $state.isBranchPickerPresented) {
            BranchPickerSheet(state: state, accentColor: accentColor)
        }
        .sheet(isPresented: $state.isModelPickerPresented) {
            ModelPickerSheet(state: state, accentColor: accentColor)
        }
        .sheet(isPresented: $state.isSettingsPresented) {
            SettingsSheetView(state: state, accentColor: accentColor)
        }
        .sheet(isPresented: $state.isGitHubSignInPresented) {
            GitHubSignInSheet(state: state, accentColor: accentColor)
        }
        .sheet(isPresented: $state.isOpenRouterSignInPresented) {
            OpenRouterSignInSheet(state: state, accentColor: accentColor)
        }
        .sheet(isPresented: $state.isConnectionsSheetPresented) {
            ConnectionsRegistrySheet(state: state, accentColor: accentColor)
        }
    }

    // MARK: - Top Bar (Side-menu button left, Cost counter middle, Files button right)

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    state.isSideMenuOpen.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Spacer()

            VStack(spacing: 2) {
                Text(state.activeChat?.title ?? "MAIPA-G")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    let chatCost = state.activeChat?.totalCostUSD ?? 0.0
                    Text(String(format: "Chat cost: $%.4f", chatCost))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if state.openRouterKey != nil {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "Bal: $%.2f", state.openRouterBalanceUSD))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(accentColor)
                    }
                }
            }

            Spacer()

            Button {
                state.isFilesSheetPresented = true
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Home Greeting & Connections Row

    private var homeZeroStateGreeting: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 28)

                if state.settings.showMascotOnHome {
                    MAIPAGMascotView(
                        accentColor: accentColor,
                        animateFloat: state.settings.mascotMotionEnabled
                    )
                }

                VStack(spacing: 6) {
                    Text("What can I help you with?")
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .multilineTextAlignment(.center)

                    Text("Pick a repo below, read or search any file, or plan your next change.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Connection Chips Row (Arena + Kiro style)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            state.isGitHubSignInPresented = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .font(.caption.bold())
                                Text(state.githubToken != nil ? "GitHub ✓" : "Connect GitHub")
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(state.githubToken != nil ? accentColor.opacity(0.18) : Color(UIColor.secondarySystemBackground))
                            .foregroundStyle(state.githubToken != nil ? accentColor : .primary)
                            .clipShape(Capsule())
                        }

                        Button {
                            Task {
                                await state.startOpenRouterOneTapSignIn()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                    .font(.caption.bold())
                                Text(state.openRouterKey != nil ? "OpenRouter ✓" : "Sign in with OpenRouter")
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(state.openRouterKey != nil ? accentColor.opacity(0.18) : Color(UIColor.secondarySystemBackground))
                            .foregroundStyle(state.openRouterKey != nil ? accentColor : .primary)
                            .clipShape(Capsule())
                        }

                        ForEach(state.connectors.filter { $0.id != "github" }.prefix(4)) { conn in
                            Button {
                                state.isConnectionsSheetPresented = true
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: conn.iconName)
                                        .font(.caption)
                                    Text(conn.isConnected ? "\(conn.name) ✓" : conn.name)
                                        .font(.caption.weight(.medium))
                                }
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(Color(UIColor.secondarySystemBackground))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                            }
                        }

                        Button {
                            state.isConnectionsSheetPresented = true
                        } label: {
                            Text("All connectors…")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(Color(UIColor.secondarySystemBackground))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Quick Starter Prompts for the picked repo
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick repo actions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    quickStarterButton(
                        title: "Read .kiro/notes/PLAN.md and summarize Build 1",
                        icon: "doc.text.magnifyingglass"
                    )
                    quickStarterButton(
                        title: "List all files in the selected repository",
                        icon: "folder.badge.gearshape"
                    )
                    quickStarterButton(
                        title: "Search the repo for owner rules and workflow steps",
                        icon: "magnifyingglass"
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)

                Spacer(minLength: 20)
            }
        }
    }

    private func quickStarterButton(title: String, icon: String) -> some View {
        Button {
            Task {
                await state.sendCurrentMessage(overrideText: title)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(accentColor)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Chat Messages List (Collapsible Tool Lines + Numbered Question Buttons)

    private func chatMessagesList(chat: ChatThread) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(chat.messages) { msg in
                        messageRow(msg: msg, chatId: chat.id)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .onChange(of: chat.messages.count) { _, _ in
                if let lastId = chat.messages.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func messageRow(msg: ChatMessage, chatId: String) -> some View {
        VStack(alignment: msg.role == .user ? .trailing : .leading, spacing: 8) {
            // Tool Call Lines (each thing the AI does shows as a small line he can tap open)
            if !msg.toolCalls.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(msg.toolCalls) { step in
                        VStack(alignment: .leading, spacing: 4) {
                            Button {
                                if expandedToolIds.contains(step.id) {
                                    expandedToolIds.remove(step.id)
                                } else {
                                    expandedToolIds.insert(step.id)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: step.status == .running ? "hourglass" : (step.status == .completed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"))
                                        .font(.caption2)
                                        .foregroundStyle(step.status == .completed ? accentColor : .secondary)

                                    Text(step.summaryLine)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)

                                    Spacer()

                                    Image(systemName: expandedToolIds.contains(step.id) ? "chevron.up" : "chevron.down")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(UIColor.secondarySystemBackground).opacity(0.75))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }

                            if expandedToolIds.contains(step.id) && !step.outputDetail.isEmpty {
                                ScrollView(.horizontal, showsIndicators: true) {
                                    Text(step.outputDetail)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .padding(8)
                                }
                                .frame(maxHeight: 160)
                                .background(Color(UIColor.tertiarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                }
            }

            // Message Bubble
            VStack(alignment: .leading, spacing: 6) {
                Text(msg.text)
                    .font(.body)
                    .foregroundStyle(msg.role == .user ? .white : .primary)

                HStack(spacing: 8) {
                    if let model = msg.modelUsed, msg.role == .assistant {
                        Text(model)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if msg.role == .assistant {
                        Text(String(format: "$%.4f", msg.costUSD))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        state.toggleStarMemory(for: msg, inChatId: chatId)
                    } label: {
                        Image(systemName: msg.isStarredAsMemory ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundStyle(msg.isStarredAsMemory ? Color.yellow : (msg.role == .user ? .white.opacity(0.8) : .secondary))
                    }
                }
            }
            .padding(12)
            .background(msg.role == .user ? accentColor : Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Numbered Questions with Tappable Option Buttons
            if !msg.questions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(msg.questions) { q in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(q.number). \(q.prompt)")
                                .font(.subheadline.weight(.semibold))

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(q.options, id: \.self) { opt in
                                        Button {
                                            Task {
                                                await state.sendCurrentMessage(overrideText: "\(q.number): \(opt)")
                                            }
                                        } label: {
                                            Text(opt)
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(accentColor.opacity(0.18))
                                                .foregroundStyle(accentColor)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        }
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: msg.role == .user ? .trailing : .leading)
    }

    // MARK: - Composer Box & Repo/Branch Pickers (Kiro + Arena Design)

    private var composerSection: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                // Top chip row inside message box: Build with spec, Add to group, AI picker, Thinking level, Autonomous switch
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        // Build with spec
                        Button {
                            if let idx = state.chats.firstIndex(where: { $0.id == state.activeChatId }) {
                                state.chats[idx].specModeEnabled.toggle()
                            }
                        } label: {
                            let isSpec = state.activeChat?.specModeEnabled ?? false
                            HStack(spacing: 4) {
                                Image(systemName: "list.clipboard")
                                    .font(.caption2)
                                Text("Build with spec")
                                    .font(.caption2.weight(.semibold))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(isSpec ? accentColor.opacity(0.22) : Color(UIColor.tertiarySystemBackground))
                            .foregroundStyle(isSpec ? accentColor : .secondary)
                            .clipShape(Capsule())
                        }

                        // AI Model Picker button ("Auto" / "Claude Opus 5.5")
                        Button {
                            state.isModelPickerPresented = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "cpu")
                                    .font(.caption2)
                                Text(selectedModelOption.name)
                                    .font(.caption2.weight(.semibold))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(accentColor.opacity(0.16))
                            .foregroundStyle(accentColor)
                            .clipShape(Capsule())
                        }

                        // Thinking Level Picker (ONLY shown when the chosen AI supports thinking levels — Answer 6)
                        if selectedModelOption.supportsThinking {
                            Menu {
                                ForEach(ThinkingLevel.allCases, id: \.self) { level in
                                    Button {
                                        if let idx = state.chats.firstIndex(where: { $0.id == state.activeChatId }) {
                                            state.chats[idx].thinkingLevel = level
                                        }
                                    } label: {
                                        HStack {
                                            Text("Thinking: \(level.displayName)")
                                            if state.activeChat?.thinkingLevel == level {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "brain")
                                        .font(.caption2)
                                    Text("Thinking: \((state.activeChat?.thinkingLevel ?? .medium).displayName)")
                                        .font(.caption2.weight(.medium))
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color(UIColor.tertiarySystemBackground))
                                .foregroundStyle(.primary)
                                .clipShape(Capsule())
                            }
                        }

                        // Autonomous Switch (starts off — Answer 14)
                        Button {
                            if let idx = state.chats.firstIndex(where: { $0.id == state.activeChatId }) {
                                state.chats[idx].isAutonomous.toggle()
                            }
                        } label: {
                            let isAuto = state.activeChat?.isAutonomous ?? false
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(isAuto ? Color.green : Color.gray.opacity(0.5))
                                    .frame(width: 6, height: 6)
                                Text("Autonomous")
                                    .font(.caption2.weight(.semibold))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(isAuto ? Color.green.opacity(0.16) : Color(UIColor.tertiarySystemBackground))
                            .foregroundStyle(isAuto ? Color.green : .secondary)
                            .clipShape(Capsule())
                        }
                    }
                }

                // Message Input Field
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Ask anything...", text: $state.draftMessage, axis: .vertical)
                        .lineLimit(1...5)
                        .font(.subheadline)
                        .padding(.vertical, 4)

                    Button {
                        Task {
                            await state.sendCurrentMessage()
                        }
                    } label: {
                        Image(systemName: state.isSendingMessage ? "ellipsis" : "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(state.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.4) : accentColor)
                            .clipShape(Circle())
                    }
                    .disabled(state.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isSendingMessage)
                }

                // Bottom toolbar inside box: Web search, Attach, Group
                HStack(spacing: 12) {
                    Button {
                        if let idx = state.chats.firstIndex(where: { $0.id == state.activeChatId }) {
                            state.chats[idx].webSearchEnabled.toggle()
                        }
                    } label: {
                        let webOn = state.activeChat?.webSearchEnabled ?? false
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.caption)
                            Text("Web")
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(webOn ? accentColor : .secondary)
                    }

                    Button {
                        state.isFilesSheetPresented = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "paperclip")
                                .font(.caption)
                            Text("Attach")
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let chat = state.activeChat {
                        let route = AutoModelRouter.resolve(
                            selectedModelId: chat.selectedModelId,
                            balanceUSD: state.openRouterBalanceUSD,
                            userText: state.draftMessage,
                            specMode: chat.specModeEnabled,
                            isAutonomous: chat.isAutonomous
                        )
                        Text(route.explanation)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(12)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Under message box: Repo picker + Branch picker + Gear + X (Arena & Kiro combined bar)
            HStack(spacing: 8) {
                Button {
                    state.isRepoPickerPresented = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "book.closed")
                            .font(.caption2)
                        Text(state.selectedRepo?.fullName ?? "Pick a repo…")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(UIColor.secondarySystemBackground))
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
                }

                if state.selectedRepo != nil {
                    Button {
                        state.isBranchPickerPresented = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.caption2)
                            Text(state.selectedBranchName)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(UIColor.secondarySystemBackground))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                    }
                }

                Spacer()

                Button {
                    state.isSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(Circle())
                }

                if state.selectedRepo != nil {
                    Button {
                        state.clearSelectedRepo()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color(UIColor.secondarySystemBackground))
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}
