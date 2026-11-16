import AppKit
import Network

final class ServerApp: NSObject, NSApplicationDelegate {
    private let server = Process()
    private let status = NSTextField(labelWithString: "Starting your local world…")
    private var window: NSWindow!
    private var timer: Timer?
    private var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 145),
            styleMask: [.titled, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MU Server"
        let credentials = NSTextField(wrappingLabelWithString:
            "Open MU Client to play. Sign in with solo / soloplay and create a character.")
        let stop = NSButton(title: "Stop Server and Quit", target: self, action: #selector(stopServer))
        stop.keyEquivalent = "q"
        stop.keyEquivalentModifierMask = .command
        let stack = NSStackView(views: [status, credentials, stop])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let content = window.contentView {
            content.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
                stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            ])
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        guard let launcher = Bundle.main.url(forResource: "start-server", withExtension: "sh") else {
            status.stringValue = "The server launcher is missing."
            return
        }
        server.executableURL = URL(fileURLWithPath: "/bin/bash")
        server.arguments = [launcher.path]
        server.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.timer?.invalidate()
                if self.quitting {
                    NSApp.reply(toApplicationShouldTerminate: true)
                } else {
                    self.status.stringValue = "Server stopped. See the logs in MU Solo."
                }
            }
        }
        do {
            try server.run()
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                self?.checkReadiness()
            }
        } catch {
            status.stringValue = "Couldn’t start the server."
        }
    }

    private func checkReadiness() {
        let probe = NWConnection(host: "127.0.0.1", port: 44406, using: .tcp)
        probe.stateUpdateHandler = { [weak self, weak probe] state in
            if case .ready = state, let self, self.server.isRunning, !self.quitting {
                self.status.stringValue = "Your local world is ready."
                self.timer?.invalidate()
                probe?.cancel()
            }
        }
        probe.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { probe.cancel() }
    }

    @objc private func stopServer() {
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard server.isRunning else { return .terminateNow }
        quitting = true
        timer?.invalidate()
        status.stringValue = "Saving and stopping the server…"
        server.terminate()
        return .terminateLater
    }
}

let app = NSApplication.shared
let delegate = ServerApp()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
