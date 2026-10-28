import Foundation

// MARK: - AI Models & Thinking Levels

public enum ThinkingLevel: String, Codable, CaseIterable, Sendable {
    case low = "low"
    case medium = "medium"
    case high = "high"

    public var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

public enum TaskCostTier: String, Codable, CaseIterable, Sendable {
    case low = "low"
    case medium = "medium"
    case high = "high"
}

public struct AIModelOption: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let provider: String
    public let isFree: Bool
    public let supportsThinking: Bool
    public let inputPricePerMillion: Double
    public let outputPricePerMillion: Double
    public let summary: String

    public init(
        id: String,
        name: String,
        provider: String,
        isFree: Bool,
        supportsThinking: Bool,
        inputPricePerMillion: Double,
        outputPricePerMillion: Double,
        summary: String
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.isFree = isFree
        self.supportsThinking = supportsThinking
        self.inputPricePerMillion = inputPricePerMillion
        self.outputPricePerMillion = outputPricePerMillion
        self.summary = summary
    }

    public static let defaultCatalog: [AIModelOption] = [
        AIModelOption(
            id: "openrouter/auto",
            name: "Auto",
            provider: "MAIPA-G",
            isFree: false,
            supportsThinking: true,
            inputPricePerMillion: 0.0,
            outputPricePerMillion: 0.0,
            summary: "Picks the right AI for each job: cheap or free for small things, smarter ones for hard work. Uses only free AIs when your balance is $0."
        ),
        AIModelOption(
            id: "openrouter/free",
            name: "Free AIs (Auto)",
            provider: "OpenRouter",
            isFree: true,
            supportsThinking: true,
            inputPricePerMillion: 0.0,
            outputPricePerMillion: 0.0,
            summary: "Always $0. Picks the best free model that supports the tools your chat needs."
        ),
        AIModelOption(
            id: "apple/foundation",
            name: "iPhone AI (On-Device)",
            provider: "Apple",
            isFree: true,
            supportsThinking: false,
            inputPricePerMillion: 0.0,
            outputPricePerMillion: 0.0,
            summary: "Runs straight on your iPhone at $0. Great for chat titles and quick notes."
        ),
        AIModelOption(
            id: "anthropic/claude-opus-4.1",
            name: "Claude Opus 5.5",
            provider: "Anthropic",
            isFree: false,
            supportsThinking: true,
            inputPricePerMillion: 4.0,
            outputPricePerMillion: 20.0,
            summary: "Deep planning, hard debugging, and thorough code checks ($4 / $20 per 1M tokens)."
        ),
        AIModelOption(
            id: "anthropic/claude-sonnet-4",
            name: "Claude Sonnet 5.5",
            provider: "Anthropic",
            isFree: false,
            supportsThinking: true,
            inputPricePerMillion: 2.0,
            outputPricePerMillion: 10.0,
            summary: "Fast everyday coding and repo work ($2 / $10 per 1M tokens)."
        ),
        AIModelOption(
            id: "anthropic/claude-3.5-haiku",
            name: "Claude Haiku 5.5",
            provider: "Anthropic",
            isFree: false,
            supportsThinking: false,
            inputPricePerMillion: 0.10,
            outputPricePerMillion: 0.50,
            summary: "Quick searches and light tasks ($0.10 / $0.50 per 1M tokens)."
        ),
        AIModelOption(
            id: "deepseek/deepseek-r1:free",
            name: "DeepSeek R1 (Free)",
            provider: "DeepSeek",
            isFree: true,
            supportsThinking: true,
            inputPricePerMillion: 0.0,
            outputPricePerMillion: 0.0,
            summary: "Free reasoning model with step-by-step thinking."
        ),
        AIModelOption(
            id: "google/gemini-2.5-pro-exp-03-25:free",
            name: "Gemini Pro (Free)",
            provider: "Google",
            isFree: true,
            supportsThinking: true,
            inputPricePerMillion: 0.0,
            outputPricePerMillion: 0.0,
            summary: "Large context window for reading whole repositories at $0."
        )
    ]
}

