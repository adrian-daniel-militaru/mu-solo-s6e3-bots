import AppKit
import Network

final class ServerApp: NSObject, NSApplicationDelegate {
    private enum BotSettings {
        case launcher(Int)
        case controlPanel
    }

    private let botCountKey = "BotCount"
    private let botSettingsModeKey = "ManageBotsInControlPanel"
    private let botCountRange = 0...600
    private let botCountField = NSTextField(string: "")
    private lazy var apply = NSButton(title: "Apply and Restart", target: self, action: #selector(applyBotSettings))
    private lazy var manageBots = NSButton(checkboxWithTitle: "Manage bots in Control Panel",
                                           target: self, action: #selector(updateBotControls))
    private lazy var openPanel = NSButton(title: "Open Control Panel", target: self, action: #selector(openControlPanel))
    private lazy var copyPassword = NSButton(title: "Copy Admin Password", target: self, action: #selector(copyAdminPassword))
    private let status = NSTextField(labelWithString: "Starting your local world…")
    private var server: Process?
    private var nextBotSettings: BotSettings?
    private var controlPanelURL: URL?
    private var window: NSWindow!
    private var timer: Timer?
    private var quitting = false

    private lazy var stateDirectory: URL = {
        if let path = ProcessInfo.processInfo.environment["MU_SOLO_STATE_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MU Solo", isDirectory: true)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 290),
            styleMask: [.titled, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MU Server"
        let credentials = NSTextField(wrappingLabelWithString:
            "Open MU Client to play. Sign in with solo / soloplay and create a character.")
        let savedCount = UserDefaults.standard.object(forKey: botCountKey) as? Int
        let botCount = savedCount.flatMap { botCountRange.contains($0) ? $0 : nil } ?? 12
        let managedInPanel = UserDefaults.standard.bool(forKey: botSettingsModeKey)
        manageBots.state = managedInPanel ? .on : .off
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
        updateBotControls()
        let hint = NSTextField(labelWithString: "Choose 0–600. Applying disconnects the client.")
        hint.textColor = .secondaryLabelColor
        let panelButtons = NSStackView(views: [openPanel, copyPassword])
        panelButtons.orientation = .horizontal
        panelButtons.spacing = 8
        let panelHint = NSTextField(labelWithString: "Sign in to the control panel as admin.")
        panelHint.textColor = .secondaryLabelColor
        let stop = NSButton(title: "Stop Server and Quit", target: self, action: #selector(stopServer))
        stop.keyEquivalent = "q"
        stop.keyEquivalentModifierMask = .command
        let stack = NSStackView(views: [status, credentials, settings, manageBots, hint, panelButtons, panelHint, stop])
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
        startServer(botSettings: managedInPanel ? .controlPanel : .launcher(botCount))
    }

    private func startServer(botSettings: BotSettings) {
        setControlPanelURL(nil)
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
        switch botSettings {
        case .launcher(let botCount):
            environment["MU_SOLO_BOT_COUNT"] = String(botCount)
        case .controlPanel:
            environment.removeValue(forKey: "MU_SOLO_BOT_COUNT")
        }
        process.environment = environment
        process.terminationHandler = { [weak self] stoppedProcess in
            DispatchQueue.main.async {
                guard let self, self.server === stoppedProcess else { return }
                self.timer?.invalidate()
                self.setControlPanelURL(nil)
                self.server = nil
                if self.quitting {
                    NSApp.reply(toApplicationShouldTerminate: true)
                } else if let settings = self.nextBotSettings {
                    self.nextBotSettings = nil
                    self.startServer(botSettings: settings)
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
        guard server === process, process.isRunning, nextBotSettings == nil, !quitting else { return }
        if controlPanelURL == nil, let url = readControlPanelURL() {
            setControlPanelURL(url)
        }
        let probe = NWConnection(host: "127.0.0.1", port: 44406, using: .tcp)
        probe.stateUpdateHandler = { [weak self, weak probe] state in
            if case .ready = state, let self, self.server === process, process.isRunning,
               self.nextBotSettings == nil, !self.quitting {
                self.status.stringValue = "Your local world is ready."
                self.apply.isEnabled = true
                self.timer?.invalidate()
                probe?.cancel()
            }
        }
        probe.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { probe.cancel() }
    }

    private func readControlPanelURL() -> URL? {
        let file = stateDirectory.appendingPathComponent("admin-url")
        guard let address = try? String(contentsOf: file, encoding: .utf8),
              let url = URL(string: address),
              url.scheme == "http", url.host == "127.0.0.1", let port = url.port, port > 0 else {
            return nil
        }
        return url
    }

    private func setControlPanelURL(_ url: URL?) {
        controlPanelURL = url
        openPanel.isEnabled = url != nil
        copyPassword.isEnabled = url != nil
    }

    @objc private func openControlPanel() {
        if let controlPanelURL {
            NSWorkspace.shared.open(controlPanelURL)
        }
    }

    @objc private func copyAdminPassword() {
        let file = stateDirectory.appendingPathComponent("admin-password")
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else {
            status.stringValue = "Couldn’t read the admin password."
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(contents.trimmingCharacters(in: .newlines), forType: .string) {
            status.stringValue = "Admin password copied."
        }
    }

    @objc private func updateBotControls() {
        botCountField.isEnabled = manageBots.state != .on
    }

    @objc private func applyBotSettings() {
        window.makeFirstResponder(nil)
        let managedInPanel = manageBots.state == .on
        let settings: BotSettings
        if managedInPanel {
            settings = .controlPanel
        } else {
            let value = botCountField.stringValue.trimmingCharacters(in: .whitespaces)
            guard let count = Int(value), botCountRange.contains(count) else {
                let alert = NSAlert()
                alert.messageText = "Enter a whole number from 0 to 600."
                alert.beginSheetModal(for: window, completionHandler: nil)
                return
            }
            botCountField.stringValue = String(count)
            UserDefaults.standard.set(count, forKey: botCountKey)
            settings = .launcher(count)
        }
        UserDefaults.standard.set(managedInPanel, forKey: botSettingsModeKey)
        if let server {
            nextBotSettings = settings
            apply.isEnabled = false
            setControlPanelURL(nil)
            timer?.invalidate()
            status.stringValue = "Saving and restarting the server…"
            if server.isRunning {
                server.terminate()
            }
        } else {
            startServer(botSettings: settings)
        }
    }

    @objc private func stopServer() {
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let server, server.isRunning else { return .terminateNow }
        quitting = true
        apply.isEnabled = false
        setControlPanelURL(nil)
        timer?.invalidate()
        status.stringValue = "Saving and stopping the server…"
        if nextBotSettings == nil {
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
