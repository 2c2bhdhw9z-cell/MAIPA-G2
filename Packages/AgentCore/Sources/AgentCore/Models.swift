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
    public let supportsImages: Bool
    public let inputPricePerMillion: Double
    public let outputPricePerMillion: Double
    public let summary: String

    public init(
        id: String,
        name: String,
        provider: String,
        isFree: Bool,
        supportsThinking: Bool,
        supportsImages: Bool = false,
        inputPricePerMillion: Double,
        outputPricePerMillion: Double,
        summary: String
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.isFree = isFree
        self.supportsThinking = supportsThinking
        self.supportsImages = supportsImages
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
            supportsImages: true,
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
            supportsImages: false,
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
            supportsImages: false,
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
            supportsImages: true,
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
            supportsImages: true,
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
            supportsImages: true,
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
            supportsImages: false,
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
            supportsImages: true,
            inputPricePerMillion: 0.0,
            outputPricePerMillion: 0.0,
            summary: "Large context window for reading whole repositories at $0."
        ),
        AIModelOption(
            id: "openai/gpt-5-mini",
            name: "GPT-5 Mini",
            provider: "OpenAI",
            isFree: false,
            supportsThinking: true,
            supportsImages: true,
            inputPricePerMillion: 0.25,
            outputPricePerMillion: 2.0,
            summary: "Fast multi-modal coding and second-opinion reviews."
        ),
        AIModelOption(
            id: "black-forest-labs/flux-1-schnell:free",
            name: "FLUX.1 Picture Maker",
            provider: "OpenRouter Images",
            isFree: true,
            supportsThinking: false,
            supportsImages: true,
            inputPricePerMillion: 0.0,
            outputPricePerMillion: 0.0,
            summary: "Generates icons, mockups, and pictures through OpenRouter."
        )
    ]
}

// MARK: - GitHub Models (Repos, Branches, Tree, Saved Changes, PRs, Actions Runs)

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

public struct RepoFileEditOperation: Identifiable, Codable, Equatable, Sendable {
    public enum OperationKind: String, Codable, Sendable {
        case update = "update"
        case create = "create"
        case delete = "delete"
    }

    public let id: String
    public let path: String
    public let kind: OperationKind
    public let content: String?

    public init(id: String = UUID().uuidString, path: String, kind: OperationKind, content: String? = nil) {
        self.id = id
        self.path = path
        self.kind = kind
        self.content = content
    }
}

/// Tracks a saved change or Pull Request created by an agent so the user can tap:
/// - "Add it" (squash-merge PR into default branch, then delete side branch)
/// - "Throw away" (close PR and delete side branch)
/// - "Undo" (revert the branch back to `previousCommitSha`)
public struct SavedChangeReceipt: Identifiable, Codable, Equatable, Sendable {
    public enum ResolutionState: String, Codable, Sendable {
        case pendingPR = "pending_pr"
        case savedDirect = "saved_direct"
        case merged = "merged"
        case thrownAway = "thrown_away"
        case undone = "undone"
    }

    public let id: String
    public let repoFullName: String
    public let baseBranch: String
    public let workingBranch: String
    public let commitSha: String
    public let previousCommitSha: String
    public let commitMessage: String
    public let changedPaths: [String]
    public let prNumber: Int?
    public let prURL: String?
    public var state: ResolutionState
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        repoFullName: String,
        baseBranch: String,
        workingBranch: String,
        commitSha: String,
        previousCommitSha: String,
        commitMessage: String,
        changedPaths: [String],
        prNumber: Int? = nil,
        prURL: String? = nil,
        state: ResolutionState,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.repoFullName = repoFullName
        self.baseBranch = baseBranch
        self.workingBranch = workingBranch
        self.commitSha = commitSha
        self.previousCommitSha = previousCommitSha
        self.commitMessage = commitMessage
        self.changedPaths = changedPaths
        self.prNumber = prNumber
        self.prURL = prURL
        self.state = state
        self.createdAt = createdAt
    }
}

public struct GitHubWorkflowRunItem: Identifiable, Codable, Equatable, Sendable {
    public let id: Int
    public let runNumber: Int
    public let name: String
    public let headBranch: String
    public let headSha: String
    public let status: String // "queued", "in_progress", "completed"
    public let conclusion: String? // "success", "failure", "cancelled"
    public let htmlURL: String
    public let createdAt: String

    public init(
        id: Int,
        runNumber: Int,
        name: String,
        headBranch: String,
        headSha: String,
        status: String,
        conclusion: String?,
        htmlURL: String,
        createdAt: String
    ) {
        self.id = id
        self.runNumber = runNumber
        self.name = name
        self.headBranch = headBranch
        self.headSha = headSha
        self.status = status
        self.conclusion = conclusion
        self.htmlURL = htmlURL
        self.createdAt = createdAt
    }
}

