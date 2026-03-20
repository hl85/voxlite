import Foundation

public final class HotKeySettings: ObservableObject {
    private static let userDefaultsKey = "com.voxlite.hotkey.configuration"

    @Published public var configuration: HotKeyConfiguration {
        didSet {
            save()
        }
    }
    @Published public var hasConflict: Bool = false
    @Published public var conflictMessage: String = ""

    public init() {
        if let saved = Self.load() {
            self.configuration = saved
        } else {
            self.configuration = .defaultConfiguration
        }
    }

    public func updateConfiguration(_ newConfig: HotKeyConfiguration) {
        configuration = newConfig
    }

    public func resetToDefault() {
        configuration = .defaultConfiguration
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(encoded, forKey: Self.userDefaultsKey)
        }
    }

    private static func load() -> HotKeyConfiguration? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode(HotKeyConfiguration.self, from: data) else {
            return nil
        }
        return decoded
    }

    public func checkForConflicts() -> (hasConflict: Bool, message: String) {
        let config = configuration
        if config.keyCode == HotKeyConfiguration.fnKeyCode {
            return (false, "")
        }

        let registeredHotKeys = fetchSystemRegisteredHotKeys()

        for registered in registeredHotKeys {
            if registered.keyCode == config.keyCode && registered.modifiers == config.modifiers {
                return (true, "此快捷键已被系统或其他应用占用")
            }
        }

        return (false, "")
    }

    private func fetchSystemRegisteredHotKeys() -> [HotKeyConfiguration] {
        return []
    }
}
