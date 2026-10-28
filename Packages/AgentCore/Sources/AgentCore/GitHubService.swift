import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum GitHubServiceError: Error, LocalizedError {
    case notConnected
    case invalidURL(String)
    case httpError(Int, String)
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "GitHub is not connected yet. Tap Connect GitHub first."
        case .invalidURL(let url):
            return "Invalid GitHub URL: \(url)"
        case .httpError(let status, let body):
            return "GitHub returned HTTP \(status): \(body)"
        case .decodingError(let reason):
            return "Could not read GitHub response: \(reason)"
        }
    }
}

public struct GitHubDeviceFlowStart: Codable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationUri: String
    public let expiresIn: Int
    public let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

public struct GitHubBuildReleaseInfo: Codable, Equatable, Sendable {
    public let tagName: String
    public let title: String
    public let htmlURL: String
    public let ipaDownloadURL: String
    public let publishedAt: String?

    public init(tagName: String, title: String, htmlURL: String, ipaDownloadURL: String, publishedAt: String?) {
        self.tagName = tagName
        self.title = title
        self.htmlURL = htmlURL
        self.ipaDownloadURL = ipaDownloadURL
        self.publishedAt = publishedAt
    }
}

public final class GitHubService: @unchecked Sendable {
    public static let officialDeviceFlowClientId = "178c6fc778ccc68e1d6a"
    public static let maipaGRepoFullName = "2c2bhdhw9z-cell/MAIPA-G2"
    public static let privateDataRepoName = "MAIPA-G-data"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Sign in without copying keys (Manifest conversion & Device Flow)

