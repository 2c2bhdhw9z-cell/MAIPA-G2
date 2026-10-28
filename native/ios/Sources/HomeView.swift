import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AgentCore

public struct HomeView: View {
    @ObservedObject public var state: AppState
    @State private var expandedToolIds: Set<String> = []
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isFileImporterPresented: Bool = false

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
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.white)
                            Text(banner)
                                .font(.caption)
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Spacer()
                            Button("OK") {
                                state.statusBannerText = nil
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(accentColor.opacity(0.92))
                    }

                    // Active Spec Bar if Spec Mode created a document
                    if let chat = state.activeChat, let spec = chat.specDocument {
                        specProgressCard(spec: spec, chatId: chat.id)
                            .padding(.horizontal, 14)
                            .padding(.top, 6)
                    }

                    // Main Chat or Home Greeting
                    if let chat = state.activeChat, !chat.messages.isEmpty {
                        chatMessagesList(chat: chat)
                    } else {
                        homeZeroStateGreeting
                    }

                    // Composer Box & Repo/Branch Pickers
                    composerSection
                }
                .background(Color(UIColor.systemBackground))
                .toolbar(.hidden, for: .navigationBar)
            }

            // Slide-out Side Menu
            if state.isSideMenuOpen {
                Color.black.opacity(0.48)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            state.isSideMenuOpen = false
                        }
                    }

                SideMenuView(state: state, accentColor: accentColor)
                    .frame(width: 308)
                    .transition(.move(edge: .leading))
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    let b64 = data.base64EncodedString()
                    let att = ChatAttachmentItem(
                        name: "Photo-\(Int(Date().timeIntervalSince1970)).jpg",
                        kind: .photo,
                        mimeType: "image/jpeg",
                        textPreview: "[Attached iPhone Photo (\(data.count) bytes)]",
                        base64Data: b64,
                        sizeBytes: data.count
                    )
                    state.pendingAttachments.append(att)
                }
                selectedPhotoItem = nil
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item, .plainText, .sourceCode, .json, .image, .pdf],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let secured = url.startAccessingSecurityScopedResource()
                defer { if secured { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    let textPreview = String(data: data, encoding: .utf8).map { String($0.prefix(3000)) }
                    let att = ChatAttachmentItem(
                        name: url.lastPathComponent,
                        kind: .file,
                        mimeType: "application/octet-stream",
                        textPreview: textPreview ?? "[Binary file: \(url.lastPathComponent) (\(data.count) bytes)]",
                        sizeBytes: data.count
                    )
                    state.pendingAttachments.append(att)
                }
            }
        }
        .sheet(isPresented: $state.isFilesSheetPresented) {
            RepoFilesSheet(state: state, accentColor: accentColor)
        }
        .sheet(isPresented: $state.isBuildsSheetPresented) {
            BuildsAndActionsSheet(state: state, accentColor: accentColor)
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
        .sheet(isPresented: $state.isGroupPickerPresented) {
            GroupPickerSheet(state: state, accentColor: accentColor)
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
        .sheet(isPresented: $state.isLivePreviewPresented) {
            LiveWebPreviewSheet(state: state, accentColor: accentColor)
        }
    }

    // MARK: - Top Bar (Side-menu button left, Cost counter middle, Undo / Builds / Files right)

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    state.isSideMenuOpen.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Spacer()

            VStack(spacing: 2) {
                HStack(spacing: 5) {
                    Text(state.activeChat?.title ?? "New chat")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if let groupId = state.activeChat?.groupId,
                       let grp = state.groups.first(where: { $0.id == groupId }) {
                        Text(grp.name)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accentColor.opacity(0.18))
                            .foregroundStyle(accentColor)
                            .clipShape(Capsule())
                    }
                }

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

            HStack(spacing: 6) {
                // 1-Tap Undo button when the chat has a saved change (Item 9 & Answer 9)
                if let chat = state.activeChat,
                   let receipt = chat.lastSavedReceipt,
                   receipt.state != .undone && receipt.state != .thrownAway {
                    Button {
                        Task {
                            await state.undoLastSavedChange(inChatId: chat.id)
                        }
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.orange)
                            .frame(width: 34, height: 34)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .accessibilityLabel("Undo last saved change")
                }

                // Builds / GitHub Actions button when a repo is selected (Build 3)
                if state.selectedRepo != nil {
                    Button {
                        state.isBuildsSheetPresented = true
                    } label: {
                        Image(systemName: "hammer")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 34, height: 34)
                            .background(Color(UIColor.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .accessibilityLabel("Builds and GitHub Actions")
                }

                // Files Browser & Editor button
                Button {
                    state.isFilesSheetPresented = true
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .accessibilityLabel("Repository Files")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Home Greeting & Uncluttered Connections Row

    private var homeZeroStateGreeting: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 22)

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

                    if let repo = state.selectedRepo {
                        Text("Connected to \(repo.fullName) (\(state.selectedBranchName)). Read, search, or edit files, or run a build.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    } else {
                        Text("Start chatting right away, or pick a GitHub repo below when you want to work on code.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }

                // Clean Connection Chips Row:
                // Only shows GitHub, OpenRouter, any connector you actually turned on, and "+ Connectors"
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
                            .padding(.horizontal, 12)
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
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(state.openRouterKey != nil ? accentColor.opacity(0.18) : Color(UIColor.secondarySystemBackground))
                            .foregroundStyle(state.openRouterKey != nil ? accentColor : .primary)
                            .clipShape(Capsule())
                        }

                        ForEach(state.homeVisibleThirdPartyConnectors) { conn in
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
                                .background(conn.isConnected ? accentColor.opacity(0.15) : Color(UIColor.secondarySystemBackground))
                                .foregroundStyle(conn.isConnected ? accentColor : .secondary)
                                .clipShape(Capsule())
                            }
                        }

                        Button {
                            state.isConnectionsSheetPresented = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle")
                                    .font(.caption)
                                Text("Connectors")
                                    .font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(Color(UIColor.secondarySystemBackground))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Adaptive Starter Actions (adapts to whether a repo is selected or not)
                VStack(alignment: .leading, spacing: 8) {
                    if let repo = state.selectedRepo {
                        Text("Quick actions for \(repo.name)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        quickStarterButton(
                            title: "List and summarize the files in \(repo.name)",
                            icon: "folder.badge.gearshape"
                        )
                        quickStarterButton(
                            title: "Search \(repo.name) for bugs, TODOs, or build issues",
                            icon: "magnifyingglass"
                        )
                        quickStarterButton(
                            title: "Build with spec: plan a new feature for \(repo.name)",
                            icon: "list.clipboard"
                        ) {
                            if let idx = state.chats.firstIndex(where: { $0.id == state.activeChatId }) {
                                state.chats[idx].specModeEnabled = true
                            }
                            Task {
                                await state.sendCurrentMessage(overrideText: "Plan a new feature for \(repo.name) with a step-by-step spec.")
                            }
                        }
                    } else {
                        Text("Get started")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        Button {
                            if state.githubToken == nil {
                                state.isGitHubSignInPresented = true
                            } else {
                                state.isRepoPickerPresented = true
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "book.closed.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(accentColor)
                                    .frame(width: 24)
                                Text(state.githubToken == nil ? "Connect GitHub to pick a repository" : "Pick a GitHub repository for this chat")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(Color(UIColor.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        quickStarterButton(
                            title: "Plan a new app or game with Build with spec",
                            icon: "list.clipboard"
                        ) {
                            if let idx = state.chats.firstIndex(where: { $0.id == state.activeChatId }) {
                                state.chats[idx].specModeEnabled = true
                            }
                            Task {
                                await state.sendCurrentMessage(overrideText: "Help me plan a new iPhone app or game step by step.")
                            }
                        }

                        quickStarterButton(
                            title: "Run a multi-step agent workflow",
                            icon: "arrow.triangle.2.circlepath"
                        ) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                state.isSideMenuOpen = true
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)

                Spacer(minLength: 16)
            }
        }
    }

    private func quickStarterButton(title: String, icon: String, customAction: (() -> Void)? = nil) -> some View {
        Button {
            if let customAction {
                customAction()
            } else {
                Task {
                    await state.sendCurrentMessage(overrideText: title)
                }
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

    // MARK: - Interactive Spec Card (Item 6 & Answer 25)

    private func specProgressCard(spec: SpecPlanDocument, chatId: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Spec: \(spec.title)", systemImage: "list.clipboard.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accentColor)
                Spacer()
                Text(spec.stage == .whatItWillBuild ? "Step 1: What it'll build" : (spec.stage == .howItWorks ? "Step 2: How it works" : (spec.stage == .taskChecklist ? "Step 3: Task list" : "Approved ✓")))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(accentColor.opacity(0.16))
                    .foregroundStyle(accentColor)
                    .clipShape(Capsule())
            }

            if spec.stage == .whatItWillBuild {
                Text(spec.whatItWillBuild)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if spec.stage == .howItWorks {
                Text(spec.howItWorks)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(spec.tasks) { task in
                        Button {
                            state.toggleSpecTask(taskId: task.id, inChatId: chatId)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.caption)
                                    .foregroundStyle(task.isCompleted ? .green : .secondary)
                                Text("\(task.number). \(task.title)")
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .strikethrough(task.isCompleted)
                                Spacer()
                            }
                        }
                    }
                }
            }

            if spec.stage != .building {
                HStack {
                    Spacer()
                    Button {
                        Task {
                            await state.approveNextSpecStage(inChatId: chatId)
                        }
                    } label: {
                        Text(spec.stage == .taskChecklist ? "OK, approve & save spec" : "OK, next step →")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(accentColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Chat Messages List (Collapsible Tool Lines + PR Add/Throw Away + Numbered Question Buttons)

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
                    if state.settings.smoothChatTransitionsEnabled {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    } else {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func messageRow(msg: ChatMessage, chatId: String) -> some View {
        VStack(alignment: msg.role == .user ? .trailing : .leading, spacing: 8) {
            // Attachment pills on user messages
            if !msg.attachments.isEmpty {
                HStack(spacing: 6) {
                    ForEach(msg.attachments) { att in
                        HStack(spacing: 4) {
                            Image(systemName: att.kind == .photo ? "photo.fill" : "doc.fill")
                                .font(.caption2)
                            Text(att.name)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(Capsule())
                    }
                }
            }

            // Tool Call Lines (each thing the AI does shows as a small line you can tap open)
            if !msg.toolCalls.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(msg.toolCalls) { step in
                        VStack(alignment: .leading, spacing: 4) {
                            Button {
                                let toggle = {
                                    if expandedToolIds.contains(step.id) {
                                        expandedToolIds.remove(step.id)
                                    } else {
                                        expandedToolIds.insert(step.id)
                                    }
                                }
                                if state.settings.toolStepAnimationsEnabled {
                                    withAnimation(.easeInOut(duration: 0.18)) { toggle() }
                                } else {
                                    toggle()
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
            VStack(alignment: .leading, spacing: 8) {
                Text(msg.text)
                    .font(.body)
                    .foregroundStyle(msg.role == .user ? .white : .primary)

                if let imageURL = msg.generatedImageURL, !imageURL.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.artframe")
                                .foregroundStyle(accentColor)
                            Text("Generated Picture")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Button("Preview") {
                                state.livePreviewTitle = "Generated Picture"
                                state.livePreviewHTML = "<html><body style='margin:0;background:#0d0c14;display:flex;align-items:center;justify-content:center;height:100vh;'><img src='\(imageURL)' style='max-width:94%;border-radius:20px;'/></body></html>"
                                state.isLivePreviewPresented = true
                            }
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(accentColor)
                        }
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.12, green: 0.11, blue: 0.29), accentColor.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 150)
                            .overlay(
                                VStack(spacing: 6) {
                                    Image(systemName: "sparkles.rectangle.stack.fill")
                                        .font(.system(size: 32))
                                        .foregroundStyle(.white)
                                    Text("Tap Preview to view full generated image")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                            )
                            .onTapGesture {
                                state.livePreviewTitle = "Generated Picture"
                                state.livePreviewHTML = "<html><body style='margin:0;background:#0d0c14;display:flex;align-items:center;justify-content:center;height:100vh;'><img src='\(imageURL)' style='max-width:94%;border-radius:20px;'/></body></html>"
                                state.isLivePreviewPresented = true
                            }
                    }
                    .padding(8)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if !msg.autoSavedMemories.isEmpty {
                    ForEach(msg.autoSavedMemories, id: \.self) { note in
                        HStack(spacing: 4) {
                            Image(systemName: "brain.head.profile")
                                .font(.caption2)
                            Text("Saved memory: \(note)")
                                .font(.caption2)
                        }
                        .foregroundStyle(accentColor)
                        .padding(.top, 2)
                    }
                }

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

            // Build 2: Pull Request "Add it" / "Throw away" & Undo Card (Answer 9)
            if let receipt = msg.savedChangeReceipt {
                savedChangeCard(receipt: receipt, chatId: chatId, messageId: msg.id)
            }

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

    private func savedChangeCard(receipt: SavedChangeReceipt, chatId: String, messageId: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.triangle.pull")
                    .foregroundStyle(accentColor)
                Text(receipt.prNumber != nil ? "Pull Request #\(receipt.prNumber!) (\(receipt.workingBranch) → \(receipt.baseBranch))" : "Saved to \(receipt.workingBranch)")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(receipt.state.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            if receipt.state == .pendingPR {
                HStack(spacing: 10) {
                    Button {
                        Task {
                            await state.approveAndMergePR(receipt: receipt, inChatId: chatId, messageId: messageId)
                        }
                    } label: {
                        Label("Add it", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    Button {
                        Task {
                            await state.discardPR(receipt: receipt, inChatId: chatId, messageId: messageId)
                        }
                    } label: {
                        Label("Throw away", systemImage: "trash")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.red.opacity(0.16))
                            .foregroundStyle(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    if let prURL = receipt.prURL, let url = URL(string: prURL) {
                        Link("View PR", destination: url)
                            .font(.caption.weight(.medium))
                    }
                }
            } else if receipt.state == .savedDirect {
                Button {
                    Task {
                        await state.undoLastSavedChange(inChatId: chatId)
                    }
                } label: {
                    Label("Undo this save", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.orange.opacity(0.18))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(10)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Composer Box & Repo/Branch Pickers (Kiro + Arena Design)

    private var composerSection: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 9) {
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

                        // Add to group (Kiro composer chip — PLAN.md line 17 & 24)
                        Button {
                            state.isGroupPickerPresented = true
                        } label: {
                            let hasGroup = state.activeChat?.groupId != nil
                            HStack(spacing: 4) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.caption2)
                                Text("Add to group")
                                    .font(.caption2.weight(.semibold))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(hasGroup ? accentColor.opacity(0.22) : Color(UIColor.tertiarySystemBackground))
                            .foregroundStyle(hasGroup ? accentColor : .secondary)
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
                                    .font(.system(size: 8))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(accentColor.opacity(0.16))
                            .foregroundStyle(accentColor)
                            .clipShape(Capsule())
                        }

                        // Thinking Level Picker (ONLY shown when chosen AI supports thinking — Answer 6)
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

                // Pending Attachments Strip (Photos & Files)
                if !state.pendingAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(state.pendingAttachments) { att in
                                HStack(spacing: 5) {
                                    Image(systemName: att.kind == .photo ? "photo.fill" : "doc.text.fill")
                                        .font(.caption2)
                                        .foregroundStyle(accentColor)
                                    Text(att.name)
                                        .font(.caption2)
                                        .lineLimit(1)
                                    Button {
                                        state.pendingAttachments.removeAll(where: { $0.id == att.id })
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(UIColor.tertiarySystemBackground))
                                .clipShape(Capsule())
                            }
                        }
                    }
                }

                // Message Input Field
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Ask anything...", text: $state.draftMessage, axis: .vertical)
                        .lineLimit(1...5)
                        .font(.subheadline)
                        .padding(.vertical, 4)

                    let canSend = (!state.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !state.pendingAttachments.isEmpty) && !state.isSendingMessage
                    Button {
                        Task {
                            await state.sendCurrentMessage()
                        }
                    } label: {
                        Image(systemName: state.isSendingMessage ? "ellipsis" : "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(canSend ? accentColor : Color.gray.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .disabled(!canSend)
                }

                // Bottom toolbar inside box: Web search, Attach (Photos + Files), Live Preview, Route status
                HStack(spacing: 14) {
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

                    // Attach Menu (PhotosPicker + File Importer + Repo File)
                    Menu {
                        Button {
                            isFileImporterPresented = true
                        } label: {
                            Label("Attach File from iPhone", systemImage: "doc.badge.plus")
                        }

                        if state.selectedRepo != nil {
                            Button {
                                state.isFilesSheetPresented = true
                            } label: {
                                Label("Browse or Edit Repo Files", systemImage: "folder")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "paperclip")
                                .font(.caption)
                            Text("Attach")
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                    }

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        HStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.caption)
                            Text("Photo")
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                    }

                    Button {
                        state.isLivePreviewPresented = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.display")
                                .font(.caption)
                            Text("Preview")
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

            // Under message box: Repo picker + Branch picker (only when repo is picked) + Gear + X
            HStack(spacing: 8) {
                Button {
                    if state.githubToken == nil {
                        state.isGitHubSignInPresented = true
                    } else {
                        state.isRepoPickerPresented = true
                    }
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
                    .foregroundStyle(state.selectedRepo != nil ? .primary : .secondary)
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
                    .accessibilityLabel("Disconnect repository from this chat")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}
