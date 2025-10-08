import Foundation
import Security

/// Manages a persistent device identifier stored in the keychain.
class DeviceIdentifier {
    static let shared = DeviceIdentifier()

    private let service = "com.jacobparty.deviceid"
    private let account = "device-uuid"

    private init() {}

    /// Get or create device UUID (persists across app reinstalls if backed up)
    var uuid: String {
        // Try to load existing UUID from keychain
        if let existingUUID = loadFromKeychain() {
            return existingUUID
        }

        // Generate new UUID and save to keychain
        let newUUID = UUID().uuidString
        saveToKeychain(newUUID)
        print("🔑 Generated new device UUID: \(newUUID)")
        return newUUID
    }

    private func loadFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let uuid = String(data: data, encoding: .utf8) else {
            return nil
        }

        return uuid
    }

    private func saveToKeychain(_ uuid: String) {
        guard let data = uuid.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        // Delete any existing item
        SecItemDelete(query as CFDictionary)

        // Add new item
        SecItemAdd(query as CFDictionary, nil)
    }
}
