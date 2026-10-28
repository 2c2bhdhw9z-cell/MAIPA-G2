import SwiftUI
import WebKit
import AgentCore

// MARK: - Side Menu View (Chats in groups, searchable, Agents, Workflows, Memories, Settings)

public struct SideMenuView: View {
    @ObservedObject public var state: AppState
    public let accentColor: Color
    @State private var searchText: String = ""
    @State private var selectedSection: SideMenuTab = .chats
    @State private var newMemoryText: String = ""
    @State private var editingMemoryId: String? = nil
    @State private var editingMemoryText: String = ""

    // Agent & Workflow Maker State (Build 4 — Answer 21)
    @State private var isAddingAgent: Bool = false
    @State private var newAgentName: String = ""
    @State private var newAgentSummary: String = ""
    @State private var newAgentPrompt: String = ""

    @State private var isAddingWorkflow: Bool = false
    @State private var workflowMakerDescription: String = ""
    @State private var newWorkflowName: String = ""
    @State private var selectedWorkflowSteps: [String] = ["Planner", "Coder", "Code checker"]

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
                        Text("New chat")
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

    // MARK: - Chats in Groups

    private var chatsListSection: some View {
        let filtered = state.chats.filter {
            searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText)
        }
        return VStack(alignment: .leading, spacing: 10) {
            if !state.groups.isEmpty {
                ForEach(state.groups) { grp in
                    let groupChats = filtered.filter { $0.groupId == grp.id }
                    if !groupChats.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .font(.caption2)
                                    .foregroundStyle(accentColor)
                                Text(grp.name.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    state.createNewChat(inGroupId: grp.id)
                                } label: {
                                    Image(systemName: "plus.circle")
                                        .font(.caption)
                                        .foregroundStyle(accentColor)
                                }
                            }
                            .padding(.horizontal, 4)

                            ForEach(groupChats) { chat in
                                chatRowButton(chat: chat)
                            }
                        }
                    }
                }
            }

            let ungrouped = filtered.filter { $0.groupId == nil }
            ForEach(ungrouped) { chat in
                chatRowButton(chat: chat)
            }
        }
    }

    private func chatRowButton(chat: ChatThread) -> some View {
        HStack(spacing: 6) {
            Button {
                state.switchActiveChat(to: chat.id)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(chat.title)
                        .font(.subheadline.weight(state.activeChatId == chat.id ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(chat.repoFullName ?? "No repo")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "$%.4f", chat.totalCostUSD))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if state.chats.count > 1 {
                Button {
                    state.deleteChat(chat.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
            }
        }
        .padding(10)
        .background(state.activeChatId == chat.id ? accentColor.opacity(0.16) : Color(UIColor.tertiarySystemBackground).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Agents Section (Tappable + Custom Agent Creator — Build 4)

    private var agentsListSection: some View {
        let allAgents = state.customAgents + AgentPreset.kiroBuiltIns
        let filtered = allAgents.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) || $0.summary.localizedCaseInsensitiveContains(searchText)
        }
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                isAddingAgent.toggle()
            } label: {
                Label(isAddingAgent ? "Close Agent Creator" : "Make Your Own Agent", systemImage: "plus.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
            }

            if isAddingAgent {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Agent name (e.g. Game Tester)", text: $newAgentName)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                    TextField("What it does in plain English", text: $newAgentSummary)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                    TextField("Instructions for the AI", text: $newAgentPrompt)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                    Button("Save Agent") {
                        let name = newAgentName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        let ag = AgentPreset(
                            id: "custom-\(UUID().uuidString.prefix(6))",
                            name: name,
                            summary: newAgentSummary.isEmpty ? "Custom agent" : newAgentSummary,
                            rolePrompt: newAgentPrompt.isEmpty ? newAgentSummary : newAgentPrompt,
                            isBuiltIn: false
                        )
                        state.customAgents.insert(ag, at: 0)
                        state.saveWorkspaceLocallyAndSync()
                        newAgentName = ""
                        newAgentSummary = ""
                        newAgentPrompt = ""
                        isAddingAgent = false
                    }
                    .font(.caption.bold())
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
                }
                .padding(10)
                .background(Color(UIColor.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            ForEach(filtered) { agent in
                let isSelected = state.activeChat?.activeAgentId == agent.id
                Button {
                    if let idx = state.chats.firstIndex(where: { $0.id == state.activeChatId }) {
                        state.chats[idx].activeAgentId = (isSelected ? nil : agent.id)
                        state.chats[idx].activeWorkflowId = nil
                        state.saveWorkspaceLocallyAndSync()
                    }
                    state.isSideMenuOpen = false
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(agent.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(isSelected ? "Active ✓" : "Use")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(isSelected ? accentColor : .secondary)
                        }
                        Text(agent.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isSelected ? accentColor.opacity(0.18) : Color(UIColor.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    // MARK: - Workflows Section (Describe in Words OR Tap Steps Together — Answer 20 & 21)

    private var workflowsListSection: some View {
        let allWorkflows = state.customWorkflows + WorkflowPreset.kiroBuiltIns
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                isAddingWorkflow.toggle()
            } label: {
                Label(isAddingWorkflow ? "Close Workflow Maker" : "Make a Workflow (Words or Steps)", systemImage: "plus.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
            }

            if isAddingWorkflow {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Describe in words (Workflow maker):")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("e.g. Check my code with two AIs then build .ipa", text: $workflowMakerDescription)
                            .font(.caption)
                            .textFieldStyle(.roundedBorder)
                        Button("Draft") {
                            let desc = workflowMakerDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !desc.isEmpty else { return }
                            newWorkflowName = String(desc.prefix(28))
                            var steps: [String] = []
                            let lower = desc.lowercased()
                            if lower.contains("plan") || lower.contains("spec") { steps.append("Planner") }
                            if lower.contains("design") || lower.contains("ui") { steps.append("Designer") }
                            if lower.contains("code") || lower.contains("fix") || lower.contains("build") { steps.append("Coder") }
                            if lower.contains("two") || lower.contains("second") {
                                steps.append(contentsOf: ["Code checker", "Second opinion", "Review combiner"])
                            } else {
                                steps.append("Code checker")
                            }
                            if lower.contains("ipa") || lower.contains("build") { steps.append("Builder") }
                            if lower.contains("pr") || lower.contains("branch") { steps.append("Request sender") }
                            selectedWorkflowSteps = steps.isEmpty ? ["Planner", "Coder", "Code checker"] : steps
                        }
                        .font(.caption.bold())
                    }

                    Text("Or tap steps together yourself:")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("Workflow name", text: $newWorkflowName)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(AgentPreset.kiroBuiltIns) { ag in
                                Button {
                                    selectedWorkflowSteps.append(ag.name)
                                } label: {
                                    Text("+ \(ag.name)")
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(accentColor.opacity(0.16))
                                        .foregroundStyle(accentColor)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    if !selectedWorkflowSteps.isEmpty {
                        HStack {
                            Text(selectedWorkflowSteps.joined(separator: " → "))
                                .font(.caption2)
                                .foregroundStyle(accentColor)
                            Spacer()
                            Button("Clear") {
                                selectedWorkflowSteps.removeAll()
                            }
                            .font(.caption2)
                        }
                    }

                    Button("OK, Save Workflow") {
                        let title = newWorkflowName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty, !selectedWorkflowSteps.isEmpty else { return }
                        let wf = WorkflowPreset(
                            id: "custom-wf-\(UUID().uuidString.prefix(6))",
                            name: title,
                            summary: workflowMakerDescription.isEmpty ? "Custom multi-step workflow" : workflowMakerDescription,
                            steps: selectedWorkflowSteps,
                            isBuiltIn: false
                        )
                        state.customWorkflows.insert(wf, at: 0)
                        state.saveWorkspaceLocallyAndSync()
                        newWorkflowName = ""
                        workflowMakerDescription = ""
                        isAddingWorkflow = false
                    }
                    .font(.caption.bold())
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
                }
                .padding(10)
                .background(Color(UIColor.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            ForEach(allWorkflows) { wf in
                let isSelected = state.activeChat?.activeWorkflowId == wf.id
                Button {
                    if wf.id == "build-ipa" && state.selectedRepo != nil {
                        state.isSideMenuOpen = false
                        state.isBuildsSheetPresented = true
                    } else {
                        if let idx = state.chats.firstIndex(where: { $0.id == state.activeChatId }) {
                            state.chats[idx].activeWorkflowId = wf.id
                            state.chats[idx].activeAgentId = nil
                        }
                        state.isSideMenuOpen = false
                        Task {
                            await state.sendCurrentMessage(overrideText: "Run workflow '\(wf.name)': \(wf.steps.joined(separator: " → "))")
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(wf.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("Run →")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(accentColor)
                        }
                        Text(wf.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                        Text(wf.steps.joined(separator: " → "))
                            .font(.caption2)
                            .foregroundStyle(accentColor)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isSelected ? accentColor.opacity(0.18) : Color(UIColor.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    // MARK: - Memories Section (Add, Edit, Delete, Per-item & Master Switch — Answer 24)

    private var memoriesListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Use memories in new chats", isOn: $state.settings.memoriesMasterSwitch)
                .font(.caption.weight(.semibold))
                .onChange(of: state.settings.memoriesMasterSwitch) { _, _ in
                    state.saveWorkspaceLocallyAndSync()
                }

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
                Text("Memories start empty. Tap ★ on any chat message, add one above, or let the AI save preferences automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($state.memories) { $mem in
                    VStack(alignment: .leading, spacing: 6) {
                        if editingMemoryId == mem.id {
                            HStack {
                                TextField("Edit memory", text: $editingMemoryText)
                                    .font(.caption)
                                    .textFieldStyle(.roundedBorder)
                                Button("Save") {
                                    mem.text = editingMemoryText
                                    mem.updatedAt = Date()
                                    editingMemoryId = nil
                                    state.saveWorkspaceLocallyAndSync()
                                }
                                .font(.caption.bold())
                            }
                        } else {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(mem.text)
                                        .font(.caption)
                                    HStack(spacing: 8) {
                                        Text(mem.source.rawValue)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Button("Edit") {
                                            editingMemoryId = mem.id
                                            editingMemoryText = mem.text
                                        }
                                        .font(.caption2)
                                        Button("Delete", role: .destructive) {
                                            let idToDelete = mem.id
                                            state.memories.removeAll(where: { $0.id == idToDelete })
                                            state.saveWorkspaceLocallyAndSync()
                                        }
                                        .font(.caption2)
                                    }
                                }
                                Spacer()
                                Toggle("", isOn: $mem.isEnabled)
                                    .labelsHidden()
                                    .onChange(of: mem.isEnabled) { _, _ in
                                        state.saveWorkspaceLocallyAndSync()
                                    }
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}

// MARK: - Repo Files Browser & In-App Code Editor Sheet (Build 2 — Read, Edit, Create, Delete with Confirmation, Save PR)

public struct RepoFilesSheet: View {
    @ObservedObject public var state: AppState
    public let accentColor: Color
    @Environment(\.dismiss) private var dismiss
    @State private var filterText: String = ""
    @State private var selectedFilePath: String? = nil
    @State private var selectedFileContent: String = ""
    @State private var isEditingFile: Bool = false
    @State private var isCreatingNewFile: Bool = false
    @State private var newFilePath: String = ""
    @State private var newFileContent: String = ""
    @State private var commitMessageInput: String = ""
    @State private var isLoadingFile: Bool = false
    @State private var isSavingCommit: Bool = false
    @State private var showDeleteConfirm: Bool = false

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isCreatingNewFile {
                    newFileEditorView
                } else if let filePath = selectedFilePath {
                    fileDetailAndEditorView(filePath: filePath)
                } else {
                    fileListView
                }
            }
            .navigationTitle(state.selectedRepo?.fullName ?? "Repository Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if state.selectedRepo != nil && selectedFilePath == nil && !isCreatingNewFile {
                        Button {
                            newFilePath = ""
                            newFileContent = ""
                            commitMessageInput = "Add new file via MAIPA-G"
                            isCreatingNewFile = true
                        } label: {
                            Label("New File", systemImage: "doc.badge.plus")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if let repo = state.selectedRepo, state.currentRepoTree.isEmpty {
                    await state.refreshBranchesAndTree(for: repo.fullName, branch: state.selectedBranchName)
                }
            }
            .alert("Delete \(selectedFilePath ?? "file")?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete File", role: .destructive) {
                    guard let path = selectedFilePath else { return }
                    Task {
                        await performDeleteFile(path: path)
                    }
                }
            } message: {
                Text("MAIPA-G always asks before deleting a file. This will save a delete commit/PR on GitHub.")
            }
        }
    }

    private var fileListView: some View {
        List {
            if state.selectedRepo == nil {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No repository selected")
                            .font(.subheadline.weight(.semibold))
                        Text("Pick a GitHub repository first to browse, search, or edit its files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Pick a Repository") {
                            dismiss()
                            if state.githubToken == nil {
                                state.isGitHubSignInPresented = true
                            } else {
                                state.isRepoPickerPresented = true
                            }
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .padding(.vertical, 6)
                }
            } else {
                let blobs = state.currentRepoTree.filter {
                    $0.type == "blob" && (filterText.isEmpty || $0.path.localizedCaseInsensitiveContains(filterText))
                }
                if blobs.isEmpty {
                    Text("No matching files in \(state.selectedRepo?.fullName ?? "repository").")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(blobs) { item in
                        Button {
                            Task {
                                await openFile(item.path)
                            }
                        } label: {
                            HStack {
                                Image(systemName: item.path.hasSuffix(".swift") ? "swift" : "doc.text")
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
        }
        .searchable(text: $filterText, prompt: "Filter files in \(state.selectedRepo?.name ?? "repo")")
    }

    private func fileDetailAndEditorView(filePath: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    selectedFilePath = nil
                    isEditingFile = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Files")
                    }
                    .font(.subheadline.weight(.semibold))
                }

                Spacer()

                Text(filePath)
                    .font(.caption.monospaced())
                    .lineLimit(1)

                Spacer()

                Menu {
                    Button {
                        isEditingFile.toggle()
                        commitMessageInput = "Update \(filePath)"
                    } label: {
                        Label(isEditingFile ? "Cancel Edit" : "Edit File", systemImage: "pencil")
                    }

                    Button {
                        let att = ChatAttachmentItem(
                            name: filePath,
                            kind: .repoFile,
                            mimeType: "text/plain",
                            textPreview: String(selectedFileContent.prefix(3000)),
                            sizeBytes: selectedFileContent.utf8.count
                        )
                        state.pendingAttachments.append(att)
                        dismiss()
                    } label: {
                        Label("Attach to Chat", systemImage: "paperclip")
                    }

                    if filePath.hasSuffix(".html") || filePath.hasSuffix(".md") {
                        Button {
                            state.livePreviewTitle = filePath
                            state.livePreviewHTML = selectedFileContent
                            dismiss()
                            state.isLivePreviewPresented = true
                        } label: {
                            Label("Open in Live Preview", systemImage: "play.display")
                        }
                    }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete File…", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if isLoadingFile {
                ProgressView("Reading \(filePath)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isEditingFile {
                VStack(spacing: 8) {
                    TextEditor(text: $selectedFileContent)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(8)

                    Divider()

                    HStack {
                        TextField("Commit message", text: $commitMessageInput)
                            .font(.caption)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            Task {
                                await saveEditedFile(path: filePath)
                            }
                        } label: {
                            Text(isSavingCommit ? "Saving…" : "Save to GitHub")
                                .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accentColor)
                        .disabled(isSavingCommit)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            } else {
                ScrollView([.vertical, .horizontal]) {
                    Text(selectedFileContent)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(14)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var newFileEditorView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Cancel") {
                    isCreatingNewFile = false
                }
                Spacer()
                Text("New Repository File")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(isSavingCommit ? "Saving…" : "Save") {
                    Task {
                        await saveCreatedFile()
                    }
                }
                .fontWeight(.bold)
                .disabled(newFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingCommit)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            TextField("File path (e.g. Sources/NewFeature.swift)", text: $newFilePath)
                .font(.caption.monospaced())
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)

            TextField("Commit summary", text: $commitMessageInput)
                .font(.caption)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)

            Divider()

            TextEditor(text: $newFileContent)
                .font(.system(size: 12, design: .monospaced))
                .padding(8)
        }
    }

    private func openFile(_ path: String) async {
        guard let repo = state.selectedRepo else { return }
        selectedFilePath = path
        isEditingFile = false
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

    private func saveEditedFile(path: String) async {
        isSavingCommit = true
        defer { isSavingCommit = false }
        let op = RepoFileEditOperation(path: path, kind: .update, content: selectedFileContent)
        let msg = commitMessageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Update \(path)" : commitMessageInput
        do {
            _ = try await state.saveRepoFileChanges(operations: [op], commitMessage: msg)
            isEditingFile = false
            dismiss()
        } catch {
            state.statusBannerText = "Save failed: \(error.localizedDescription)"
        }
    }

    private func saveCreatedFile() async {
        isSavingCommit = true
        defer { isSavingCommit = false }
        let path = newFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let op = RepoFileEditOperation(path: path, kind: .create, content: newFileContent)
        let msg = commitMessageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Create \(path)" : commitMessageInput
        do {
            _ = try await state.saveRepoFileChanges(operations: [op], commitMessage: msg)
            isCreatingNewFile = false
            dismiss()
        } catch {
            state.statusBannerText = "Create file failed: \(error.localizedDescription)"
        }
    }

    private func performDeleteFile(path: String) async {
        isSavingCommit = true
        defer { isSavingCommit = false }
        let op = RepoFileEditOperation(path: path, kind: .delete, content: nil)
        do {
            _ = try await state.saveRepoFileChanges(operations: [op], commitMessage: "Delete \(path)")
            selectedFilePath = nil
            dismiss()
        } catch {
            state.statusBannerText = "Delete failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Build 3: Builds & GitHub Actions Sheet (Watch runs, Start build when asked, Check .ipa)

public struct BuildsAndActionsSheet: View {
    @ObservedObject public var state: AppState
    public let accentColor: Color
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            List {
                if let repo = state.selectedRepo {
                    Section("Start a Build (\(repo.fullName))") {
                        Button {
                            Task {
                                await state.triggerRepoBuildOnGitHub()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                    .foregroundStyle(accentColor)
                                Text("Start iOS .ipa Build Now (\(state.selectedBranchName))")
                                    .fontWeight(.semibold)
                            }
                        }
                    }

                    Section("Recent GitHub Actions Runs") {
                        if state.workflowRuns.isEmpty {
                            Text("No recent workflow runs found.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(state.workflowRuns) { run in
                                HStack {
                                    Image(systemName: run.status == "completed" ? (run.conclusion == "success" ? "checkmark.circle.fill" : "xmark.circle.fill") : "clock.arrow.circlepath")
                                        .foregroundStyle(run.status == "completed" ? (run.conclusion == "success" ? .green : .red) : .orange)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(run.name) #\(run.runNumber)")
                                            .font(.subheadline.weight(.semibold))
                                        Text("\(run.headBranch) · \(String(run.headSha.prefix(7))) · \(run.status)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let url = URL(string: run.htmlURL) {
                                        Link("Logs", destination: url)
                                            .font(.caption.weight(.semibold))
                                    }
                                }
                            }
                        }
                    }
                }

                if let release = state.latestBuildRelease {
                    Section("Latest Verified .ipa Release") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(release.title)
                                .font(.subheadline.weight(.semibold))
                            Text("Tag: \(release.tagName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let url = URL(string: release.ipaDownloadURL) {
                                Link("Download MAIPA-G.ipa", destination: url)
                                    .font(.subheadline.weight(.bold))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Builds & Cloud Jobs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh") {
                        Task {
                            await state.refreshWorkflowRuns()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await state.refreshWorkflowRuns()
            }
        }
    }
}

// MARK: - Repo Picker, Branch Picker, Group Picker, and AI Model Picker Sheets

public struct RepoPickerSheet: View {
    @ObservedObject public var state: AppState
    public let accentColor: Color
    @Environment(\.dismiss) private var dismiss
    @State private var search: String = ""
    @State private var isCreatingRepo: Bool = false
    @State private var newRepoName: String = ""
    @State private var newRepoDesc: String = ""
    @State private var newRepoPrivate: Bool = false

    public var body: some View {
        NavigationStack {
            List {
                if state.selectedRepo != nil {
                    Section {
                        Button(role: .destructive) {
                            state.clearSelectedRepo()
                            dismiss()
                        } label: {
                            Label("Work without a repository (Disconnect)", systemImage: "xmark.circle")
                        }
                    }
                }

                Section {
                    Button {
                        isCreatingRepo.toggle()
                    } label: {
                        Label(isCreatingRepo ? "Close New Repo Form" : "Create a New GitHub Repository", systemImage: "plus.rectangle.on.folder")
                            .foregroundStyle(accentColor)
                    }

                    if isCreatingRepo {
                        TextField("Repository name", text: $newRepoName)
                        TextField("Description (optional)", text: $newRepoDesc)
                        Toggle("Private repository", isOn: $newRepoPrivate)
                        Button("Create & Select Repository") {
                            guard let token = state.githubToken, !newRepoName.isEmpty else { return }
                            Task {
                                if let created = try? await state.githubService.createRepository(
                                    name: newRepoName,
                                    description: newRepoDesc,
                                    isPrivate: newRepoPrivate,
                                    token: token
                                ) {
                                    state.availableRepos.insert(created, at: 0)
                                    await state.selectRepository(created)
                                    dismiss()
                                }
                            }
                        }
                        .fontWeight(.bold)
                    }
                }

                Section("Your GitHub Repositories") {
                    let filtered = state.availableRepos.filter {
                        search.isEmpty || $0.fullName.localizedCaseInsensitiveContains(search)
                    }
                    if filtered.isEmpty {
                        Text(state.githubToken == nil ? "Tap Connect GitHub first to load your repositories." : "No repositories found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filtered) { repo in
                            Button {
                                Task {
                                    await state.selectRepository(repo)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(repo.fullName)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            if repo.isPrivate {
                                                Text("Private")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(Color.secondary.opacity(0.2))
                                                    .clipShape(Capsule())
                                            }
                                        }
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
            .task {
                if state.availableRepos.isEmpty && state.githubToken != nil {
                    await state.refreshRepositories()
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

public struct GroupPickerSheet: View {
    @ObservedObject public var state: AppState
    public let accentColor: Color
    @Environment(\.dismiss) private var dismiss
    @State private var newGroupName: String = ""

    public var body: some View {
        NavigationStack {
            Form {
                Section("Create a Group") {
                    HStack {
                        TextField("Group name (e.g. Games, Daily)", text: $newGroupName)
                        Button("Create") {
                            let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            let grp = ChatGroup(name: trimmed)
                            state.groups.append(grp)
                            if let idx = state.chats.firstIndex(where: { $0.id == state.activeChatId }) {
                                state.chats[idx].groupId = grp.id
                            }
                            state.saveWorkspaceLocallyAndSync()
                            newGroupName = ""
                            dismiss()
                        }
                        .fontWeight(.bold)
                    }
                }

                Section("Assign Current Chat to Group") {
                    Button {
                        if let idx = state.chats.firstIndex(where: { $0.id == state.activeChatId }) {
                            state.chats[idx].groupId = nil
                            state.saveWorkspaceLocallyAndSync()
                        }
                        dismiss()
                    } label: {
                        HStack {
                            Text("No Group")
                                .foregroundStyle(.primary)
                            Spacer()
                            if state.activeChat?.groupId == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(accentColor)
                            }
                        }
                    }

                    ForEach(state.groups) { grp in
                        Button {
                            if let idx = state.chats.firstIndex(where: { $0.id == state.activeChatId }) {
                                state.chats[idx].groupId = grp.id
                                state.saveWorkspaceLocallyAndSync()
                            }
                            dismiss()
                        } label: {
                            HStack {
                                Label(grp.name, systemImage: "folder.fill")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if state.activeChat?.groupId == grp.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chat Groups")
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

// MARK: - GitHub, OpenRouter, Connections (40,000+ Official MCP Registry + Hide Unused), Live Preview & Settings

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
    @State private var showHiddenConnectors: Bool = false
    @State private var isAddingCustomServer: Bool = false
    @State private var customName: String = ""
    @State private var customURL: String = ""
    @State private var customSummary: String = ""

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Show hidden connectors (\(state.settings.hiddenConnectorIds.count) hidden)", isOn: $showHiddenConnectors)
                        .font(.caption)
                    Button {
                        isAddingCustomServer.toggle()
                    } label: {
                        Label(isAddingCustomServer ? "Close Custom Server Form" : "Add Any Custom MCP Server URL", systemImage: "plus.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accentColor)
                    }

                    if isAddingCustomServer {
                        TextField("Connector name", text: $customName)
                        TextField("Server URL (https://... or stdio)", text: $customURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                        TextField("Summary (optional)", text: $customSummary)
                        Button("Add & Connect") {
                            guard !customName.isEmpty, !customURL.isEmpty else { return }
                            state.addCustomConnector(name: customName, serverURL: customURL, summary: customSummary)
                            customName = ""
                            customURL = ""
                            customSummary = ""
                            isAddingCustomServer = false
                        }
                        .fontWeight(.bold)
                    }
                }

                if !state.customConnectors.isEmpty {
                    Section("Your Custom Connectors") {
                        ForEach(state.customConnectors) { item in
                            connectorRow(item: item, isCustom: true)
                        }
                    }
                }

                ForEach(MCPConnectorCategory.allCases.filter { $0 != .officialRegistry }, id: \.self) { category in
                    let items = state.connectors.filter { item in
                        guard item.category == category else { return false }
                        if !showHiddenConnectors && state.isConnectorHidden(item.id) { return false }
                        return query.isEmpty
                            || item.name.localizedCaseInsensitiveContains(query)
                            || item.summary.localizedCaseInsensitiveContains(query)
                    }
                    if !items.isEmpty {
                        Section(category.rawValue) {
                            ForEach(items) { item in
                                connectorRow(item: item, isCustom: false)
                            }
                        }
                    }
                }

                Section("Official MCP Registry (40,000+ Live Servers)") {
                    Button {
                        Task {
                            await state.searchMCPRegistry(query: query)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundStyle(accentColor)
                            Text(state.isSearchingRegistry ? "Searching MCP Registry…" : (query.isEmpty ? "Load Popular Servers from Official MCP Registry" : "Search Official Registry for \"\(query)\""))
                                .font(.caption.weight(.semibold))
                        }
                    }

                    ForEach(state.registrySearchResults) { item in
                        connectorRow(item: item, isCustom: false)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search 40,000+ MCP connectors…")
            .onSubmit(of: .search) {
                Task {
                    await state.searchMCPRegistry(query: query)
                }
            }
            .navigationTitle("Connections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func connectorRow(item: MCPConnectorItem, isCustom: Bool) -> some View {
        let isHidden = state.isConnectorHidden(item.id)
        return HStack(spacing: 10) {
            Image(systemName: item.iconName)
                .foregroundStyle(isHidden ? .secondary : accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isHidden ? .secondary : .primary)
                    if isHidden {
                        Text("Hidden")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                Text(item.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Hide / Unhide button so the user can hide any connector they don't use
            if item.id != "github" {
                Button {
                    state.toggleHideConnector(item.id)
                } label: {
                    Image(systemName: isHidden ? "eye" : "eye.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }

            Button {
                if item.id == "github" {
                    dismiss()
                    state.isGitHubSignInPresented = true
                } else if isCustom, let idx = state.customConnectors.firstIndex(where: { $0.id == item.id }) {
                    state.customConnectors[idx].isConnected.toggle()
                    state.saveWorkspaceLocallyAndSync()
                } else if let idx = state.connectors.firstIndex(where: { $0.id == item.id }) {
                    state.connectors[idx].isConnected.toggle()
                    state.saveWorkspaceLocallyAndSync()
                } else {
                    var copy = item
                    copy.isConnected = true
                    state.customConnectors.append(copy)
                    state.saveWorkspaceLocallyAndSync()
                }
            } label: {
                Text(item.isConnected ? "Connected ✓" : "Connect")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(item.isConnected ? accentColor.opacity(0.18) : Color(UIColor.tertiarySystemBackground))
                    .foregroundStyle(item.isConnected ? accentColor : .primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Build 5: Live Web Project Preview Sheet (Answer 30)

public struct LiveWebPreviewSheet: View {
    @ObservedObject public var state: AppState
    public let accentColor: Color
    @Environment(\.dismiss) private var dismiss
    @State private var urlInput: String = ""

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("https://...", text: $urlInput)
                        .font(.caption)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            state.livePreviewHTML = nil
                            state.livePreviewURLString = urlInput
                        }
                    Button("Go") {
                        state.livePreviewHTML = nil
                        state.livePreviewURLString = urlInput
                    }
                    .font(.caption.bold())
                }
                .padding(10)
                .background(Color(UIColor.secondarySystemBackground))

                Divider()

                EmbeddedWebView(
                    htmlString: state.livePreviewHTML,
                    urlString: state.livePreviewURLString
                )
            }
            .navigationTitle(state.livePreviewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                urlInput = state.livePreviewURLString
            }
        }
    }
}

private struct EmbeddedWebView: UIViewRepresentable {
    let htmlString: String?
    let urlString: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if let html = htmlString, !html.isEmpty {
            webView.loadHTMLString(html, baseURL: nil)
        } else if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
    }
}

// MARK: - Settings Sheet (Accounts, Cost Limit, Colours, Effects, Per-Repo Save Policy, Technical Details)

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

                Section("Money & Cost Control") {
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

                Section("How Each Repo Saves Changes") {
                    if let repo = state.selectedRepo {
                        let isContinuum = repo.fullName.lowercased().contains("continuum")
                        if isContinuum {
                            HStack {
                                Text(repo.fullName)
                                Spacer()
                                Text("Saves straight to master (repo rule)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Toggle(
                                "Save straight to branch in \(repo.name) (skip PR)",
                                isOn: Binding(
                                    get: { state.settings.perRepoSaveStraightToBranch[repo.fullName] ?? false },
                                    set: { newVal in
                                        state.settings.perRepoSaveStraightToBranch[repo.fullName] = newVal
                                        state.saveWorkspaceLocallyAndSync()
                                    }
                                )
                            )
                        }
                    } else {
                        Text("By default, changes on main open a clean side branch and Pull Request with 'Add it' and 'Throw away' buttons. Pick a repo to customize its save mode.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Home Screen & Connectors") {
                    Toggle("Show unconnected connectors on Home", isOn: $state.settings.showUnconnectedConnectorsOnHome)
                    Button("Manage or Hide Connectors (\(state.settings.hiddenConnectorIds.count) hidden)") {
                        dismiss()
                        state.isConnectionsSheetPresented = true
                    }
                }

                Section("Appearance & Colours") {
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

                Section("Effects & Mascot Switches") {
                    Toggle("Show mascot on Home screen", isOn: $state.settings.showMascotOnHome)
                    Toggle("Gentle mascot floating effect", isOn: $state.settings.mascotMotionEnabled)
                    Toggle("Smooth chat message transitions", isOn: $state.settings.smoothChatTransitionsEnabled)
                    Toggle("Tool step expand animations", isOn: $state.settings.toolStepAnimationsEnabled)
                }

                Section("Workflows & Notifications") {
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

                Section("Technical Details") {
                    HStack {
                        Text("Bundle ID")
                        Spacer()
                        Text(Bundle.main.bundleIdentifier ?? "dev.maipag.app")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Data Sync Repo")
                        Spacer()
                        Text(state.githubUsername != nil ? "\(state.githubUsername!)/MAIPA-G-data (Private)" : "Local JSON until GitHub connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Git Author")
                        Spacer()
                        Text("MAIPA-G")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
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
