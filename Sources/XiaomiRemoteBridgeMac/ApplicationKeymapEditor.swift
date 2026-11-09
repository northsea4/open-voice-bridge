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

private enum KeymapEditorAlert: Identifiable {
    case resetDefaults
    case clearOverrides(bundleIdentifier: String, name: String)
    case removeApplication(bundleIdentifier: String, name: String)
    case error(String)

    var id: String {
        switch self {
        case .resetDefaults: return "reset"
        case let .clearOverrides(identifier, _): return "clear-" + identifier
        case let .removeApplication(identifier, _): return "remove-" + identifier
        case let .error(message): return "error-" + message
        }
    }
}

struct ApplicationKeymapEditor: View {
    @ObservedObject var model: BridgeAppModel
    @ObservedObject private var settings: AppSettings
    @ObservedObject private var foreground: ForegroundApplicationMonitor
    @State private var editingBundleIdentifier: String?
    @State private var selectedButton: RemoteButton = .ok
    @State private var recordingButton: RemoteButton?
    @State private var editorAlert: KeymapEditorAlert?

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
                applicationSidebar.frame(width: 174)
                Divider()
                bindingEditor.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                ScrollView {
                    livePreview
                }
                .frame(width: 210)
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
        .alert(item: $editorAlert) { alert in
            switch alert {
            case .resetDefaults:
                return Alert(
                    title: Text("恢复默认键位？"),
                    message: Text("默认键位将恢复为初始设置，包括全局语音键。所有跟随默认的按键也会更新，应用专属键位会保留。"),
                    primaryButton: .destructive(Text("恢复默认键位")) { resetDefaultBindings() },
                    secondaryButton: .cancel(Text("取消"))
                )
            case let .clearOverrides(identifier, name):
                return Alert(
                    title: Text("全部跟随默认？"),
                    message: Text("将清除“\(name)”的全部专属键位，之后所有按键跟随默认。此操作无法撤销。"),
                    primaryButton: .destructive(Text("全部跟随默认")) {
                        model.clearApplicationOverrides(bundleIdentifier: identifier)
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            case let .removeApplication(identifier, name):
                return Alert(
                    title: Text("移除“\(name)”的按键配置？"),
                    message: Text("将删除此应用的专属键位，之后使用默认键位。此操作无法撤销。"),
                    primaryButton: .destructive(Text("移除应用")) {
                        model.removeApplicationKeymap(bundleIdentifier: identifier)
                        if editingBundleIdentifier == identifier { editingBundleIdentifier = nil }
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            case let .error(message):
                return Alert(title: Text("无法修改键位"), message: Text(message), dismissButton: .default(Text("好")))
            }
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
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("应用只覆盖单独设置的普通键，其余跟随默认。切换应用会停止旧连发，松开再按后继续。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var applicationSidebar: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("编辑键位").font(.system(size: 12)).foregroundColor(.secondary)
            ScrollView {
                VStack(spacing: 5) {
                    applicationRow(nil)
                    ForEach(settings.applicationKeymaps) { profile in applicationRow(profile) }
                }
            }
            Button(action: addApplication) { Label("添加应用…", systemImage: "plus") }
            Text("选择要编辑的应用。此处的选择不会切换前台应用。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func applicationRow(_ profile: ApplicationKeymap?) -> some View {
        let selected = editingBundleIdentifier == profile?.bundleIdentifier
        let disabled = profile?.isEnabled == false
        let tint: Color = disabled ? .orange : .accentColor
        return Button {
            editingBundleIdentifier = profile?.bundleIdentifier
        } label: {
            HStack(spacing: 8) {
                applicationIcon(for: profile, size: 28)
                    .saturation(disabled ? 0 : 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile?.displayName ?? "默认键位")
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .foregroundColor(disabled ? .secondary : (selected ? .accentColor : .primary))
                        .lineLimit(2)
                    Text(profile.map {
                        $0.isEnabled ? "\($0.overrides.count) 个专属键位" : "已停用"
                    } ?? "其他按键的基础")
                        .font(.system(size: 12))
                        .foregroundColor(disabled ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if disabled {
                    Image(systemName: "pause.circle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))
                        .accessibilityHidden(true)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? tint.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("编辑\(profile?.displayName ?? "默认键位")\(disabled ? "，配置已停用" : "")"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func applicationIcon(for profile: ApplicationKeymap?, size: CGFloat) -> some View {
        if let profile, let icon = ApplicationIconCache.image(for: profile.bundleIdentifier) {
            Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).frame(width: size, height: size)
        } else {
            Image(systemName: profile == nil ? "keyboard" : "app")
                .font(.system(size: size * 0.55, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: size, height: size)
                .background(Color.accentColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var bindingEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                applicationIcon(for: editingProfile, size: 38)
                VStack(alignment: .leading, spacing: 5) {
                    Text(editingName)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)
                    Text(editingBundleIdentifier == nil
                         ? "修改默认键位会同步影响所有跟随默认的按键。"
                         : editingProfile?.isEnabled == false
                            ? "此配置已停用，当前使用默认键位。专属键位已保留，仍可编辑并随时重新启用。"
                            : "未修改的键跟随默认；语音键在所有应用中保持一致。")
                        .font(.system(size: 12))
                        .foregroundColor(editingProfile?.isEnabled == false ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let profile = editingProfile {
                    Toggle(isOn: Binding(
                        get: { settings.applicationKeymap(for: profile.bundleIdentifier)?.isEnabled ?? false },
                        set: { model.setApplicationKeymapEnabled($0, bundleIdentifier: profile.bundleIdentifier) }
                    )) {
                        Text(profile.isEnabled ? "已启用" : "已停用")
                            .font(.system(size: 12))
                            .foregroundColor(profile.isEnabled ? .secondary : .orange)
                    }
                    .toggleStyle(.switch)
                    .fixedSize()
                    .accessibilityLabel(Text("启用\(profile.displayName)的按键配置"))
                    .help("停用后使用默认键位，已设置的专属键位会保留。")
                }
            }
            .padding(.bottom, 4)
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
                Button(editingBundleIdentifier == nil ? "恢复默认键位" : "全部跟随默认") {
                    if let profile = editingProfile {
                        editorAlert = .clearOverrides(bundleIdentifier: profile.bundleIdentifier, name: profile.displayName)
                    } else {
                        editorAlert = .resetDefaults
                    }
                }
                Spacer()
                if let profile = editingProfile {
                    Button("移除应用") {
                        editorAlert = .removeApplication(bundleIdentifier: profile.bundleIdentifier, name: profile.displayName)
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
        let hasOverride = settings.applicationOverride(for: button, bundleIdentifier: editingBundleIdentifier) != nil
        return HStack(spacing: 8) {
            Button { selectedButton = button } label: {
                HStack(spacing: 8) {
                    Text(button.shortLabel)
                        .font(.system(size: 12).weight(.semibold))
                        .frame(width: 36, height: 29)
                        .background(selectedButton == button ? Color.accentColor : Color.secondary.opacity(0.14))
                        .foregroundColor(selectedButton == button ? .white : .primary)
                        .clipShape(Capsule())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(button.displayName).font(.callout)
                        if hasOverride {
                            Label("已修改", systemImage: "pencil")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Capsule())
                                .help("此应用的专属键位；在动作菜单中选择“跟随默认”即可恢复继承。")
                        } else {
                            Text(sourceLabel(for: button))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
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
        .background(selectedButton == button
                    ? Color.accentColor.opacity(0.09)
                    : hasOverride ? Color.accentColor.opacity(0.045) : Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(hasOverride ? Color.accentColor.opacity(0.45) : .clear, lineWidth: 1)
        )
    }

    private var livePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前前台应用").font(.system(size: 12)).foregroundColor(.secondary)
            Text(foreground.application?.displayName ?? "未识别应用").font(.callout.weight(.semibold))
            Text("生效：\(activeProfileName)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            RemoteControlDiagram(
                selectedButton: $selectedButton,
                voiceActive: model.isStreaming,
                variant: settings.xiaomiRemoteVariant
            )
            Text("当前前台的\(selectedButton.displayName)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text(settings.binding(
                for: selectedButton,
                applicationBundleIdentifier: foreground.application?.bundleIdentifier
            ).displayName)
                .font(.callout.weight(.semibold))
            Text("切回目标应用，再用遥控器试按。编辑中的应用与当前前台应用可以不同。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var activeProfileName: String {
        guard settings.automaticallySwitchApplicationKeymaps else { return "默认键位（自动切换已关闭）" }
        guard let profile = settings.applicationKeymap(for: foreground.application?.bundleIdentifier) else { return "默认键位" }
        return profile.isEnabled ? profile.displayName : "默认键位（应用配置已停用）"
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
            editorAlert = .error("无法识别所选应用，请选择有效的 Mac 应用。")
            return
        }
        editingBundleIdentifier = identifier
    }

    private func setBinding(_ binding: ButtonBinding, for button: RemoteButton) {
        if !model.setButtonBinding(binding, for: button, applicationBundleIdentifier: editingBundleIdentifier) {
            editorAlert = .error(model.voiceShortcutStatus)
        }
    }

    private func resetDefaultBindings() {
        if !model.resetButtonBindings() {
            // Present any voice-key guard failure after the confirmation closes.
            DispatchQueue.main.async { editorAlert = .error(model.voiceShortcutStatus) }
        }
    }
}
