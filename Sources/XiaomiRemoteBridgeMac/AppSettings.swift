import Combine
import Foundation

enum MacDeviceProfile: String, CaseIterable, Identifiable {
    case xiaomiRC003 = "xiaomi-rc003"
    case djiMic2 = "dji-mic-2"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .xiaomiRC003:
            return "小米蓝牙语音遥控器"
        case .djiMic2:
            return "DJI Mic 2"
        }
    }

    var shortName: String {
        switch self {
        case .xiaomiRC003: return "RC003"
        case .djiMic2: return "DJI Mic 2"
        }
    }
}

enum XiaomiRemoteVariant: String, CaseIterable, Identifiable {
    case rc003Pro = "xiaomi-rc003-pro"
    case arn9 = "xiaomi-arn9"

    var id: String { rawValue }

    static func detected(fromModelNumber modelNumber: String) -> Self? {
        switch modelNumber
            .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
            .uppercased()
        {
        case "RC003": return .rc003Pro
        case "ARN9": return .arn9
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .rc003Pro: return "小米蓝牙语音遥控器 2 Pro"
        case .arn9: return "小米蓝牙语音遥控器（普通款）"
        }
    }

    var shortName: String {
        switch self {
        case .rc003Pro: return "2 Pro"
        case .arn9: return "普通款 ARN9"
        }
    }

    var imageResourceName: String {
        switch self {
        case .rc003Pro: return "RC003-remote-photo"
        case .arn9: return "ARN9-remote-photo"
        }
    }

    var mappableButtons: [RemoteButton] {
        switch self {
        case .rc003Pro:
            return RemoteButton.allCases
        case .arn9:
            return RemoteButton.allCases.filter { $0 != .tv }
        }
    }
}

struct ApplicationKeymap: Codable, Equatable, Identifiable {
    let bundleIdentifier: String
    var displayName: String
    var overrides: [String: ButtonBinding] = [:]
    var isEnabled: Bool = true

    init(bundleIdentifier: String, displayName: String, overrides: [String: ButtonBinding] = [:], isEnabled: Bool = true) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.overrides = overrides
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier, displayName, overrides, isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        displayName = try container.decode(String.self, forKey: .displayName)
        overrides = try container.decodeIfPresent([String: ButtonBinding].self, forKey: .overrides) ?? [:]
        // Profiles saved before the individual switch was added stay active.
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    var id: String { bundleIdentifier }
}

final class AppSettings: ObservableObject {
    private enum Keys {
        static let selectedDeviceProfile = "selectedDeviceProfile"
        static let xiaomiRemoteVariant = "xiaomiRemoteVariant"
        static let gainDB = "gainDB"
        static let selectedAudioDeviceUID = "selectedAudioDeviceUID"
        static let customMappingEnabled = "customMappingEnabled"
        static let legacyExclusiveHID = "exclusiveHID"
        static let buttonBindings = "buttonBindings"
        static let buttonBindingsV2 = "buttonBindingsV2"
        static let peripheralIdentifier = "peripheralIdentifier"
        static let localFnMicEnabled = "localFnMicEnabled"
        static let localMicInputUID = "localMicInputUID"
        static let doubleClickToggleEnabled = "doubleClickToggleEnabled"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
        static let applicationKeymaps = "applicationKeymapsV1"
        static let automaticallySwitchApplicationKeymaps = "automaticallySwitchApplicationKeymaps"
    }

    private let defaults: UserDefaults
    private(set) var mappingRevision: UInt64 = 0

    @Published var automaticallySwitchApplicationKeymaps: Bool {
        didSet {
            defaults.set(automaticallySwitchApplicationKeymaps, forKey: Keys.automaticallySwitchApplicationKeymaps)
            mappingRevision &+= 1
        }
    }

    @Published private(set) var applicationKeymaps: [ApplicationKeymap] {
        didSet {
            if let data = try? JSONEncoder().encode(applicationKeymaps) {
                defaults.set(data, forKey: Keys.applicationKeymaps)
            }
            mappingRevision &+= 1
        }
    }

    @Published var selectedDeviceProfile: MacDeviceProfile {
        didSet { defaults.set(selectedDeviceProfile.rawValue, forKey: Keys.selectedDeviceProfile) }
    }

    @Published var xiaomiRemoteVariant: XiaomiRemoteVariant {
        didSet { defaults.set(xiaomiRemoteVariant.rawValue, forKey: Keys.xiaomiRemoteVariant) }
    }

    @Published var gainDB: Double {
        didSet { defaults.set(gainDB, forKey: Keys.gainDB) }
    }