// MARK: - Attachments & Spec Mode Models

public struct ChatAttachmentItem: Identifiable, Codable, Equatable, Sendable {
    public enum AttachmentKind: String, Codable, Sendable {
        case photo = "photo"
        case file = "file"
        case repoFile = "repo_file"
    }

    public let id: String
    public let name: String
    public let kind: AttachmentKind
    public let mimeType: String
    public let textPreview: String?
    public let base64Data: String?
    public let sizeBytes: Int

    public init(
        id: String = UUID().uuidString,
        name: String,
        kind: AttachmentKind,
        mimeType: String = "text/plain",
        textPreview: String? = nil,
        base64Data: String? = nil,
        sizeBytes: Int = 0
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.mimeType = mimeType
        self.textPreview = textPreview
        self.base64Data = base64Data
        self.sizeBytes = sizeBytes
    }
}

public struct SpecTaskItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var number: Int
    public var title: String
    public var isCompleted: Bool

    public init(id: String = UUID().uuidString, number: Int, title: String, isCompleted: Bool = false) {
        self.id = id
        self.number = number
        self.title = title
        self.isCompleted = isCompleted
    }
}

/// Kiro's 3-step Spec flow (Item 6 & Answer 25):
/// 1. What it'll build (Requirements) -> User taps OK
/// 2. How it works (Design) -> User taps OK
/// 3. Task list -> User OKs and works down the list, saved to `.kiro/specs/<slug>/`
public struct SpecPlanDocument: Identifiable, Codable, Equatable, Sendable {
    public enum SpecStage: String, Codable, Sendable {
        case whatItWillBuild = "what"
        case howItWorks = "how"
        case taskChecklist = "tasks"
        case building = "building"
    }

    public let id: String
    public var slug: String
    public var title: String
    public var whatItWillBuild: String
    public var howItWorks: String
    public var tasks: [SpecTaskItem]
    public var stage: SpecStage
    public var whatApproved: Bool
    public var howApproved: Bool
    public var tasksApproved: Bool

