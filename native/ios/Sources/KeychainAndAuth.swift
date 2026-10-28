import Foundation
import Security
import AuthenticationServices
import UIKit
import AgentCore

// MARK: - Keychain Helper

public enum KeychainHelper {
    private static let serviceName = "dev.maipag.app.keychain"

    public static func saveString(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    public static func readString(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public static func deleteValue(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - On-Phone GitHub App RS256 JWT Signer (Answer 2c — Security.framework)

public enum GitHubAppRS256Signer {
    public static func createJWT(appId: Int, pemPrivateKey: String) throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let headerDict: [String: Any] = ["alg": "RS256", "typ": "JWT"]
        let payloadDict: [String: Any] = [
            "iat": now - 60,
            "exp": now + 540,
            "iss": "\(appId)"
        ]
        let headerB64 = PKCEHelper.base64URLEncode(try JSONSerialization.data(withJSONObject: headerDict))
        let payloadB64 = PKCEHelper.base64URLEncode(try JSONSerialization.data(withJSONObject: payloadDict))
        let signingInput = "\(headerB64).\(payloadB64)"

        let derData = try stripPEMHeaders(pem: pemPrivateKey)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(derData as CFData, attributes as CFDictionary, &error) else {
            throw NSError(domain: "GitHubAppRS256Signer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid RSA private key PEM"])
        }
        guard let signatureCF = SecKeyCreateSignature(
            secKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            Data(signingInput.utf8) as CFData,
            &error
        ) else {
            throw NSError(domain: "GitHubAppRS256Signer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to sign RS256 JWT"])
        }
        let sigB64 = PKCEHelper.base64URLEncode(signatureCF as Data)
        return "\(signingInput).\(sigB64)"
    }

    private static func stripPEMHeaders(pem: String) throws -> Data {
        let lines = pem
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("-----BEGIN") && !$0.hasPrefix("-----END") }
        let b64 = lines.joined()
        guard let data = Data(base64Encoded: b64) else {
            throw NSError(domain: "GitHubAppRS256Signer", code: -3, userInfo: [NSLocalizedDescriptionKey: "Could not decode PEM base64"])
        }
        return data
    }
}

// MARK: - Web Authentication Session Presenter (OpenRouter PKCE & GitHub Manifest)

@MainActor
public final class WebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    public static let shared = WebAuthCoordinator()
    private var currentSession: ASWebAuthenticationSession?

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return keyWindow
        }
        if let firstScene = scenes.first {
            return ASPresentationAnchor(windowScene: firstScene)
        }
        return ASPresentationAnchor()
    }

    public func startWebAuth(url: URL, callbackScheme: String = "maipag") async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                self.currentSession = nil
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let callbackURL = callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: URLError(.cancelled))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.currentSession = session
            session.start()
        }
    }
}