// MARK: - GitHub Models

public struct GitHubRepo: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let fullName: String
    public let ownerLogin: String
    public let defaultBranch: String
    public let isPrivate: Bool
    public let description: String?
    public let updatedAt: String?

    public init(
        id: Int,
        name: String,
        fullName: String,
        ownerLogin: String,
        defaultBranch: String,
        isPrivate: Bool,
        description: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.ownerLogin = ownerLogin
        self.defaultBranch = defaultBranch
        self.isPrivate = isPrivate
        self.description = description
        self.updatedAt = updatedAt
    }
}

public struct GitHubBranch: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let sha: String

    public init(name: String, sha: String) {
        self.name = name
        self.sha = sha
    }
}

public struct GitHubTreeItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let type: String // "blob" or "tree"
    public let size: Int?
    public let sha: String

    public var isDirectory: Bool {
        type == "tree"
    }

    public var fileName: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    public init(path: String, type: String, size: Int?, sha: String) {
        self.path = path
        self.type = type
        self.size = size
        self.sha = sha
    }
}

// MARK: - Chat & Tool Call Models

public enum ToolCallStatus: String, Codable, Sendable {
    case running = "running"
    case completed = "completed"
    case failed = "failed"
}

public struct ToolCallItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let toolName: String
    public var summaryLine: String
    public var inputSummary: String
    public var outputDetail: String
    public var status: ToolCallStatus
    public var startedAt: Date
    public var finishedAt: Date?

    public init(
        id: String = UUID().uuidString,
        toolName: String,
        summaryLine: String,
        inputSummary: String,
        outputDetail: String = "",
        status: ToolCallStatus = .running,
        startedAt: Date = Date(),
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.summaryLine = summaryLine
        self.inputSummary = inputSummary
        self.outputDetail = outputDetail
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

public struct NumberedQuestionItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let number: Int
    public let prompt: String
    public let options: [String]
    public var selectedOption: String?

    public init(
        id: String = UUID().uuidString,
        number: Int,
        prompt: String,
        options: [String],
        selectedOption: String? = nil
    ) {
        self.id = id
        self.number = number
        self.prompt = prompt
        self.options = options
        self.selectedOption = selectedOption
    }
}

public enum MessageRole: String, Codable, Sendable {
    case user = "user"
    case assistant = "assistant"
    case system = "system"
}

public struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let role: MessageRole
    public var text: String
    public let createdAt: Date
    public var modelUsed: String?
    public var costUSD: Double
    public var toolCalls: [ToolCallItem]
    public var questions: [NumberedQuestionItem]
    public var isStarredAsMemory: Bool
    public var stopAndAskTriggered: Bool

    public init(
        id: String = UUID().uuidString,
        role: MessageRole,
        text: String,
        createdAt: Date = Date(),
        modelUsed: String? = nil,
        costUSD: Double = 0.0,
        toolCalls: [ToolCallItem] = [],
        questions: [NumberedQuestionItem] = [],
        isStarredAsMemory: Bool = false,
        stopAndAskTriggered: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.modelUsed = modelUsed
        self.costUSD = costUSD
        self.toolCalls = toolCalls
        self.questions = questions
        self.isStarredAsMemory = isStarredAsMemory
        self.stopAndAskTriggered = stopAndAskTriggered
    }
}

