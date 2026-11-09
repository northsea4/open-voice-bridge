import AppKit
import Combine

struct ForegroundApplication: Equatable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let displayName: String

    static func current() -> ForegroundApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return ForegroundApplication(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            displayName: app.localizedName ?? "未知应用"
        )
    }
}

/// Publishes activation changes without polling or reading another app's data.
/// The HID path also samples current() immediately before sending an action, so
/// a queued workspace notification cannot let an old repeat reach a new app.
final class ForegroundApplicationMonitor: ObservableObject {
    @Published private(set) var application: ForegroundApplication?
    var onChange: (() -> Void)?

    private let notificationCenter: NotificationCenter
    private let readApplication: () -> ForegroundApplication?
    private var observer: NSObjectProtocol?

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        readApplication: @escaping () -> ForegroundApplication? = ForegroundApplication.current
    ) {
        self.notificationCenter = notificationCenter
        self.readApplication = readApplication
    }

    func start() {
        guard observer == nil else { return }
        refresh()
        observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    func stop() {
        if let observer { notificationCenter.removeObserver(observer) }
        observer = nil
    }

    func refresh() {
        let current = readApplication()
        guard current != application else { return }
        onChange?()
        application = current
    }

    deinit { stop() }
}