    public init(
        id: String = UUID().uuidString,
        slug: String,
        title: String,
        whatItWillBuild: String,
        howItWorks: String,
        tasks: [SpecTaskItem],
        stage: SpecStage = .whatItWillBuild,
        whatApproved: Bool = false,
        howApproved: Bool = false,
        tasksApproved: Bool = false
    ) {
        self.id = id
        self.slug = slug
        self.title = title
        self.whatItWillBuild = whatItWillBuild
        self.howItWorks = howItWorks
        self.tasks = tasks
        self.stage = stage
        self.whatApproved = whatApproved
        self.howApproved = howApproved
        self.tasksApproved = tasksApproved
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
    public var attachments: [ChatAttachmentItem]
    public var savedChangeReceipt: SavedChangeReceipt?
    public var autoSavedMemories: [String]
    public var generatedImageURL: String?
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
        attachments: [ChatAttachmentItem] = [],
        savedChangeReceipt: SavedChangeReceipt? = nil,
        autoSavedMemories: [String] = [],
        generatedImageURL: String? = nil,
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
        self.attachments = attachments
        self.savedChangeReceipt = savedChangeReceipt
        self.autoSavedMemories = autoSavedMemories
        self.generatedImageURL = generatedImageURL
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
    public var activeAgentId: String?
    public var activeWorkflowId: String?
    public var specDocument: SpecPlanDocument?
    public var lastSavedReceipt: SavedChangeReceipt?
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
        activeAgentId: String? = nil,
        activeWorkflowId: String? = nil,
        specDocument: SpecPlanDocument? = nil,
        lastSavedReceipt: SavedChangeReceipt? = nil,
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
        self.activeAgentId = activeAgentId
        self.activeWorkflowId = activeWorkflowId
        self.specDocument = specDocument
        self.lastSavedReceipt = lastSavedReceipt
        self.messages = messages
        self.totalCostUSD = totalCostUSD
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Memories, Agents, Workflows, MCP Connectors, and Settings

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
    public var maxLoopCount: Int
    public var hasStopAndAskStep: Bool
    public let isBuiltIn: Bool

    public init(
        id: String,
        name: String,
        summary: String,
        steps: [String],
        maxLoopCount: Int = 1,
        hasStopAndAskStep: Bool = false,
        isBuiltIn: Bool = true
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.steps = steps
        self.maxLoopCount = maxLoopCount
        self.hasStopAndAskStep = hasStopAndAskStep
        self.isBuiltIn = isBuiltIn
    }

    public static let kiroBuiltIns: [WorkflowPreset] = [
        WorkflowPreset(id: "look-into", name: "Look into something", summary: "Reads the repo and explains how something works or why a bug happens.", steps: ["Investigator"]),
        WorkflowPreset(id: "keep-going", name: "Keep going until a goal is met", summary: "Works in a loop and checks its own result until the goal passes.", steps: ["Coder", "Code checker", "Builder"], maxLoopCount: 3),
        WorkflowPreset(id: "checklist", name: "Work through a checklist", summary: "Checks off each item in your list one by one.", steps: ["Planner", "Coder", "Code checker"]),
        WorkflowPreset(id: "full-feature", name: "Full feature", summary: "Requirements, design, checked design, plan, build with a two-AI review, and final check.", steps: ["Planner", "Designer", "Design checker", "Coder", "Code checker", "Second opinion", "Review combiner"], hasStopAndAskStep: true),
        WorkflowPreset(id: "two-ai-review", name: "Two-AI review", summary: "Two different AIs check the code and combine their notes.", steps: ["Code checker", "Second opinion", "Review combiner"]),
        WorkflowPreset(id: "experiment", name: "Experiment until it's better", summary: "Tries changes and keeps what works best.", steps: ["Researcher", "Code checker"], maxLoopCount: 3),
        WorkflowPreset(id: "send-pr", name: "Send a side copy for review", summary: "Saves changes to a side branch and opens a pull request.", steps: ["Request sender", "Feedback answerer"]),
        WorkflowPreset(id: "build-ipa", name: "Build and check the .ipa", summary: "Starts the iOS build on GitHub and verifies the .ipa bundle.", steps: ["Builder"])
    ]
}

public enum MCPConnectorCategory: String, Codable, CaseIterable, Sendable {
    case codeAndDev = "Code & Build"
    case cloudAndDB = "Cloud & Databases"
    case searchAndWeb = "Search & Research"
    case chatAndTeam = "Chat & Issues"
    case designAndMedia = "Design & Media"
    case docsAndFiles = "Docs & Storage"
    case googleWorkspace = "Google Workspace"
    case automationAndHome = "Automation & Daily"
    case officialRegistry = "MCP Registry"
}

public struct MCPConnectorItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var iconName: String
    public var category: MCPConnectorCategory
    public var summary: String
    public var serverURL: String?
    public var requiresWebsiteSetupNote: String?
    public var isPopular: Bool
    public var isConnected: Bool

    public init(
        id: String,
        name: String,
        iconName: String,
        category: MCPConnectorCategory = .codeAndDev,
        summary: String,
        serverURL: String? = nil,
        requiresWebsiteSetupNote: String? = nil,
        isPopular: Bool = true,
        isConnected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.category = category
        self.summary = summary
        self.serverURL = serverURL
        self.requiresWebsiteSetupNote = requiresWebsiteSetupNote
        self.isPopular = isPopular
        self.isConnected = isConnected
    }