    public func exchangeAppManifestCode(_ code: String) async throws -> (appId: Int, slug: String, pem: String, clientId: String, clientSecret: String) {
        guard let url = URL(string: "https://api.github.com/app-manifests/\(code)/conversions") else {
            throw GitHubServiceError.invalidURL(code)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MAIPA-G-iOS", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubServiceError.httpError(status, body)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? Int,
              let slug = json["slug"] as? String,
              let pem = json["pem"] as? String,
              let clientId = json["client_id"] as? String,
              let clientSecret = json["client_secret"] as? String else {
            throw GitHubServiceError.decodingError("Missing GitHub App manifest fields")
        }
        return (id, slug, pem, clientId, clientSecret)
    }

    public func startDeviceFlow(clientId: String = GitHubService.officialDeviceFlowClientId) async throws -> GitHubDeviceFlowStart {
        guard let url = URL(string: "https://github.com/login/device/code") else {
            throw GitHubServiceError.invalidURL("device/code")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "client_id=\(clientId)&scope=repo,workflow,read:user".data(using: .utf8)

        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw GitHubServiceError.httpError(status, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(GitHubDeviceFlowStart.self, from: data)
    }

    public func pollDeviceFlowOnce(deviceCode: String, clientId: String = GitHubService.officialDeviceFlowClientId) async throws -> String? {
        guard let url = URL(string: "https://github.com/login/oauth/access_token") else {
            throw GitHubServiceError.invalidURL("access_token")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "client_id=\(clientId)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
        req.httpBody = body.data(using: .utf8)

        let (data, _) = try await session.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let token = json["access_token"] as? String, !token.isEmpty {
            return token
        }
        return nil
    }

    // MARK: - User & Repository Operations

    public func fetchAuthenticatedUsername(token: String) async throws -> String {
        let data = try await githubGET(path: "/user", token: token)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = json["login"] as? String else {
            throw GitHubServiceError.decodingError("Missing login")
        }
        return login
    }

    /// Only fetches repositories when a valid GitHub token is connected.
    /// Does NOT auto-connect or pull fallback repositories when signed out.
    public func fetchRepositories(token: String?) async throws -> [GitHubRepo] {
        guard let token = token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        let path = "/user/repos?sort=updated&per_page=100&affiliation=owner,collaborator"
        let data = try await githubGET(path: path, token: token)
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw GitHubServiceError.decodingError("Expected array of repos")
        }
        return arr.compactMap { item -> GitHubRepo? in
            guard let id = item["id"] as? Int,
                  let name = item["name"] as? String,
                  let fullName = item["full_name"] as? String,
                  let owner = item["owner"] as? [String: Any],
                  let login = owner["login"] as? String else {
                return nil
            }
            let defaultBranch = (item["default_branch"] as? String) ?? "main"
            let isPrivate = (item["private"] as? Bool) ?? false
            let desc = item["description"] as? String
            let updatedAt = item["updated_at"] as? String
            return GitHubRepo(
                id: id,
                name: name,
                fullName: fullName,
                ownerLogin: login,
                defaultBranch: defaultBranch,
                isPrivate: isPrivate,
                description: desc,
                updatedAt: updatedAt
            )
        }
    }

    public func createRepository(name: String, description: String, isPrivate: Bool, token: String) async throws -> GitHubRepo {
        let body: [String: Any] = [
            "name": name,
            "description": description,
            "private": isPrivate,
            "auto_init": true
        ]
        let data = try await githubRequest(method: "POST", path: "/user/repos", token: token, bodyJSON: body)
        guard let item = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = item["id"] as? Int,
              let repoName = item["name"] as? String,
              let fullName = item["full_name"] as? String,
              let owner = item["owner"] as? [String: Any],
              let login = owner["login"] as? String else {
            throw GitHubServiceError.decodingError("Could not parse created repo")
        }
        let defaultBranch = (item["default_branch"] as? String) ?? "main"
        return GitHubRepo(
            id: id,
            name: repoName,
            fullName: fullName,
            ownerLogin: login,
            defaultBranch: defaultBranch,
            isPrivate: isPrivate,
            description: description
        )
    }

    public func fetchBranches(fullName: String, token: String?) async throws -> [GitHubBranch] {
        let data = try await githubGET(path: "/repos/\(fullName)/branches?per_page=100", token: token)
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw GitHubServiceError.decodingError("Expected array of branches")
        }
        return arr.compactMap { item in
            guard let name = item["name"] as? String,
                  let commit = item["commit"] as? [String: Any],
                  let sha = commit["sha"] as? String else {
                return nil
            }
            return GitHubBranch(name: name, sha: sha)
        }
    }

    public func fetchTree(fullName: String, branch: String, token: String?) async throws -> [GitHubTreeItem] {
        let encodedBranch = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch
        let data = try await githubGET(path: "/repos/\(fullName)/git/trees/\(encodedBranch)?recursive=1", token: token)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tree = json["tree"] as? [[String: Any]] else {
            throw GitHubServiceError.decodingError("Expected git tree")
        }
        return tree.compactMap { item in
            guard let path = item["path"] as? String,
                  let type = item["type"] as? String,
                  let sha = item["sha"] as? String else {
                return nil
            }
            let size = item["size"] as? Int
            return GitHubTreeItem(path: path, type: type, size: size, sha: sha)
        }
    }

    public func fetchFileContent(fullName: String, path: String, branch: String, token: String?) async throws -> String {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedBranch = branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? branch
        let data = try await githubGET(path: "/repos/\(fullName)/contents/\(cleanPath)?ref=\(encodedBranch)", token: token)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GitHubServiceError.decodingError("Expected file content object")
        }
        if let contentB64 = json["content"] as? String {
            let cleaned = contentB64.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
            if let decoded = Data(base64Encoded: cleaned),
               let text = String(data: decoded, encoding: .utf8) {
                return text
            }
        }
        throw GitHubServiceError.decodingError("File is binary or could not be decoded as UTF-8 text.")
    }

    public func searchInRepo(fullName: String, branch: String, query: String, token: String?) async throws -> [(path: String, line: Int, snippet: String)] {
        let tree = try await fetchTree(fullName: fullName, branch: branch, token: token)
        let lowerQuery = query.lowercased()

        var results: [(path: String, line: Int, snippet: String)] = []
        let candidateFiles = tree.filter { item in
            guard item.type == "blob", (item.size ?? 0) < 120_000 else { return false }
            let ext = (item.path as NSString).pathExtension.lowercased()
            let textExts: Set<String> = ["swift", "md", "yml", "yaml", "json", "sh", "py", "ts", "tsx", "js", "rs", "c", "h", "cpp", "txt", "plist", "entitlements", "html", "css"]
            return textExts.contains(ext) || item.path.lowercased().contains(lowerQuery)
        }

        let sortedCandidates = candidateFiles.sorted { a, b in
            let aMatch = a.path.lowercased().contains(lowerQuery)
            let bMatch = b.path.lowercased().contains(lowerQuery)
            if aMatch != bMatch { return aMatch }
            return a.path < b.path
        }.prefix(18)

        for file in sortedCandidates {
            if file.path.lowercased().contains(lowerQuery) {
                results.append((path: file.path, line: 1, snippet: "[Filename match] \(file.path)"))
            }
            if let content = try? await fetchFileContent(fullName: fullName, path: file.path, branch: branch, token: token) {
                let lines = content.components(separatedBy: .newlines)
                for (idx, lineText) in lines.enumerated() {
                    if lineText.lowercased().contains(lowerQuery) {
                        let trimmed = String(lineText.trimmingCharacters(in: .whitespaces).prefix(160))
                        results.append((path: file.path, line: idx + 1, snippet: trimmed))
                        if results.count >= 30 {
                            return results
                        }
                    }
                }
            }
        }
        return results
    }

    // MARK: - Build 2: Saving Code Changes (Side Branch + PR or Straight-to-Branch) & Undo (Answer 9)

    /// Checks whether a repo's own rules say "no branches" (like Continuum) or if the user turned on straight-to-branch saving.
    public func shouldSaveStraightToBranch(fullName: String, pickedBranch: String, defaultBranch: String, settings: AppSettings) -> Bool {
        if fullName.lowercased().contains("continuum") {
            return true
        }
        if settings.perRepoSaveStraightToBranch[fullName] == true {
            return true
        }
        // If user explicitly picked a non-default branch, work on that branch directly (Answer 9)
        if pickedBranch != defaultBranch {
            return true
        }
        return false
    }

    /// Commits file changes to GitHub under MAIPA-G's name (Answer 9 & line 43).
    /// - If `pickedBranch == defaultBranch` and straight-save is off, creates a new side branch (`maipa-g/<slug>`) and opens a Pull Request into `defaultBranch`.
    /// - Otherwise saves directly onto `pickedBranch`.
    public func saveChangesToRepo(
        fullName: String,
        pickedBranch: String,
        defaultBranch: String,
        commitMessage: String,
        operations: [RepoFileEditOperation],
        settings: AppSettings,
        token: String
    ) async throws -> SavedChangeReceipt {
        guard !token.isEmpty else { throw GitHubServiceError.notConnected }

        // 1. Get the current HEAD SHA of pickedBranch
        let refData = try await githubGET(path: "/repos/\(fullName)/git/ref/heads/\(pickedBranch)", token: token)
        guard let refJSON = try JSONSerialization.jsonObject(with: refData) as? [String: Any],
              let obj = refJSON["object"] as? [String: Any],
              let baseCommitSha = obj["sha"] as? String else {
            throw GitHubServiceError.decodingError("Could not read branch HEAD SHA")
        }

        // 2. Get base commit's tree SHA
        let commitData = try await githubGET(path: "/repos/\(fullName)/git/commits/\(baseCommitSha)", token: token)
        guard let commitJSON = try JSONSerialization.jsonObject(with: commitData) as? [String: Any],
              let treeObj = commitJSON["tree"] as? [String: Any],
              let baseTreeSha = treeObj["sha"] as? String else {
            throw GitHubServiceError.decodingError("Could not read base tree SHA")
        }

        // 3. Determine target branch (side branch vs straight-to-branch)
        let saveDirect = shouldSaveStraightToBranch(
            fullName: fullName,
            pickedBranch: pickedBranch,
            defaultBranch: defaultBranch,
            settings: settings
        )
        let shortId = String(UUID().uuidString.lowercased().prefix(6))
        let workingBranch = saveDirect ? pickedBranch : "maipa-g/update-\(shortId)"

        if !saveDirect {
            let createRefBody: [String: Any] = [
                "ref": "refs/heads/\(workingBranch)",
                "sha": baseCommitSha
            ]
            _ = try await githubRequest(method: "POST", path: "/repos/\(fullName)/git/refs", token: token, bodyJSON: createRefBody)
        }

        // 4. Build tree entries for all operations
        var treeEntries: [[String: Any]] = []
        for op in operations {
            let cleanPath = op.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            switch op.kind {
            case .create, .update:
                let content = op.content ?? ""
                let blobBody: [String: Any] = [
                    "content": content,
                    "encoding": "utf-8"
                ]
                let blobData = try await githubRequest(method: "POST", path: "/repos/\(fullName)/git/blobs", token: token, bodyJSON: blobBody)
                guard let blobJSON = try JSONSerialization.jsonObject(with: blobData) as? [String: Any],
                      let blobSha = blobJSON["sha"] as? String else {
                    throw GitHubServiceError.decodingError("Could not create blob for \(cleanPath)")
                }
                let isShellScript = cleanPath.hasSuffix(".sh")
                treeEntries.append([
                    "path": cleanPath,
                    "mode": isShellScript ? "100755" : "100644",
                    "type": "blob",
                    "sha": blobSha
                ])
            case .delete:
                treeEntries.append([
                    "path": cleanPath,
                    "mode": "100644",
                    "type": "blob",
                    "sha": NSNull()
                ])
            }
        }

        // 5. Create new Git Tree
        let newTreeBody: [String: Any] = [
            "base_tree": baseTreeSha,
            "tree": treeEntries
        ]
        let newTreeData = try await githubRequest(method: "POST", path: "/repos/\(fullName)/git/trees", token: token, bodyJSON: newTreeBody)
        guard let newTreeJSON = try JSONSerialization.jsonObject(with: newTreeData) as? [String: Any],
              let newTreeSha = newTreeJSON["sha"] as? String else {
            throw GitHubServiceError.decodingError("Could not create Git tree")
        }

        // 6. Create Git Commit signed under MAIPA-G's name (line 43 of PLAN.md)
        let newCommitBody: [String: Any] = [
            "message": commitMessage,
            "tree": newTreeSha,
            "parents": [baseCommitSha],
            "author": [
                "name": "MAIPA-G",
                "email": "maipa-g@users.noreply.github.com"
            ],
            "committer": [
                "name": "MAIPA-G",
                "email": "maipa-g@users.noreply.github.com"
            ]
        ]
        let newCommitData = try await githubRequest(method: "POST", path: "/repos/\(fullName)/git/commits", token: token, bodyJSON: newCommitBody)
        guard let newCommitJSON = try JSONSerialization.jsonObject(with: newCommitData) as? [String: Any],
              let newCommitSha = newCommitJSON["sha"] as? String else {
            throw GitHubServiceError.decodingError("Could not create Git commit")
        }

        // 7. Update workingBranch ref to point to newCommitSha
        let updateRefBody: [String: Any] = [
            "sha": newCommitSha,
            "force": false
        ]
        _ = try await githubRequest(method: "PATCH", path: "/repos/\(fullName)/git/refs/heads/\(workingBranch)", token: token, bodyJSON: updateRefBody)

        // 8. If working on a side branch, open a Pull Request into defaultBranch
        var prNumber: Int? = nil
        var prURL: String? = nil
        if !saveDirect {
            let prBody: [String: Any] = [
                "title": commitMessage,
                "head": workingBranch,
                "base": defaultBranch,
                "body": "Saved by **MAIPA-G**.\n\nChanged files:\n" + operations.map { "- `\($0.path)` (\($0.kind.rawValue))" }.joined(separator: "\n")
            ]
            let prData = try await githubRequest(method: "POST", path: "/repos/\(fullName)/pulls", token: token, bodyJSON: prBody)
            if let prJSON = try JSONSerialization.jsonObject(with: prData) as? [String: Any] {
                prNumber = prJSON["number"] as? Int
                prURL = prJSON["html_url"] as? String
            }
        }

        return SavedChangeReceipt(
            repoFullName: fullName,
            baseBranch: defaultBranch,
            workingBranch: workingBranch,
            commitSha: newCommitSha,
            previousCommitSha: baseCommitSha,
            commitMessage: commitMessage,
            changedPaths: operations.map(\.path),
            prNumber: prNumber,
            prURL: prURL,
            state: saveDirect ? .savedDirect : .pendingPR
        )
    }

    /// Answer 9: "Add it" button — squash-merges the PR into the base branch, then deletes the side branch.
    public func mergeAndTidyPullRequest(receipt: SavedChangeReceipt, token: String) async throws {
        guard let prNum = receipt.prNumber else { return }
        let mergeBody: [String: Any] = [
            "commit_title": receipt.commitMessage,
            "merge_method": "squash"
        ]
        _ = try await githubRequest(method: "PUT", path: "/repos/\(receipt.repoFullName)/pulls/\(prNum)/merge", token: token, bodyJSON: mergeBody)
        if receipt.workingBranch != receipt.baseBranch {
            _ = try? await githubRequest(method: "DELETE", path: "/repos/\(receipt.repoFullName)/git/refs/heads/\(receipt.workingBranch)", token: token, bodyJSON: nil)
        }
    }

    /// Answer 9: "Throw away" button — closes the PR without merging and deletes the side branch.
    public func closeAndTidyPullRequest(receipt: SavedChangeReceipt, token: String) async throws {
        if let prNum = receipt.prNumber {
            let closeBody: [String: Any] = ["state": "closed"]
            _ = try? await githubRequest(method: "PATCH", path: "/repos/\(receipt.repoFullName)/pulls/\(prNum)", token: token, bodyJSON: closeBody)
        }
        if receipt.workingBranch != receipt.baseBranch {
            _ = try? await githubRequest(method: "DELETE", path: "/repos/\(receipt.repoFullName)/git/refs/heads/\(receipt.workingBranch)", token: token, bodyJSON: nil)
        }
    }

    /// Answer 9: "Undo" button — one tap takes back the last change an agent saved.
    public func undoLastSavedChange(receipt: SavedChangeReceipt, token: String) async throws {
        if receipt.state == .pendingPR {
            try await closeAndTidyPullRequest(receipt: receipt, token: token)
            return
        }
        // Reset the branch ref back to previousCommitSha
        let resetBody: [String: Any] = [
            "sha": receipt.previousCommitSha,
            "force": true
        ]
        _ = try await githubRequest(
            method: "PATCH",
            path: "/repos/\(receipt.repoFullName)/git/refs/heads/\(receipt.workingBranch)",
            token: token,
            bodyJSON: resetBody
        )
    }

    // MARK: - Build 3: GitHub Actions Runs, Build Checking, and Autonomous Jobs

    public func fetchWorkflowRuns(fullName: String, token: String?) async throws -> [GitHubWorkflowRunItem] {
        let data = try await githubGET(path: "/repos/\(fullName)/actions/runs?per_page=15", token: token)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runs = json["workflow_runs"] as? [[String: Any]] else {
            return []
        }
        return runs.compactMap { item in
            guard let id = item["id"] as? Int,
                  let name = item["name"] as? String,
                  let headBranch = item["head_branch"] as? String,
                  let headSha = item["head_sha"] as? String,
                  let status = item["status"] as? String,
                  let htmlURL = item["html_url"] as? String else {
                return nil
            }
            let runNumber = (item["run_number"] as? Int) ?? 0
            let conclusion = item["conclusion"] as? String
            let createdAt = (item["created_at"] as? String) ?? ""
            return GitHubWorkflowRunItem(
                id: id,
                runNumber: runNumber,
                name: name,
                headBranch: headBranch,
                headSha: headSha,
                status: status,
                conclusion: conclusion,
                htmlURL: htmlURL,
                createdAt: createdAt
            )
        }
    }

    public func triggerWorkflowDispatch(fullName: String, workflowFileName: String = "ios.yml", ref: String = "main", token: String) async throws {
        let body: [String: Any] = ["ref": ref]
        _ = try await githubRequest(
            method: "POST",
            path: "/repos/\(fullName)/actions/workflows/\(workflowFileName)/dispatches",
            token: token,
            bodyJSON: body
        )
    }

    // MARK: - Build 5: Official MCP Registry Live Search (40,000+ Connectors — Answer 28)

    public func searchOfficialMCPRegistry(query: String) async throws -> [MCPConnectorItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = trimmed.isEmpty
            ? "https://registry.modelcontextprotocol.io/v0/servers?limit=30"
            : "https://registry.modelcontextprotocol.io/v0/servers?search=\(encoded)&limit=30"
        guard let url = URL(string: urlString) else { return [] }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10

        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let rawServers = (json["servers"] as? [[String: Any]]) ?? []
        return rawServers.compactMap { entry -> MCPConnectorItem? in
            let serverObj = (entry["server"] as? [String: Any]) ?? entry
            guard let rawName = (serverObj["name"] as? String) ?? (serverObj["id"] as? String) else {
                return nil
            }
            let desc = (serverObj["description"] as? String) ?? "Official MCP Registry server"
            var remoteURL: String? = nil
            if let remotes = serverObj["remotes"] as? [[String: Any]],
               let firstRemote = remotes.first {
                remoteURL = firstRemote["url"] as? String
            }
            let shortTitle = rawName.split(separator: "/").last.map(String.init) ?? rawName
            return MCPConnectorItem(
                id: "registry-\(rawName.lowercased())",
                name: shortTitle,
                iconName: "puzzlepiece.extension.fill",
                category: .officialRegistry,
                summary: desc,
                serverURL: remoteURL,
                isPopular: false,
                isConnected: false
            )
        }
    }

    // MARK: - Private MAIPA-G-data Sync (Answer 16)

    public func syncWorkspaceToPrivateRepo(bundle: PersistedWorkspaceBundle, owner: String, token: String) async throws {
        guard !token.isEmpty else { return }
        let fullName = "\(owner)/\(Self.privateDataRepoName)"

        do {
            _ = try await githubGET(path: "/repos/\(fullName)", token: token)
        } catch {
            let createBody: [String: Any] = [
                "name": Self.privateDataRepoName,
                "private": true,
                "auto_init": true,
                "description": "Private state storage for MAIPA-G (chats, memories, agents, workflows, settings)"
            ]
            _ = try await githubRequest(method: "POST", path: "/user/repos", token: token, bodyJSON: createBody)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let encodedData = try encoder.encode(bundle)
        let b64 = encodedData.base64EncodedString()

        var existingSha: String? = nil
        if let existingData = try? await githubGET(path: "/repos/\(fullName)/contents/workspace.json", token: token),
           let existingJSON = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            existingSha = existingJSON["sha"] as? String
        }

        var putBody: [String: Any] = [
            "message": "MAIPA-G sync workspace state [skip ci]",
            "content": b64,
            "committer": [
                "name": "MAIPA-G",
                "email": "maipa-g@users.noreply.github.com"
            ]
        ]
        if let sha = existingSha {
            putBody["sha"] = sha
        }
        _ = try await githubRequest(method: "PUT", path: "/repos/\(fullName)/contents/workspace.json", token: token, bodyJSON: putBody)
    }

    public func loadWorkspaceFromPrivateRepo(owner: String, token: String) async throws -> PersistedWorkspaceBundle? {
        guard !token.isEmpty else { return nil }
        let fullName = "\(owner)/\(Self.privateDataRepoName)"
        guard let text = try? await fetchFileContent(fullName: fullName, path: "workspace.json", branch: "main", token: token),
              let data = text.data(using: .utf8) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PersistedWorkspaceBundle.self, from: data)
    }

