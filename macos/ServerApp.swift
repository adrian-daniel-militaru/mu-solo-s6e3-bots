import AppKit
import Network

final class ServerApp: NSObject, NSApplicationDelegate {
    private let botCountKey = "BotCount"
    private let botCountRange = 0...600
    private let botCountField = NSTextField(string: "")
    private lazy var apply = NSButton(title: "Apply and Restart", target: self, action: #selector(applyBotCount))
    private let status = NSTextField(labelWithString: "Starting your local world…")
    private var server: Process?
    private var nextBotCount: Int?
    private var window: NSWindow!
    private var timer: Timer?
    private var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 210),
            styleMask: [.titled, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MU Server"
        let credentials = NSTextField(wrappingLabelWithString:
            "Open MU Client to play. Sign in with solo / soloplay and create a character.")
        let savedCount = UserDefaults.standard.object(forKey: botCountKey) as? Int
        let botCount = savedCount.flatMap { botCountRange.contains($0) ? $0 : nil } ?? 12
        botCountField.stringValue = String(botCount)
        botCountField.isEditable = true
        botCountField.alignment = .right
        botCountField.setAccessibilityLabel("Bot count")
        botCountField.widthAnchor.constraint(equalToConstant: 55).isActive = true
        let settings = NSStackView(views: [
            NSTextField(labelWithString: "Bots"), botCountField, apply,
        ])
        settings.orientation = .horizontal
        settings.alignment = .firstBaseline
        settings.spacing = 8
        let hint = NSTextField(labelWithString: "Choose 0–600. Applying disconnects the client.")
        hint.textColor = .secondaryLabelColor
        let stop = NSButton(title: "Stop Server and Quit", target: self, action: #selector(stopServer))
        stop.keyEquivalent = "q"
        stop.keyEquivalentModifierMask = .command
        let stack = NSStackView(views: [status, credentials, settings, hint, stop])
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
        startServer(botCount: botCount)
    }

    private func startServer(botCount: Int) {
        guard let launcher = Bundle.main.url(forResource: "start-server", withExtension: "sh") else {
            status.stringValue = "The server launcher is missing."
            apply.isEnabled = false
            return
        }
        status.stringValue = "Starting your local world…"
        apply.isEnabled = false
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [launcher.path]
        var environment = ProcessInfo.processInfo.environment
        environment["MU_SOLO_BOT_COUNT"] = String(botCount)
        process.environment = environment
        process.terminationHandler = { [weak self] stoppedProcess in
            DispatchQueue.main.async {
                guard let self, self.server === stoppedProcess else { return }
                self.timer?.invalidate()
                self.server = nil
                if self.quitting {
                    NSApp.reply(toApplicationShouldTerminate: true)
                } else if let count = self.nextBotCount {
                    self.nextBotCount = nil
                    self.startServer(botCount: count)
                } else {
                    self.status.stringValue = "Server stopped. See the logs in MU Solo."
                    self.apply.isEnabled = true
                }
            }
        }
        server = process
        do {
            try process.run()
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self, weak process] _ in
                if let process {
                    self?.checkReadiness(for: process)
                }
            }
        } catch {
            server = nil
            status.stringValue = "Couldn’t start the server."
            apply.isEnabled = true
        }
    }

    private func checkReadiness(for process: Process) {
        let probe = NWConnection(host: "127.0.0.1", port: 44406, using: .tcp)
        probe.stateUpdateHandler = { [weak self, weak probe] state in
            if case .ready = state, let self, self.server === process, process.isRunning,
               self.nextBotCount == nil, !self.quitting {
                self.status.stringValue = "Your local world is ready."
                self.apply.isEnabled = true
                self.timer?.invalidate()
                probe?.cancel()
            }
        }
        probe.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { probe.cancel() }
    }

    @objc private func applyBotCount() {
        window.makeFirstResponder(nil)
        let value = botCountField.stringValue.trimmingCharacters(in: .whitespaces)
        guard let count = Int(value), botCountRange.contains(count) else {
            let alert = NSAlert()
            alert.messageText = "Enter a whole number from 0 to 600."
            alert.beginSheetModal(for: window, completionHandler: nil)
            return
        }
        botCountField.stringValue = String(count)
        UserDefaults.standard.set(count, forKey: botCountKey)
        if let server {
            nextBotCount = count
            apply.isEnabled = false
            timer?.invalidate()
            status.stringValue = "Saving and restarting the server…"
            if server.isRunning {
                server.terminate()
            }
        } else {
            startServer(botCount: count)
        }
    }

    @objc private func stopServer() {
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let server, server.isRunning else { return .terminateNow }
        quitting = true
        apply.isEnabled = false
        timer?.invalidate()
        status.stringValue = "Saving and stopping the server…"
        if nextBotCount == nil {
            server.terminate()
        }
        return .terminateLater
    }
}

let app = NSApplication.shared
let delegate = ServerApp()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
