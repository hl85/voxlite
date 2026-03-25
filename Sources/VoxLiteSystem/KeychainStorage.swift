import Foundation
import Security
import VoxLiteDomain

public enum KeychainError: Error, Equatable {
    case unhandledStatus(OSStatus)
    case dataConversionFailed
}

extension KeychainError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String?
            return "Keychain operation failed: \(message ?? "Unknown error \(status)")"
        case .dataConversionFailed:
            return "Failed to convert data to string"
        }
    }
}

public final class KeychainStorage: KeychainStoring, Sendable {
    private let service: String

    public init(service: String = "ai.holoo.voxlite.apikeys") {
        self.service = service
    }

    public func store(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        try delete(forKey: key)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    public func retrieve(forKey key: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: kCFBooleanTrue!,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }

        guard let data = result as? Data else {
            return nil
        }

        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        return string
    }

    public func delete(forKey key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }
}

public extension KeychainStorage {
    func storeAPIKey(_ apiKey: String, for provider: RemoteProvider) throws {
        try store(apiKey, forKey: provider.rawValue)
    }

    func retrieveAPIKey(for provider: RemoteProvider) throws -> String? {
        try retrieve(forKey: provider.rawValue)
    }

    func deleteAPIKey(for provider: RemoteProvider) throws {
        try delete(forKey: provider.rawValue)
    }
}