    // MARK: - Check Latest MAIPA-G Build (Settings update check)

    public func fetchLatestMAIPAGRelease(token: String? = nil) async throws -> GitHubBuildReleaseInfo? {
        guard let data = try? await githubGET(path: "/repos/\(Self.maipaGRepoFullName)/releases/latest", token: token),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let htmlURL = json["html_url"] as? String else {
            return nil
        }
        let title = (json["name"] as? String) ?? tagName
        let publishedAt = json["published_at"] as? String
        let ipaURL = "https://github.com/\(Self.maipaGRepoFullName)/releases/latest/download/MAIPA-G.ipa"
        return GitHubBuildReleaseInfo(
            tagName: tagName,
            title: title,
            htmlURL: htmlURL,
            ipaDownloadURL: ipaURL,
            publishedAt: publishedAt
        )
    }

    // MARK: - Internal HTTP Helpers

    private func githubGET(path: String, token: String?) async throws -> Data {
        return try await githubRequest(method: "GET", path: path, token: token, bodyJSON: nil)
    }

    private func githubRequest(method: String, path: String, token: String?, bodyJSON: [String: Any]?) async throws -> Data {
        let urlString = path.hasPrefix("http") ? path : "https://api.github.com\(path)"
        guard let url = URL(string: urlString) else {
            throw GitHubServiceError.invalidURL(urlString)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MAIPA-G-iOS/1.0", forHTTPHeaderField: "User-Agent")
        if let token = token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let bodyJSON = bodyJSON {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: bodyJSON)
        }

        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubServiceError.httpError(status, body)
        }
        return data
    }
}