    public static let defaultConnectors: [MCPConnectorItem] = [
        // Code & Build
        MCPConnectorItem(id: "github", name: "GitHub", iconName: "chevron.left.forwardslash.chevron.right", category: .codeAndDev, summary: "Repos, branches, pull requests, and .ipa builds"),
        MCPConnectorItem(id: "gitlab", name: "GitLab", iconName: "chevron.left.forwardslash.chevron.right", category: .codeAndDev, summary: "GitLab repositories, merge requests, and CI pipelines", serverURL: "https://mcp.gitlab.com/sse"),
        MCPConnectorItem(id: "sentry", name: "Sentry", iconName: "ladybug.fill", category: .codeAndDev, summary: "Crash reports, stack traces, and release health", serverURL: "https://mcp.sentry.dev/sse"),
        MCPConnectorItem(id: "vercel", name: "Vercel", iconName: "triangle.fill", category: .codeAndDev, summary: "Deployments, preview links, and build logs", serverURL: "https://mcp.vercel.com/sse"),
        MCPConnectorItem(id: "cloudflare", name: "Cloudflare", iconName: "cloud.fill", category: .codeAndDev, summary: "Workers, KV, D1, R2 storage, and DNS", serverURL: "https://mcp.cloudflare.com/sse"),
        MCPConnectorItem(id: "docker", name: "Docker Hub", iconName: "shippingbox.and.arrow.backward.fill", category: .codeAndDev, summary: "Container images, tags, and build registries"),
        MCPConnectorItem(id: "apple-docs", name: "Apple Developer Docs", iconName: "apple.logo", category: .codeAndDev, summary: "Swift, SwiftUI, Xcode, and iOS 17–26 documentation"),
        MCPConnectorItem(id: "context7", name: "Context7 Library Docs", iconName: "books.vertical.fill", category: .codeAndDev, summary: "Up-to-date SDK and package documentation for coding"),

        // Cloud & Databases
        MCPConnectorItem(id: "supabase", name: "Supabase", iconName: "bolt.horizontal.fill", category: .cloudAndDB, summary: "Postgres tables, edge functions, and auth", serverURL: "https://mcp.supabase.com/sse"),
        MCPConnectorItem(id: "neon", name: "Neon Postgres", iconName: "cylinder.split.1x2.fill", category: .cloudAndDB, summary: "Serverless Postgres branches and SQL queries", serverURL: "https://mcp.neon.tech/sse"),
        MCPConnectorItem(id: "firebase", name: "Firebase", iconName: "flame.fill", category: .cloudAndDB, summary: "Firestore collections, rules, and Crashlytics"),
        MCPConnectorItem(id: "upstash", name: "Upstash Redis", iconName: "memorychip.fill", category: .cloudAndDB, summary: "Serverless Redis queues and rate limits"),
        MCPConnectorItem(id: "stripe", name: "Stripe", iconName: "creditcard.fill", category: .cloudAndDB, summary: "Payments, subscriptions, webhooks, and invoices", serverURL: "https://mcp.stripe.com/sse"),
        MCPConnectorItem(id: "aws", name: "AWS Cloud", iconName: "server.rack", category: .cloudAndDB, summary: "S3 buckets, Lambda functions, and CloudWatch logs"),

        // Search & Research
        MCPConnectorItem(id: "brave-search", name: "Brave Search", iconName: "safari.fill", category: .searchAndWeb, summary: "Fast web and code search without tracking"),
        MCPConnectorItem(id: "exa", name: "Exa Search", iconName: "sparkle.magnifyingglass", category: .searchAndWeb, summary: "Deep semantic search for papers, repos, and docs", serverURL: "https://mcp.exa.ai/sse"),
        MCPConnectorItem(id: "perplexity", name: "Perplexity", iconName: "globe.americas.fill", category: .searchAndWeb, summary: "Cited web research and fact checking"),
        MCPConnectorItem(id: "fetch-reader", name: "Web Page Reader", iconName: "doc.richtext", category: .searchAndWeb, summary: "Fetches any URL and turns it into clean readable text", isConnected: true),
        MCPConnectorItem(id: "arxiv", name: "arXiv Papers", iconName: "graduationcap.fill", category: .searchAndWeb, summary: "Search and read research papers on arXiv"),
        MCPConnectorItem(id: "wikipedia", name: "Wikipedia", iconName: "book.fill", category: .searchAndWeb, summary: "Instant encyclopedia lookup and article summaries"),

        // Chat & Issues
        MCPConnectorItem(id: "discord", name: "Discord", iconName: "gamecontroller.fill", category: .chatAndTeam, summary: "Servers, channels, webhooks, and bot messages"),
        MCPConnectorItem(id: "linear", name: "Linear", iconName: "checklist", category: .chatAndTeam, summary: "Issues, cycles, and project roadmaps", serverURL: "https://mcp.linear.app/sse"),
        MCPConnectorItem(id: "slack", name: "Slack", iconName: "bubble.left.and.bubble.right.fill", category: .chatAndTeam, summary: "Channels, threads, and messages in Slack", serverURL: "https://mcp.slack.com/sse"),
        MCPConnectorItem(id: "jira", name: "Jira", iconName: "list.bullet.rectangle.portrait.fill", category: .chatAndTeam, summary: "Tickets, sprints, and boards in Atlassian Jira"),
        MCPConnectorItem(id: "telegram", name: "Telegram", iconName: "paperplane.fill", category: .chatAndTeam, summary: "Send alerts and chat updates via Telegram bot"),

        // Design & Media
        MCPConnectorItem(id: "figma", name: "Figma", iconName: "paintbrush.pointed.fill", category: .designAndMedia, summary: "Inspect Figma frames, tokens, and layout specs", serverURL: "https://mcp.figma.com/sse"),
        MCPConnectorItem(id: "spotify", name: "Spotify", iconName: "music.note.list", category: .designAndMedia, summary: "Playlists, tracks, and playback controls"),
        MCPConnectorItem(id: "youtube", name: "YouTube Transcripts", iconName: "play.rectangle.fill", category: .designAndMedia, summary: "Read video captions, chapters, and summaries"),
        MCPConnectorItem(id: "huggingface", name: "Hugging Face", iconName: "face.smiling.inverse", category: .designAndMedia, summary: "Open models, datasets, and Spaces", serverURL: "https://hf.co/mcp"),

        // Docs & Storage
        MCPConnectorItem(id: "obsidian", name: "Obsidian Vault", iconName: "note.text", category: .docsAndFiles, summary: "Markdown notes and backlinks"),
        MCPConnectorItem(id: "notion", name: "Notion", iconName: "book.closed.fill", category: .docsAndFiles, summary: "Pages, databases, and notes in Notion", serverURL: "https://mcp.notion.com/sse"),
        MCPConnectorItem(id: "dropbox", name: "Dropbox", iconName: "shippingbox.fill", category: .docsAndFiles, summary: "Files and shared folders in Dropbox"),
        MCPConnectorItem(id: "airtable", name: "Airtable", iconName: "tablecells.badge.ellipsis", category: .docsAndFiles, summary: "Structured bases, records, and views"),

        // Google Workspace (Official remote MCP servers)
        MCPConnectorItem(id: "google-drive", name: "Google Drive", iconName: "externaldrive.fill", category: .googleWorkspace, summary: "Read and search files in Google Drive", serverURL: "https://drive.mcp.googleapis.com/mcp", requiresWebsiteSetupNote: "Uses Google's remote MCP server with OAuth 2.1."),
        MCPConnectorItem(id: "google-docs", name: "Google Docs", iconName: "doc.text.fill", category: .googleWorkspace, summary: "Read and write Google Docs", serverURL: "https://docs.mcp.googleapis.com/mcp"),
        MCPConnectorItem(id: "google-sheets", name: "Google Sheets", iconName: "tablecells.fill", category: .googleWorkspace, summary: "Spreadsheets and tables in Google Sheets", serverURL: "https://sheets.mcp.googleapis.com/mcp"),
        MCPConnectorItem(id: "google-slides", name: "Google Slides", iconName: "rectangle.on.rectangle.angled", category: .googleWorkspace, summary: "Presentations and slides in Google Slides", serverURL: "https://slides.mcp.googleapis.com/mcp"),
        MCPConnectorItem(id: "gmail", name: "Gmail", iconName: "envelope.fill", category: .googleWorkspace, summary: "Search and draft emails in Gmail", serverURL: "https://gmail.mcp.googleapis.com/mcp"),
        MCPConnectorItem(id: "google-calendar", name: "Google Calendar", iconName: "calendar", category: .googleWorkspace, summary: "Check events and schedules in Google Calendar", serverURL: "https://calendar.mcp.googleapis.com/mcp"),

        // Automation & Daily
        MCPConnectorItem(id: "home-assistant", name: "Home Assistant", iconName: "house.fill", category: .automationAndHome, summary: "Smart home lights, sensors, and automations"),
        MCPConnectorItem(id: "todoist", name: "Todoist", iconName: "checkmark.circle.fill", category: .automationAndHome, summary: "Personal tasks, due dates, and checklists", serverURL: "https://mcp.todoist.com/sse"),
        MCPConnectorItem(id: "zapier", name: "Zapier MCP", iconName: "bolt.circle.fill", category: .automationAndHome, summary: "Connect 7,000+ everyday apps through Zapier actions", serverURL: "https://mcp.zapier.com/sse")
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
    public var showUnconnectedConnectorsOnHome: Bool
    public var hiddenConnectorIds: [String]
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
        showUnconnectedConnectorsOnHome: Bool = false,
        hiddenConnectorIds: [String] = ["google-drive", "google-docs", "notion", "google-sheets", "google-slides"],
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
        self.showUnconnectedConnectorsOnHome = showUnconnectedConnectorsOnHome
        self.hiddenConnectorIds = hiddenConnectorIds
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
    public var customConnectors: [MCPConnectorItem]
    public var settings: AppSettings
    public var lastSyncedAt: Date

    public init(
        chats: [ChatThread] = [],
        groups: [ChatGroup] = [],
        memories: [MemoryItem] = [],
        customAgents: [AgentPreset] = [],
        customWorkflows: [WorkflowPreset] = [],
        customConnectors: [MCPConnectorItem] = [],
        settings: AppSettings = AppSettings(),
        lastSyncedAt: Date = Date()
    ) {
        self.chats = chats
        self.groups = groups
        self.memories = memories
        self.customAgents = customAgents
        self.customWorkflows = customWorkflows
        self.customConnectors = customConnectors
        self.settings = settings
        self.lastSyncedAt = lastSyncedAt
    }
}
