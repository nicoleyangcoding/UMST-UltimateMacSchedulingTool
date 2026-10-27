import Foundation
import Security

// Everything secret (calendar feed links, API tokens) lives in the macOS Keychain, never in files on disk.
enum Keychain {
    private static let service = "com.umst.app.sources"

    static func set(_ value: String, for account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly   // never synced or backed up off this Mac
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete(_ account: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}

enum Safe {
    /// Network session with no cookies, no disk cache, no credential storage.
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.urlCache = nil
        c.urlCredentialStorage = nil
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 40
        c.httpAdditionalHeaders = ["User-Agent": "UMST/0.1"]
        return URLSession(configuration: c)
    }()

    static let maxDownload = 15 * 1024 * 1024

    /// Only https URLs with a real host are allowed out. webcal:// is treated as https.
    static func httpsURL(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("webcal://") { s = "https://" + s.dropFirst(9) }
        guard let u = URL(string: s), u.scheme?.lowercased() == "https",
              let h = u.host, h.contains("."), u.user == nil, u.password == nil else { return nil }
        return u
    }

    static func fetch(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        guard data.count <= maxDownload else { throw URLError(.dataLengthExceedsMaximum) }
        return data
    }

    /// Data files are readable by this user only.
    static func lockDown(_ url: URL, directory: Bool = false) {
        try? FileManager.default.setAttributes([.posixPermissions: directory ? 0o700 : 0o600], ofItemAtPath: url.path)
    }

    static func write(_ data: Data, to url: URL) {
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
        lockDown(url)
    }
}
