import Foundation
import Security

final class ShortcutBox: @unchecked Sendable {
    private let lock = NSLock()
    private var shortcuts = ShortcutMap.default
    private var rebind: ShortcutAction?

    func snapshot() -> (ShortcutMap, ShortcutAction?) {
        lock.lock()
        defer { lock.unlock() }
        return (shortcuts, rebind)
    }

    func updateShortcuts(_ shortcuts: ShortcutMap) {
        lock.lock()
        self.shortcuts = shortcuts
        lock.unlock()
    }

    func updateRebind(_ action: ShortcutAction?) {
        lock.lock()
        rebind = action
        lock.unlock()
    }
}

enum ShortcutSync {
    static let box = ShortcutBox()
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    /// Bump when the built-in shortcut map changes so a saved Fn binding cannot linger.
    static let shortcutsVersion = 2
    private let defaults = UserDefaults.standard

    var mode: TranscriptionMode {
        didSet { defaults.set(mode.rawValue, forKey: Keys.mode) }
    }

    var autoPaste: Bool {
        didSet { defaults.set(autoPaste, forKey: Keys.autoPaste) }
    }

    var soundsEnabled: Bool {
        didSet { defaults.set(soundsEnabled, forKey: Keys.sounds) }
    }

    var model: String {
        didSet { defaults.set(model, forKey: Keys.model) }
    }

    var shortcuts: ShortcutMap {
        didSet {
            if let data = try? JSONEncoder().encode(shortcuts) {
                defaults.set(data, forKey: Keys.shortcuts)
            }
            ShortcutSync.box.updateShortcuts(shortcuts)
        }
    }

    var hasAPIKey: Bool

    private init() {
        let storedMode = defaults.string(forKey: Keys.mode) ?? TranscriptionMode.cleaned.rawValue
        mode = TranscriptionMode(rawValue: storedMode) ?? .cleaned
        autoPaste = defaults.object(forKey: Keys.autoPaste) == nil ? true : defaults.bool(forKey: Keys.autoPaste)
        soundsEnabled = defaults.object(forKey: Keys.sounds) == nil ? true : defaults.bool(forKey: Keys.sounds)
        let storedModel = defaults.string(forKey: Keys.model) ?? CleanupPrompt.defaultModel
        model = storedModel.isEmpty ? CleanupPrompt.defaultModel : storedModel
        let storedVersion = defaults.integer(forKey: Keys.shortcutsVersion)
        if storedVersion >= Self.shortcutsVersion,
           let data = defaults.data(forKey: Keys.shortcuts),
           let decoded = try? JSONDecoder().decode(ShortcutMap.self, from: data) {
            shortcuts = decoded
        } else {
            shortcuts = .default
            if let data = try? JSONEncoder().encode(ShortcutMap.default) {
                defaults.set(data, forKey: Keys.shortcuts)
            }
            defaults.set(Self.shortcutsVersion, forKey: Keys.shortcutsVersion)
        }
        hasAPIKey = KeychainStore.load() != nil
        ShortcutSync.box.updateShortcuts(shortcuts)
    }

    func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete()
            hasAPIKey = false
            return
        }
        try KeychainStore.save(trimmed)
        hasAPIKey = true
    }

    func clearAPIKey() {
        KeychainStore.delete()
        hasAPIKey = false
    }

    private enum Keys {
        static let mode = "mode"
        static let autoPaste = "autoPaste"
        static let sounds = "soundsEnabled"
        static let model = "model"
        static let shortcuts = "shortcuts"
        static let shortcutsVersion = "shortcutsVersion"
    }
}

enum KeychainStore {
    private static let service = "app.voicenotes.local"
    private static let account = "openai-api-key"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) throws {
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DictationError.keychain("Couldn't save the API key (\(status)).")
        }
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