    @Published var selectedAudioDeviceUID: String {
        didSet { defaults.set(selectedAudioDeviceUID, forKey: Keys.selectedAudioDeviceUID) }
    }

    @Published var customMappingEnabled: Bool {
        didSet { defaults.set(customMappingEnabled, forKey: Keys.customMappingEnabled) }
    }

    /// On by default for a new profile, but an explicit opt-out is persisted and
    /// respected across upgrades. Enabling the preference alone never starts
    /// capture: the physical Fn edge, TCC grants, audio-loop gate, and RC003
    /// priority still have to admit a live session.
    @Published var localFnMicEnabled: Bool {
        didSet { defaults.set(localFnMicEnabled, forKey: Keys.localFnMicEnabled) }
    }

    /// Empty string means "follow the system default input device".
    @Published var localMicInputUID: String {
        didSet { defaults.set(localMicInputUID, forKey: Keys.localMicInputUID) }
    }

    /// Whether the RC003 voice-key double-click toggles the bridge runtime on/off.
    /// On by default; this only governs gesture recognition. The runtime
    /// enabled/disabled state itself is intentionally NOT persisted (the app
    /// always starts enabled), and the explicit Settings/menu button works even
    /// when this is off.
    @Published var doubleClickToggleEnabled: Bool {
        didSet { defaults.set(doubleClickToggleEnabled, forKey: Keys.doubleClickToggleEnabled) }
    }

    /// Desired login-item state. On by default so the bridge is available after
    /// a restart; the platform manager reports whether the OS accepted it.
    @Published var launchAtLoginEnabled: Bool {
        didSet { defaults.set(launchAtLoginEnabled, forKey: Keys.launchAtLoginEnabled) }
    }

    @Published var buttonBindings: [RemoteButton: ButtonBinding] {
        didSet {
            saveBindings()
            mappingRevision &+= 1
        }
    }