public struct ChatGroup: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    public let createdAt: Date

    public init(id: String = UUID().uuidString, name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

public struct ChatThread: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var groupId: String?
    public var repoFullName: String?
    public var branchName: String?
    public var selectedModelId: String
    public var thinkingLevel: ThinkingLevel
    public var isAutonomous: Bool
    public var webSearchEnabled: Bool
    public var specModeEnabled: Bool
    public var messages: [ChatMessage]
    public var totalCostUSD: Double
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String = "New chat",
        groupId: String? = nil,
        repoFullName: String? = nil,
        branchName: String? = nil,
        selectedModelId: String = "openrouter/auto",
        thinkingLevel: ThinkingLevel = .medium,
        isAutonomous: Bool = false,
        webSearchEnabled: Bool = false,
        specModeEnabled: Bool = false,
        messages: [ChatMessage] = [],
        totalCostUSD: Double = 0.0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.groupId = groupId
        self.repoFullName = repoFullName
        self.branchName = branchName
        self.selectedModelId = selectedModelId
        self.thinkingLevel = thinkingLevel
        self.isAutonomous = isAutonomous
        self.webSearchEnabled = webSearchEnabled
        self.specModeEnabled = specModeEnabled
        self.messages = messages
        self.totalCostUSD = totalCostUSD
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Memories, Agents, Workflows, and Settings

public enum MemorySource: String, Codable, Sendable {
    case star = "★ from chat"
    case ai = "Saved by AI"
    case user = "Added by you"
}

public struct MemoryItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var text: String
    public var isEnabled: Bool
    public let source: MemorySource
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        text: String,
        isEnabled: Bool = true,
        source: MemorySource = .user,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.isEnabled = isEnabled
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct AgentPreset: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var summary: String
    public var rolePrompt: String
    public let isBuiltIn: Bool

    public init(id: String, name: String, summary: String, rolePrompt: String, isBuiltIn: Bool = true) {
        self.id = id
        self.name = name
        self.summary = summary
        self.rolePrompt = rolePrompt
        self.isBuiltIn = isBuiltIn
    }

    public static let kiroBuiltIns: [AgentPreset] = [
        AgentPreset(id: "planner", name: "Planner", summary: "Asks short numbered questions and writes a clear plan before any code changes.", rolePrompt: "Plan first. Ask short numbered questions and wait for answers before building."),
        AgentPreset(id: "designer", name: "Designer", summary: "Designs clean iPhone screens, layouts, and interactions.", rolePrompt: "Design clean, native iPhone layouts and flows."),
        AgentPreset(id: "design-checker", name: "Design checker", summary: "Reviews screen layouts and catches missing buttons or awkward spacing.", rolePrompt: "Check the design against every requirement."),
        AgentPreset(id: "coder", name: "Coder", summary: "Writes and edits code cleanly in the selected repository.", rolePrompt: "Write clean, working code that matches the plan."),
        AgentPreset(id: "code-checker", name: "Code checker", summary: "Checks code for compiler errors, bugs, and edge cases.", rolePrompt: "Inspect all changed files for bugs and build issues."),
        AgentPreset(id: "second-opinion", name: "Second opinion", summary: "Another checker running on a different AI model to catch what the first missed.", rolePrompt: "Provide an independent review from a second AI model."),
        AgentPreset(id: "review-combiner", name: "Review combiner", summary: "Combines findings from multiple checkers into one clear list.", rolePrompt: "Merge code reviews into a single actionable list."),
        AgentPreset(id: "investigator", name: "Investigator", summary: "Looks into a bug or repo question and gives a plain-English report without changing files.", rolePrompt: "Read and search the repo to explain the issue clearly without modifying files."),
        AgentPreset(id: "researcher", name: "Researcher", summary: "Tries experiments, tests what works, and keeps only the winners.", rolePrompt: "Test hypotheses and keep only verified improvements."),
        AgentPreset(id: "builder", name: "Builder", summary: "Starts a GitHub build when asked and verifies the .ipa output.", rolePrompt: "Run and verify the .ipa build and check its contents."),
        AgentPreset(id: "workflow-maker", name: "Workflow maker", summary: "Turns your plain-English description into a step-by-step workflow for your OK.", rolePrompt: "Create a clean step-by-step workflow from the user's description."),
        AgentPreset(id: "request-sender", name: "Request sender", summary: "Commits to a clean side branch and opens a pull request into the main branch.", rolePrompt: "Open a clean pull request with a plain-English summary."),
        AgentPreset(id: "feedback-answerer", name: "Feedback answerer", summary: "Reads comments on a pull request and updates the branch to answer them.", rolePrompt: "Address pull request review comments cleanly.")
    ]
}

