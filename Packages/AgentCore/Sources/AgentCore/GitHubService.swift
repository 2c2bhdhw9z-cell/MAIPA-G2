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

    public func fetchRepositories(token: String?, fallbackOwner: String = "2c2bhdhw9z-cell") async throws -> [GitHubRepo] {
        let path: String
        if let token = token, !token.isEmpty {
            path = "/user/repos?sort=updated&per_page=100&affiliation=owner,collaborator"
        } else {
            path = "/users/\(fallbackOwner)/repos?sort=updated&per_page=100"
        }
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

        // First match filenames and text files up to a reasonable count so it works even on unindexed branches
        var results: [(path: String, line: Int, snippet: String)] = []
        let candidateFiles = tree.filter { item in
            guard item.type == "blob", (item.size ?? 0) < 120_000 else { return false }
            let ext = (item.path as NSString).pathExtension.lowercased()
            let textExts: Set<String> = ["swift", "md", "yml", "yaml", "json", "sh", "py", "ts", "tsx", "js", "rs", "c", "h", "cpp", "txt", "plist", "entitlements", "html", "css"]
            return textExts.contains(ext) || item.path.lowercased().contains(lowerQuery)
        }

        // Prioritize files whose path matches or important project files
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

    // MARK: - Private MAIPA-G-data Sync (Answer 16)

    public func syncWorkspaceToPrivateRepo(bundle: PersistedWorkspaceBundle, owner: String, token: String) async throws {
        guard !token.isEmpty else { return }
        let fullName = "\(owner)/\(Self.privateDataRepoName)"

        // Ensure private repo exists
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
