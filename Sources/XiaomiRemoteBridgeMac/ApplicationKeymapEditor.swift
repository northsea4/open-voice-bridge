import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum ApplicationIconCache {
    private static let images = NSCache<NSString, NSImage>()

    static func image(for bundleIdentifier: String) -> NSImage? {
        if let image = images.object(forKey: bundleIdentifier as NSString) { return image }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        images.setObject(image, forKey: bundleIdentifier as NSString)
        return image
    }
}

struct ApplicationKeymapEditor: View {
    @ObservedObject var model: BridgeAppModel
    @ObservedObject private var settings: AppSettings
    @ObservedObject private var foreground: ForegroundApplicationMonitor
    @State private var editingBundleIdentifier: String?
    @State private var selectedButton: RemoteButton = .ok
    @State private var recordingButton: RemoteButton?
    @State private var errorMessage: String?

    init(model: BridgeAppModel) {
        self.model = model
        settings = model.settings
        foreground = model.foregroundApplicationMonitor
    }

    private var editingProfile: ApplicationKeymap? {
        settings.applicationKeymap(for: editingBundleIdentifier)
    }

    private var editingName: String { editingProfile?.displayName ?? "默认键位" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            mappingControls
            HStack(alignment: .top, spacing: 12) {
                applicationSidebar.frame(width: 154)
                Divider()
                bindingEditor.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                livePreview.frame(width: 210)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(4)
        .onChange(of: settings.xiaomiRemoteVariant) { variant in
            if !variant.mappableButtons.contains(selectedButton) { selectedButton = .ok }
        }
        .sheet(item: $recordingButton) { button in
            ShortcutRecorderView(
                button: button,
                onCancel: { recordingButton = nil },
                onClear: {
                    setBinding(.preset(.disabled), for: button)
                    recordingButton = nil
                },
                onRecord: { chord in
                    setBinding(.shortcut(chord), for: button)
                    recordingButton = nil
                }
            )
        }
        .alert(isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Alert(title: Text("无法修改键位"), message: Text(errorMessage ?? ""), dismissButton: .default(Text("好")))
        }
    }

    private var mappingControls: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Toggle("启用 \(settings.xiaomiRemoteVariant.shortName) 自定义按键映射", isOn: Binding(
                        get: { settings.customMappingEnabled },
                        set: {
                            settings.customMappingEnabled = $0
                            model.applyHIDSettings()
                        }
                    ))
                    Spacer()
                    Toggle("按前台应用自动切换键位", isOn: Binding(
                        get: { settings.automaticallySwitchApplicationKeymaps },
                        set: { model.setAutomaticApplicationKeymaps($0) }
                    ))
                }
                Text(model.hidStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("应用只覆盖单独设置的普通键，其余跟随默认。切换应用会停止旧连发，松开再按后继续。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var applicationSidebar: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("编辑键位").font(.caption).foregroundColor(.secondary)
            ScrollView {
                VStack(spacing: 5) {
                    applicationRow(nil)
                    ForEach(settings.applicationKeymaps) { profile in applicationRow(profile) }
                }
            }
            Button(action: addApplication) { Label("添加应用…", systemImage: "plus") }
            Text("选择要编辑的应用。此处的选择不会切换前台应用。")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func applicationRow(_ profile: ApplicationKeymap?) -> some View {
        let selected = editingBundleIdentifier == profile?.bundleIdentifier
        return Button {
            editingBundleIdentifier = profile?.bundleIdentifier
        } label: {
            HStack(spacing: 8) {
                if let profile, let icon = ApplicationIconCache.image(for: profile.bundleIdentifier) {
                    Image(nsImage: icon).resizable().frame(width: 26, height: 26)
                } else {
                    Image(systemName: profile == nil ? "keyboard" : "app")
                        .frame(width: 26, height: 26)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile?.displayName ?? "默认键位").font(.callout).lineLimit(2)
                    Text(profile.map { "\($0.overrides.count) 个专属键位" } ?? "其他按键的基础")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("编辑\(profile?.displayName ?? "默认键位")"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var bindingEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(editingName).font(.headline)
                Spacer(minLength: 8)
                Text("正在编辑").font(.caption).foregroundColor(.secondary)
            }
            Text(editingBundleIdentifier == nil
                 ? "修改默认键位会同步影响所有跟随默认的按键。"
                 : "未修改的键跟随默认；语音键在所有应用中保持一致。")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(settings.xiaomiRemoteVariant.mappableButtons) { button in
                            mappingRow(button).id(button.id)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .onChange(of: selectedButton) { button in
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(button.id, anchor: .center) }
                }
            }
            HStack {
                Button(editingBundleIdentifier == nil ? "恢复默认键位" : "全部跟随默认") { resetEditingProfile() }
                Spacer()
                if let editingBundleIdentifier {
                    Button("移除应用") {
                        model.removeApplicationKeymap(bundleIdentifier: editingBundleIdentifier)
                        self.editingBundleIdentifier = nil
                    }
                }
            }
        }
    }

    private func editingBinding(for button: RemoteButton) -> ButtonBinding {
        settings.applicationOverride(for: button, bundleIdentifier: editingBundleIdentifier)
            ?? settings.binding(for: button)
    }

    private func sourceLabel(for button: RemoteButton) -> String {
        if button == .microphone { return "全局语音键" }
        guard editingBundleIdentifier != nil else { return "默认" }
        return settings.applicationOverride(for: button, bundleIdentifier: editingBundleIdentifier) == nil
            ? "跟随默认" : "此应用专属"
    }

    private func mappingRow(_ button: RemoteButton) -> some View {
        let voiceIsGlobal = button == .microphone && editingBundleIdentifier != nil
        return HStack(spacing: 8) {
            Button { selectedButton = button } label: {
                HStack(spacing: 8) {
                    Text(button.shortLabel)
                        .font(.caption.weight(.semibold))
                        .frame(width: 36, height: 29)
                        .background(selectedButton == button ? Color.accentColor : Color.secondary.opacity(0.14))
                        .foregroundColor(selectedButton == button ? .white : .primary)
                        .clipShape(Capsule())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(button.displayName).font(.callout)
                        Text(sourceLabel(for: button)).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 4)
            Menu {
                if let editingBundleIdentifier, button != .microphone {
                    Button("跟随默认（\(settings.binding(for: button).displayName)）") {
                        model.inheritDefaultBinding(for: button, bundleIdentifier: editingBundleIdentifier)
                    }
                    Divider()
                }
                if button == .microphone {
                    Button("硬件 Fn（默认语音）") { setBinding(.hardwareFn, for: button) }
                    Button("禁用") { setBinding(.preset(.disabled), for: button) }
                } else {
                    ForEach(ButtonAction.allCases) { action in
                        Button(action.displayName) { setBinding(.preset(action), for: button) }
                    }
                }
                Divider()
                Button("录制自定义快捷键…") { recordingButton = button }
            } label: {
                Text(editingBinding(for: button).displayName)
                    .lineLimit(1)
                    .frame(width: 178, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .disabled(voiceIsGlobal)
            .help(voiceIsGlobal ? "语音键在所有应用中保持一致，请在默认键位中修改。" : "修改\(button.displayName)")
        }
        .padding(8)
        .background(selectedButton == button ? Color.accentColor.opacity(0.09) : Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var livePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前前台应用").font(.caption).foregroundColor(.secondary)
            Text(foreground.application?.displayName ?? "未识别应用").font(.callout.weight(.semibold))
            Text("生效：\(activeProfileName)")
                .font(.caption)
                .foregroundColor(.secondary)
            RemoteControlDiagram(
                selectedButton: $selectedButton,
                voiceActive: model.isStreaming,
                variant: settings.xiaomiRemoteVariant
            )
            Text("当前前台的\(selectedButton.displayName)")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(settings.binding(
                for: selectedButton,
                applicationBundleIdentifier: foreground.application?.bundleIdentifier
            ).displayName)
                .font(.callout.weight(.semibold))
            Text("切回目标应用，再用遥控器试按。编辑中的应用与当前前台应用可以不同。")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var activeProfileName: String {
        guard settings.automaticallySwitchApplicationKeymaps else { return "默认键位（自动切换已关闭）" }
        return settings.applicationKeymap(for: foreground.application?.bundleIdentifier)?.displayName ?? "默认键位"
    }

    private func addApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择要单独设置键位的应用"
        panel.prompt = "添加应用"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let identifier = Bundle(url: url)?.bundleIdentifier,
              settings.addApplicationKeymap(
                bundleIdentifier: identifier,
                displayName: FileManager.default.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: "", options: [.anchored, .backwards])
              ) else {
            errorMessage = "无法识别所选应用，请选择有效的 Mac 应用。"
            return
        }
        editingBundleIdentifier = identifier
    }

    private func setBinding(_ binding: ButtonBinding, for button: RemoteButton) {
        if !model.setButtonBinding(binding, for: button, applicationBundleIdentifier: editingBundleIdentifier) {
            errorMessage = model.voiceShortcutStatus
        }
    }

    private func resetEditingProfile() {
        if let editingBundleIdentifier {
            model.clearApplicationOverrides(bundleIdentifier: editingBundleIdentifier)
        } else if !model.resetButtonBindings() {
            errorMessage = model.voiceShortcutStatus
        }
    }
}