public struct WorkflowPreset: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var summary: String
    public var steps: [String]
    public let isBuiltIn: Bool

    public init(id: String, name: String, summary: String, steps: [String], isBuiltIn: Bool = true) {
        self.id = id
        self.name = name
        self.summary = summary
        self.steps = steps
        self.isBuiltIn = isBuiltIn
    }

    public static let kiroBuiltIns: [WorkflowPreset] = [
        WorkflowPreset(id: "look-into", name: "Look into something", summary: "Reads the repo and explains how something works or why a bug happens.", steps: ["Investigator"]),
        WorkflowPreset(id: "keep-going", name: "Keep going until a goal is met", summary: "Works in a loop and checks its own result until the goal passes.", steps: ["Coder", "Code checker", "Builder"]),
        WorkflowPreset(id: "checklist", name: "Work through a checklist", summary: "Checks off each item in your list one by one.", steps: ["Planner", "Coder", "Code checker"]),
        WorkflowPreset(id: "full-feature", name: "Full feature", summary: "Requirements, design, checked design, plan, build with a two-AI review, and final check.", steps: ["Planner", "Designer", "Design checker", "Coder", "Code checker", "Second opinion", "Review combiner"]),
        WorkflowPreset(id: "two-ai-review", name: "Two-AI review", summary: "Two different AIs check the code and combine their notes.", steps: ["Code checker", "Second opinion", "Review combiner"]),
        WorkflowPreset(id: "experiment", name: "Experiment until it's better", summary: "Tries changes and keeps what works best.", steps: ["Researcher", "Code checker"]),
        WorkflowPreset(id: "send-pr", name: "Send a side copy for review", summary: "Saves changes to a side branch and opens a pull request.", steps: ["Request sender", "Feedback answerer"]),
        WorkflowPreset(id: "build-ipa", name: "Build and check the .ipa", summary: "Starts the iOS build on GitHub and verifies the .ipa bundle.", steps: ["Builder"])
    ]
}

public struct MCPConnectorItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let iconName: String
    public let summary: String
    public let isPopular: Bool
    public var isConnected: Bool

    public init(id: String, name: String, iconName: String, summary: String, isPopular: Bool = true, isConnected: Bool = false) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.summary = summary
        self.isPopular = isPopular
        self.isConnected = isConnected
    }

    public static let defaultConnectors: [MCPConnectorItem] = [
        MCPConnectorItem(id: "github", name: "GitHub", iconName: "chevron.left.forwardslash.chevron.right", summary: "Repos, branches, pull requests, and .ipa builds"),
        MCPConnectorItem(id: "google-drive", name: "Drive", iconName: "externaldrive.fill", summary: "Read and search files in your Google Drive"),
        MCPConnectorItem(id: "google-docs", name: "Docs", iconName: "doc.text.fill", summary: "Read and write Google Docs"),
        MCPConnectorItem(id: "notion", name: "Notion", iconName: "book.closed.fill", summary: "Pages, databases, and notes in Notion"),
        MCPConnectorItem(id: "google-sheets", name: "Sheets", iconName: "tablecells.fill", summary: "Spreadsheets and tables in Google Sheets"),
        MCPConnectorItem(id: "gmail", name: "Gmail", iconName: "envelope.fill", summary: "Search and draft emails in Gmail"),
        MCPConnectorItem(id: "google-calendar", name: "Calendar", iconName: "calendar", summary: "Check events and schedules in Google Calendar"),
        MCPConnectorItem(id: "slack", name: "Slack", iconName: "bubble.left.and.bubble.right.fill", summary: "Channels and messages in Slack"),
        MCPConnectorItem(id: "linear", name: "Linear", iconName: "checklist", summary: "Issues and project tracking in Linear"),
        MCPConnectorItem(id: "figma", name: "Figma", iconName: "paintbrush.pointed.fill", summary: "Inspect Figma designs and frames"),
        MCPConnectorItem(id: "dropbox", name: "Dropbox", iconName: "shippingbox.fill", summary: "Files and folders in Dropbox")
    ]
}