    var peripheralIdentifier: UUID? {
        get {
            guard let raw = defaults.string(forKey: Keys.peripheralIdentifier) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            defaults.set(newValue?.uuidString, forKey: Keys.peripheralIdentifier)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automaticallySwitchApplicationKeymaps = defaults.object(forKey: Keys.automaticallySwitchApplicationKeymaps) == nil
            ? true : defaults.bool(forKey: Keys.automaticallySwitchApplicationKeymaps)
        if let data = defaults.data(forKey: Keys.applicationKeymaps),
           let decoded = try? JSONDecoder().decode([ApplicationKeymap].self, from: data) {
            var seen = Set<String>()
            applicationKeymaps = decoded.compactMap { profile in
                guard !profile.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      seen.insert(profile.bundleIdentifier).inserted else { return nil }
                var profile = profile
                profile.overrides = profile.overrides.filter { key, binding in
                    guard let button = RemoteButton(rawValue: key), button != .microphone else { return false }
                    switch binding {
                    case .hardwareFn: return false
                    case let .shortcut(chord): return chord.isValid
                    case .preset: return true
                    }
                }
                return profile
            }
        } else {
            applicationKeymaps = []
        }
        selectedDeviceProfile = MacDeviceProfile(
            rawValue: defaults.string(forKey: Keys.selectedDeviceProfile) ?? ""
        ) ?? .xiaomiRC003
        xiaomiRemoteVariant = XiaomiRemoteVariant(
            rawValue: defaults.string(forKey: Keys.xiaomiRemoteVariant) ?? ""
        ) ?? .rc003Pro
        gainDB = defaults.object(forKey: Keys.gainDB) == nil
            ? 10.0
            : defaults.double(forKey: Keys.gainDB)
        selectedAudioDeviceUID = defaults.string(forKey: Keys.selectedAudioDeviceUID) ?? ""
        if defaults.object(forKey: Keys.customMappingEnabled) != nil {
            customMappingEnabled = defaults.bool(forKey: Keys.customMappingEnabled)
        } else {
            customMappingEnabled = defaults.bool(forKey: Keys.legacyExclusiveHID)
        }
        localFnMicEnabled = defaults.object(forKey: Keys.localFnMicEnabled) == nil
            ? true
            : defaults.bool(forKey: Keys.localFnMicEnabled)
        localMicInputUID = defaults.string(forKey: Keys.localMicInputUID) ?? ""
        doubleClickToggleEnabled = defaults.object(forKey: Keys.doubleClickToggleEnabled) == nil
            ? true
            : defaults.bool(forKey: Keys.doubleClickToggleEnabled)
        launchAtLoginEnabled = defaults.object(forKey: Keys.launchAtLoginEnabled) == nil
            ? true
            : defaults.bool(forKey: Keys.launchAtLoginEnabled)
        if let data = defaults.data(forKey: Keys.buttonBindingsV2),
           let decoded = try? JSONDecoder().decode([String: ButtonBinding].self, from: data) {
            buttonBindings = Self.defaultBindings.merging(
                Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                    RemoteButton(rawValue: key).map { ($0, value) }
                })
            ) { _, saved in saved }
        } else if let data = defaults.data(forKey: Keys.buttonBindings),
                  let decoded = try? JSONDecoder().decode([String: ButtonAction].self, from: data) {
            buttonBindings = Self.defaultBindings.merging(
                Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                    RemoteButton(rawValue: key).map { ($0, .preset(value)) }
                })
            ) { _, saved in saved }
        } else {
            buttonBindings = Self.defaultBindings
        }
    }

    func binding(for button: RemoteButton) -> ButtonBinding {
        buttonBindings[button] ?? .preset(.disabled)
    }

    /// Only ordinary HID actions consult the foreground application. Voice
    /// callers continue to use the global lookup above for the entire hold.
    func binding(for button: RemoteButton, applicationBundleIdentifier: String?) -> ButtonBinding {
        if automaticallySwitchApplicationKeymaps,
           applicationKeymap(for: applicationBundleIdentifier)?.isEnabled == true,
           let override = applicationOverride(for: button, bundleIdentifier: applicationBundleIdentifier) {
            return override
        }
        return binding(for: button)
    }

    func applicationKeymap(for bundleIdentifier: String?) -> ApplicationKeymap? {
        guard let bundleIdentifier else { return nil }
        return applicationKeymaps.first { $0.bundleIdentifier == bundleIdentifier }
    }

    func applicationOverride(for button: RemoteButton, bundleIdentifier: String?) -> ButtonBinding? {
        guard button != .microphone else { return nil }
        return applicationKeymap(for: bundleIdentifier)?.overrides[button.rawValue]
    }

    @discardableResult
    func addApplicationKeymap(bundleIdentifier: String, displayName: String) -> Bool {
        guard !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard applicationKeymap(for: bundleIdentifier) == nil else { return true }
        applicationKeymaps.append(ApplicationKeymap(bundleIdentifier: bundleIdentifier, displayName: displayName))
        return true
    }

    func setApplicationOverride(_ binding: ButtonBinding?, for button: RemoteButton, bundleIdentifier: String) {
        guard button != .microphone,
              let index = applicationKeymaps.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier })
        else { return }
        if let binding {
            switch binding {
            case .hardwareFn: return
            case let .shortcut(chord): guard chord.isValid else { return }
            case .preset: break
            }
        }
        applicationKeymaps[index].overrides[button.rawValue] = binding
    }

    func setApplicationKeymapEnabled(_ enabled: Bool, bundleIdentifier: String) {
        guard let index = applicationKeymaps.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }),
              applicationKeymaps[index].isEnabled != enabled else { return }
        applicationKeymaps[index].isEnabled = enabled
    }

    func clearApplicationOverrides(bundleIdentifier: String) {
        guard let index = applicationKeymaps.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) else { return }
        applicationKeymaps[index].overrides = [:]
    }

    func removeApplicationKeymap(bundleIdentifier: String) {
        applicationKeymaps.removeAll { $0.bundleIdentifier == bundleIdentifier }
    }

    func action(for button: RemoteButton) -> ButtonAction {
        guard case let .preset(action) = binding(for: button) else { return .disabled }
        return action
    }

    func setBinding(_ binding: ButtonBinding, for button: RemoteButton) {
        buttonBindings[button] = binding
    }

    func setAction(_ action: ButtonAction, for button: RemoteButton) {
        setBinding(.preset(action), for: button)
    }

    func resetBindings() {
        buttonBindings = Self.defaultBindings
    }

    private func saveBindings() {
        let raw = Dictionary(uniqueKeysWithValues: buttonBindings.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Keys.buttonBindingsV2)
        }
    }

    static let defaultBindings: [RemoteButton: ButtonBinding] = [
        .microphone: .hardwareFn,
        .power: .preset(.escape),
        .up: .preset(.arrowUp),
        .left: .preset(.arrowLeft),
        .ok: .preset(.returnKey),
        .right: .preset(.arrowRight),
        .down: .preset(.arrowDown),
        .back: .preset(.deleteBackward),
        .volumeUp: .preset(.volumeUp),
        .home: .preset(.showDesktop),
        .volumeDown: .preset(.volumeDown),
        .menu: .preset(.contextMenu),
        .tv: .preset(.appSwitcher),
    ]
}
