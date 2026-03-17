import Foundation
import KeychainAccess

/// Service for secure storage of sensitive data using the system Keychain
@MainActor
final class KeychainService: ObservableObject {
    static let shared = KeychainService()

    private let keychain: Keychain

    // Keychain keys
    private enum Keys {
        static let anthropicAPIKey = "anthropic_api_key"
        static let syncAuthToken = "sync_auth_token"
    }

    private init() {
        // Use app bundle identifier as service name for keychain
        let serviceName = Bundle.main.bundleIdentifier ?? "com.pedef.app"
        keychain = Keychain(service: serviceName)
            .accessibility(.whenUnlocked)
    }

    // MARK: - Anthropic API Key

    /// The stored Anthropic API key, or nil if not set
    var anthropicAPIKey: String? {
        get {
            do {
                return try keychain.get(Keys.anthropicAPIKey)
            } catch {
                print("Failed to retrieve API key from Keychain: \(error)")
                return nil
            }
        }
        set {
            do {
                if let newValue = newValue, !newValue.isEmpty {
                    try keychain.set(newValue, key: Keys.anthropicAPIKey)
                } else {
                    try keychain.remove(Keys.anthropicAPIKey)
                }
                objectWillChange.send()
            } catch {
                print("Failed to store API key in Keychain: \(error)")
            }
        }
    }

    /// Check if an API key is configured (either in Keychain or environment)
    var hasAPIKey: Bool {
        getEffectiveAPIKey() != nil
    }

    /// Get the effective API key, preferring Keychain over environment variable
    func getEffectiveAPIKey() -> String? {
        // First check Keychain
        if let keychainKey = anthropicAPIKey, !keychainKey.isEmpty {
            return keychainKey
        }

        // Fall back to environment variable
        return ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
    }

    /// Clear the stored API key
    func clearAPIKey() {
        anthropicAPIKey = nil
    }

    /// Validate that an API key looks correct (basic format check)
    nonisolated static func isValidAPIKeyFormat(_ key: String) -> Bool {
        // Anthropic API keys start with "sk-ant-" and are fairly long
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("sk-ant-") && trimmed.count > 20
    }

    // MARK: - Sync Auth Token

    /// The stored sync authentication token, or nil if not set
    var syncAuthToken: String? {
        get {
            do {
                return try keychain.get(Keys.syncAuthToken)
            } catch {
                print("Failed to retrieve sync auth token from Keychain: \(error)")
                return nil
            }
        }
        set {
            do {
                if let newValue = newValue, !newValue.isEmpty {
                    try keychain.set(newValue, key: Keys.syncAuthToken)
                } else {
                    try keychain.remove(Keys.syncAuthToken)
                }
                objectWillChange.send()
            } catch {
                print("Failed to store sync auth token in Keychain: \(error)")
            }
        }
    }

    /// Check if a sync auth token is configured
    var hasSyncAuthToken: Bool {
        if let token = syncAuthToken, !token.isEmpty {
            return true
        }
        return false
    }

    /// Clear the stored sync auth token
    func clearSyncAuthToken() {
        syncAuthToken = nil
    }
}
