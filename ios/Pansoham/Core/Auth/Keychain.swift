//
//  Keychain.swift
//  판서함
//
//  로그인 토큰처럼 기기에만 안전하게 남겨야 하는 글자를 Keychain에 저장 · 읽기 · 삭제해요.
//  UserDefaults는 암호화되지 않아서 토큰을 두지 않아요.
//

import Foundation
import Security

enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "pansoham"

    private static func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    static func read(_ key: String) -> String? {
        var query = query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 같은 키가 있으면 바꿔 써요. 이 기기에서만, 처음 잠금 해제 뒤부터 읽을 수 있어요 (백업으로 다른 기기에 옮겨지지 않게).
    @discardableResult
    static func save(_ value: String, for key: String) -> Bool {
        delete(key)
        var query = query(key)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}
