import AppKit
import Foundation
import Testing
@testable import XiaomiRemoteBridgeMac

@Suite("Application keymaps")
struct ApplicationKeymapTests {
    private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) throws {
        let name = "ApplicationKeymapTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(AppSettings(defaults: defaults), defaults)
    }

    @Test func applicationOverridesInheritLiveDefaultsAndStayIndependent() throws {
        try withSettings { settings, _ in
            settings.addApplicationKeymap(bundleIdentifier: "example.player", displayName: "Player")
            settings.addApplicationKeymap(bundleIdentifier: "example.browser", displayName: "Browser")
            let space = ButtonBinding.shortcut(KeyChord(keyCode: 49, keyLabel: "Space", modifiers: []))
            settings.setApplicationOverride(space, for: .ok, bundleIdentifier: "example.player")
            settings.setBinding(.preset(.disabled), for: .up)

            #expect(settings.binding(for: .ok, applicationBundleIdentifier: "example.player") == space)
            #expect(settings.binding(for: .ok, applicationBundleIdentifier: "example.browser") == .preset(.returnKey))
            #expect(settings.binding(for: .up, applicationBundleIdentifier: "example.player") == .preset(.disabled))
            #expect(settings.binding(for: .up, applicationBundleIdentifier: "example.browser") == .preset(.disabled))
            #expect(settings.binding(for: .ok) == .preset(.returnKey))
        }
    }

    @Test func explicitDisabledBindingDoesNotFallBackAndCanBeCleared() throws {
        try withSettings { settings, _ in
            settings.addApplicationKeymap(bundleIdentifier: "example.player", displayName: "Player")
            settings.setApplicationOverride(.preset(.disabled), for: .back, bundleIdentifier: "example.player")
            #expect(settings.binding(for: .back, applicationBundleIdentifier: "example.player") == .preset(.disabled))
            settings.setApplicationOverride(nil, for: .back, bundleIdentifier: "example.player")
            #expect(settings.binding(for: .back, applicationBundleIdentifier: "example.player") == .preset(.deleteBackward))
        }
    }

    @Test func missingApplicationAndDisabledAutomaticMatchingUseGlobalBindings() throws {
        try withSettings { settings, defaults in
            settings.addApplicationKeymap(bundleIdentifier: "example.player", displayName: "Player")
            settings.setApplicationOverride(.preset(.escape), for: .ok, bundleIdentifier: "example.player")
            #expect(settings.binding(for: .ok, applicationBundleIdentifier: nil) == .preset(.returnKey))
            #expect(settings.binding(for: .ok, applicationBundleIdentifier: "example.unknown") == .preset(.returnKey))
            settings.automaticallySwitchApplicationKeymaps = false
            #expect(settings.binding(for: .ok, applicationBundleIdentifier: "example.player") == .preset(.returnKey))
            #expect(settings.applicationOverride(for: .ok, bundleIdentifier: "example.player") == .preset(.escape))
            let restored = AppSettings(defaults: defaults)
            #expect(!restored.automaticallySwitchApplicationKeymaps)
            restored.automaticallySwitchApplicationKeymaps = true
            #expect(restored.binding(for: .ok, applicationBundleIdentifier: "example.player") == .preset(.escape))
        }
    }

    @Test func persistedProfilesDoNotReplaceExistingGlobalConfiguration() throws {
        try withSettings { settings, defaults in
            let chord = ButtonBinding.shortcut(KeyChord(keyCode: 35, keyLabel: "P", modifiers: [.command]))
            settings.setBinding(.preset(.mouseRightClick), for: .menu)
            settings.addApplicationKeymap(bundleIdentifier: "example.editor", displayName: "Editor")
            settings.setApplicationOverride(chord, for: .ok, bundleIdentifier: "example.editor")
            let restored = AppSettings(defaults: defaults)
            #expect(restored.applicationKeymaps.count == 1)
            #expect(restored.applicationKeymaps.first?.displayName == "Editor")
            #expect(restored.binding(for: .menu) == .preset(.mouseRightClick))
            #expect(restored.binding(for: .menu, applicationBundleIdentifier: "example.editor") == .preset(.mouseRightClick))
            #expect(restored.binding(for: .ok, applicationBundleIdentifier: "example.editor") == chord)
        }
    }

    @Test func olderSavedGlobalBindingsRemainUsableWithoutApplicationProfiles() throws {
        try withSettings { _, defaults in
            defaults.set(try JSONEncoder().encode(["back": ButtonAction.disabled]), forKey: "buttonBindings")
            let settings = AppSettings(defaults: defaults)
            #expect(settings.applicationKeymaps.isEmpty)
            #expect(settings.binding(for: .back, applicationBundleIdentifier: "example.player") == .preset(.disabled))
            #expect(settings.binding(for: .ok, applicationBundleIdentifier: "example.player") == .preset(.returnKey))
        }
    }

    @Test func voiceBindingCannotBeOverriddenOrChangedByAnApplicationProfile() throws {
        try withSettings { settings, _ in
            let chord = ButtonBinding.shortcut(KeyChord(keyCode: 35, keyLabel: "P", modifiers: [.option]))
            settings.setBinding(chord, for: .microphone)
            settings.addApplicationKeymap(bundleIdentifier: "example.player", displayName: "Player")
            settings.setApplicationOverride(.preset(.disabled), for: .microphone, bundleIdentifier: "example.player")
            #expect(settings.applicationOverride(for: .microphone, bundleIdentifier: "example.player") == nil)
            #expect(settings.binding(for: .microphone, applicationBundleIdentifier: "example.player") == chord)
            #expect(settings.binding(for: .microphone, applicationBundleIdentifier: "example.browser") == chord)
        }
    }

    @Test func removingAndClearingAProfileRestoresDefaultsWithoutChangingOtherProfiles() throws {
        try withSettings { settings, defaults in
            for id in ["example.player", "example.editor"] {
                settings.addApplicationKeymap(bundleIdentifier: id, displayName: id)
                settings.setApplicationOverride(.preset(.escape), for: .ok, bundleIdentifier: id)
            }
            settings.clearApplicationOverrides(bundleIdentifier: "example.player")
            #expect(settings.applicationKeymaps.count == 2)
            #expect(settings.binding(for: .ok, applicationBundleIdentifier: "example.player") == .preset(.returnKey))
            #expect(settings.binding(for: .ok, applicationBundleIdentifier: "example.editor") == .preset(.escape))
            settings.removeApplicationKeymap(bundleIdentifier: "example.editor")
            #expect(settings.binding(for: .ok, applicationBundleIdentifier: "example.editor") == .preset(.returnKey))
            #expect(AppSettings(defaults: defaults).applicationKeymap(for: "example.editor") == nil)
        }
    }

    @Test func duplicateApplicationDoesNotDiscardExistingOverrides() throws {
        try withSettings { settings, _ in
            #expect(settings.addApplicationKeymap(bundleIdentifier: "example.player", displayName: "Player"))
            settings.setApplicationOverride(.preset(.disabled), for: .ok, bundleIdentifier: "example.player")
            settings.addApplicationKeymap(bundleIdentifier: "example.player", displayName: "Player again")
            #expect(settings.applicationKeymaps.count == 1)
            #expect(settings.binding(for: .ok, applicationBundleIdentifier: "example.player") == .preset(.disabled))
            #expect(!settings.addApplicationKeymap(bundleIdentifier: " \n", displayName: "Invalid"))
        }
    }

    @Test func invalidAndVoiceOverridesAreFilteredWhenLoadingProfiles() throws {
        try withSettings { _, defaults in
            let profile = ApplicationKeymap(bundleIdentifier: "example.player", displayName: "Player", overrides: [
                "microphone": .preset(.disabled), "ok": .hardwareFn,
                "back": .shortcut(KeyChord(keyCode: 500, keyLabel: "Invalid", modifiers: [])),
                "unknown": .preset(.escape), "menu": .preset(.mouseRightClick),
            ])
            defaults.set(try JSONEncoder().encode([profile, profile]), forKey: "applicationKeymapsV1")
            let settings = AppSettings(defaults: defaults)
            #expect(settings.applicationKeymaps.count == 1)
            #expect(settings.applicationKeymaps.first?.overrides == ["menu": .preset(.mouseRightClick)])
            #expect(settings.binding(for: .microphone, applicationBundleIdentifier: "example.player") == .hardwareFn)
            #expect(settings.binding(for: .ok, applicationBundleIdentifier: "example.player") == .preset(.returnKey))
        }
    }

    @Test func individualSwitchPreservesOverridesAndPersistsAcrossLaunches() throws {
        try withSettings { settings, defaults in
            for id in ["example.player", "example.editor"] {
                settings.addApplicationKeymap(bundleIdentifier: id, displayName: id)
                settings.setApplicationOverride(.preset(.escape), for: .ok, bundleIdentifier: id)
            }
            let revision = settings.mappingRevision
            settings.setApplicationKeymapEnabled(false, bundleIdentifier: "example.player")
            #expect(settings.mappingRevision != revision)
            #expect(settings.binding(for: .ok, applicationBundleIdentifier: "example.player") == .preset(.returnKey))
            #expect(settings.applicationOverride(for: .ok, bundleIdentifier: "example.player") == .preset(.escape))
            #expect(settings.binding(for: .ok, applicationBundleIdentifier: "example.editor") == .preset(.escape))
            settings.setBinding(.preset(.mouseRightClick), for: .ok)
            #expect(settings.binding(for: .ok, applicationBundleIdentifier: "example.player") == .preset(.mouseRightClick))
            let restored = AppSettings(defaults: defaults)
            #expect(restored.applicationKeymap(for: "example.player")?.isEnabled == false)
            #expect(restored.binding(for: .ok, applicationBundleIdentifier: "example.player") == .preset(.mouseRightClick))
            restored.setApplicationKeymapEnabled(true, bundleIdentifier: "example.player")
            #expect(restored.binding(for: .ok, applicationBundleIdentifier: "example.player") == .preset(.escape))
            restored.automaticallySwitchApplicationKeymaps = false
            #expect(restored.binding(for: .ok, applicationBundleIdentifier: "example.player") == .preset(.mouseRightClick))
        }
    }

    @Test func profilesSavedBeforeIndividualSwitchRemainEnabled() throws {
        try withSettings { _, defaults in
            // Build the binding with the actual codec, then omit only the new field.
            let profile = ApplicationKeymap(bundleIdentifier: "example.player", displayName: "Player", overrides: ["ok": .preset(.escape)])
            var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
            json.removeValue(forKey: "isEnabled")
            defaults.set(try JSONSerialization.data(withJSONObject: [json]), forKey: "applicationKeymapsV1")
            let restored = AppSettings(defaults: defaults)
            #expect(restored.applicationKeymap(for: "example.player")?.isEnabled == true)
            #expect(restored.binding(for: .ok, applicationBundleIdentifier: "example.player") == .preset(.escape))
        }
    }

    @Test @MainActor func activationChangesCancelOnceEvenForInstancesOfTheSameApplication() {
        let center = NotificationCenter()
        var app: ForegroundApplication? = ForegroundApplication(
            processIdentifier: 101, bundleIdentifier: "example.player", displayName: "Player"
        )
        let monitor = ForegroundApplicationMonitor(notificationCenter: center, readApplication: { app })
        var changes = 0
        monitor.onChange = { changes += 1 }
        monitor.start()
        #expect(changes == 1)
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        #expect(changes == 1)
        app = ForegroundApplication(processIdentifier: 102, bundleIdentifier: "example.player", displayName: "Player")
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        #expect(changes == 2)
        #expect(monitor.application?.processIdentifier == 102)
        app = nil
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        #expect(changes == 3)
        #expect(monitor.application == nil)
        monitor.stop()
        app = ForegroundApplication(processIdentifier: 103, bundleIdentifier: "example.browser", displayName: "Browser")
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        #expect(changes == 3)
    }
}