public enum AppThemeMode: String, Codable, CaseIterable, Sendable {
    case dark = "dark"
    case light = "light"
    case system = "system"

    public var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .system: return "System"
        }
    }
}

public enum WorkflowTriggerChoice: String, Codable, CaseIterable, Sendable {
    case whenAsked = "when_asked"
    case bigJobsToo = "big_jobs_too"
    case everything = "everything"

    public var displayName: String {
        switch self {
        case .whenAsked: return "When asked"
        case .bigJobsToo: return "Big jobs too"
        case .everything: return "Everything"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var themeMode: AppThemeMode
    public var accentHex: String
    public var mascotMotionEnabled: Bool
    public var smoothChatTransitionsEnabled: Bool
    public var toolStepAnimationsEnabled: Bool
    public var showMascotOnHome: Bool
    public var notificationsEnabled: Bool
    public var workflowChoice: WorkflowTriggerChoice
    public var stopAndAskAtCostEnabled: Bool
    public var stopAndAskCostThresholdUSD: Double
    public var memoriesMasterSwitch: Bool
    public var perRepoSaveStraightToBranch: [String: Bool]

    public init(
        themeMode: AppThemeMode = .dark,
        accentHex: String = "#8B5CF6",
        mascotMotionEnabled: Bool = true,
        smoothChatTransitionsEnabled: Bool = true,
        toolStepAnimationsEnabled: Bool = true,
        showMascotOnHome: Bool = true,
        notificationsEnabled: Bool = true,
        workflowChoice: WorkflowTriggerChoice = .bigJobsToo,
        stopAndAskAtCostEnabled: Bool = false,
        stopAndAskCostThresholdUSD: Double = 1.00,
        memoriesMasterSwitch: Bool = true,
        perRepoSaveStraightToBranch: [String: Bool] = [:]
    ) {
        self.themeMode = themeMode
        self.accentHex = accentHex
        self.mascotMotionEnabled = mascotMotionEnabled
        self.smoothChatTransitionsEnabled = smoothChatTransitionsEnabled
        self.toolStepAnimationsEnabled = toolStepAnimationsEnabled
        self.showMascotOnHome = showMascotOnHome
        self.notificationsEnabled = notificationsEnabled
        self.workflowChoice = workflowChoice
        self.stopAndAskAtCostEnabled = stopAndAskAtCostEnabled
        self.stopAndAskCostThresholdUSD = stopAndAskCostThresholdUSD
        self.memoriesMasterSwitch = memoriesMasterSwitch
        self.perRepoSaveStraightToBranch = perRepoSaveStraightToBranch
    }
}

public struct PersistedWorkspaceBundle: Codable, Equatable, Sendable {
    public var chats: [ChatThread]
    public var groups: [ChatGroup]
    public var memories: [MemoryItem]
    public var customAgents: [AgentPreset]
    public var customWorkflows: [WorkflowPreset]
    public var settings: AppSettings
    public var lastSyncedAt: Date

    public init(
        chats: [ChatThread] = [],
        groups: [ChatGroup] = [],
        memories: [MemoryItem] = [],
        customAgents: [AgentPreset] = [],
        customWorkflows: [WorkflowPreset] = [],
        settings: AppSettings = AppSettings(),
        lastSyncedAt: Date = Date()
    ) {
        self.chats = chats
        self.groups = groups
        self.memories = memories
        self.customAgents = customAgents
        self.customWorkflows = customWorkflows
        self.settings = settings
        self.lastSyncedAt = lastSyncedAt
    }
}
