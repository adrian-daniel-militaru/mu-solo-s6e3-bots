import AppKit

final class ClientApp: NSObject, NSApplicationDelegate {
    private let status = NSTextField(wrappingLabelWithString: "")
    private let progress = NSProgressIndicator()
    private let installer = Process()
    private var window: NSWindow?
    private var logURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let files = FileManager.default
            let support = try files.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                        appropriateFor: nil, create: true)
            let state = support.appendingPathComponent("MU Solo", isDirectory: true)
            guard let release = Bundle.main.object(forInfoDictionaryKey: "MUSoloClientRelease") as? String,
                  let script = Bundle.main.url(forResource: "install-client", withExtension: "sh") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let game = state.appendingPathComponent("client", isDirectory: true)
                .appendingPathComponent(release, isDirectory: true)
                .appendingPathComponent("MU Online.app", isDirectory: true)
            if files.isExecutableFile(atPath: game.appendingPathComponent("Contents/MacOS/Main").path) {
                launch(game)
                return
            }

            let logs = state.appendingPathComponent("logs", isDirectory: true)
            try files.createDirectory(at: logs, withIntermediateDirectories: true)
            let log = logs.appendingPathComponent("client-install.log")
            try Data().write(to: log, options: .atomic)
            logURL = log
            let handle = try FileHandle(forWritingTo: log)
            defer { try? handle.close() }
            installer.executableURL = URL(fileURLWithPath: "/bin/bash")
            installer.arguments = [script.path, game.path]
            installer.standardOutput = handle
            installer.standardError = handle
            installer.terminationHandler = { [weak self] process in
                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        self?.launch(game)
                    } else {
                        self?.showStatus("Couldn’t install MuMain. Reopen MU Client to retry. Details are in client-install.log.",
                                         installing: false)
                    }
                }
            }
            showStatus("Downloading MuMain and its game data. Later launches work offline.", installing: true)
            try installer.run()
        } catch {
            showStatus("Couldn’t start MU Client. \(error.localizedDescription)", installing: false)
        }
    }

    private func launch(_ game: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["connect", "/u127.0.0.1", "/p44406"]
        NSWorkspace.shared.openApplication(at: game, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    self?.showStatus("Couldn’t open MuMain. \(error.localizedDescription)", installing: false)
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func showStatus(_ message: String, installing: Bool) {
        status.stringValue = message
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 140),
                                 styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "MU Client"
            panel.isReleasedWhenClosed = false
            progress.style = .bar
            progress.isIndeterminate = true
            let showLog = NSButton(title: "Show Install Log", target: self, action: #selector(showInstallLog))
            showLog.isHidden = logURL == nil
            let stack = NSStackView(views: [status, progress, showLog])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 12
            stack.translatesAutoresizingMaskIntoConstraints = false
            if let content = panel.contentView {
                content.addSubview(stack)
                NSLayoutConstraint.activate([
                    stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                    stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
                    stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                    progress.widthAnchor.constraint(equalTo: stack.widthAnchor),
                ])
            }
            panel.center()
            window = panel
        }
        progress.isHidden = !installing
        if installing {
            progress.startAnimation(nil)
        } else {
            progress.stopAnimation(nil)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showInstallLog() {
        if let logURL {
            NSWorkspace.shared.activateFileViewerSelecting([logURL])
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        if installer.isRunning {
            installer.terminate()
        }
    }
}

let app = NSApplication.shared
let delegate = ClientApp()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
