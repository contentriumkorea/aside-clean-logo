import AppKit
import Darwin

private let fm = FileManager.default
private let agentLabel = "com.contentrium.aside-clean-logo"
private let appName = "Aside Clean Logo.app"
private let support = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Aside Clean Logo")
private let installedApp = support.appendingPathComponent(appName)
private let agentURL = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")

struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

@discardableResult
func run(_ executable: String, _ arguments: [String], allowFailure: Bool = false) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    if process.terminationStatus != 0 && !allowFailure {
        throw Failure("\(URL(fileURLWithPath: executable).lastPathComponent): \(String(data: data, encoding: .utf8) ?? "operation failed")")
    }
    return process.terminationStatus
}

func verifySignature(_ target: URL) throws {
    try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", target.path])
}

func readAttribute(_ url: URL, _ name: String) throws -> Data? {
    let count = getxattr(url.path, name, nil, 0, 0, 0)
    if count < 0 {
        if errno == ENOATTR { return nil }
        throw Failure("Cannot read icon metadata at \(url.path): \(String(cString: strerror(errno)))")
    }
    var data = Data(count: count)
    let actual = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, count, 0, 0) }
    guard actual == count else { throw Failure("Icon metadata changed while being read. Please retry.") }
    return data
}

func writeAttribute(_ data: Data?, _ url: URL, _ name: String) throws {
    if let data = data {
        let result = data.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, data.count, 0, 0) }
        guard result == 0 else { throw Failure("Cannot restore \(name): \(String(cString: strerror(errno)))") }
    } else if removexattr(url.path, name, 0) != 0 && errno != ENOATTR {
        throw Failure("Cannot remove icon metadata: \(String(cString: strerror(errno)))")
    }
}

// NSWorkspace stores folder custom icons in FinderInfo and an Icon\r resource fork.
// Save the original bytes rather than reconstructing an existing custom icon.
struct OriginalIcon: Codable, Equatable {
    let finderInfo: Data?
    let resourceFork: Data?
    let iconFileExists: Bool
    let iconData: Data?
    let iconFinderInfo: Data?
    let iconResourceFork: Data?

    init(target: URL) throws {
        finderInfo = try readAttribute(target, "com.apple.FinderInfo")
        resourceFork = try readAttribute(target, "com.apple.ResourceFork")
        let icon = target.appendingPathComponent("Icon\r")
        iconFileExists = fm.fileExists(atPath: icon.path)
        iconData = iconFileExists ? try Data(contentsOf: icon) : nil
        iconFinderInfo = iconFileExists ? try readAttribute(icon, "com.apple.FinderInfo") : nil
        iconResourceFork = iconFileExists ? try readAttribute(icon, "com.apple.ResourceFork") : nil
    }

    func restore(target: URL) throws {
        guard NSWorkspace.shared.setIcon(nil, forFile: target.path, options: []) else {
            throw Failure("macOS refused to restore the original icon. Check write permission for \(target.path). Backup was kept.")
        }
        let icon = target.appendingPathComponent("Icon\r")
        if iconFileExists {
            try (iconData ?? Data()).write(to: icon, options: .atomic)
            try writeAttribute(iconFinderInfo, icon, "com.apple.FinderInfo")
            try writeAttribute(iconResourceFork, icon, "com.apple.ResourceFork")
        } else if fm.fileExists(atPath: icon.path) {
            try fm.removeItem(at: icon)
        }
        try writeAttribute(finderInfo, target, "com.apple.FinderInfo")
        try writeAttribute(resourceFork, target, "com.apple.ResourceFork")
    }
}

struct Installation: Codable {
    let target: String
    let original: OriginalIcon
}

func iconName(dark: Bool) -> String { dark ? "white" : "black" }

func systemIsDark() -> Bool {
    NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
}

final class IconEngine {
    let directory: URL
    let assets: URL
    var stateURL: URL { directory.appendingPathComponent("installation.json") }

    init(directory: URL, assets: URL) {
        self.directory = directory
        self.assets = assets
    }

    func load() throws -> Installation {
        try JSONDecoder().decode(Installation.self, from: Data(contentsOf: stateURL))
    }

    func prepare(_ target: URL) throws {
        guard Bundle(url: target) != nil, target.pathExtension == "app" else { throw Failure("Select an application bundle.") }
        try verifySignature(target)
        if fm.fileExists(atPath: stateURL.path) {
            guard try load().target == target.path else {
                throw Failure("Another Aside installation is already configured. Uninstall first to restore its icon.")
            }
            return
        }
        let state = try Installation(target: target.path, original: OriginalIcon(target: target))
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
    }

    func apply(dark: Bool) throws {
        let state = try load()
        let target = URL(fileURLWithPath: state.target)
        try verifySignature(target)
        guard let image = NSImage(contentsOf: assets.appendingPathComponent("\(iconName(dark: dark)).png")) else {
            throw Failure("The approved icon resource is missing or unreadable.")
        }
        guard NSWorkspace.shared.setIcon(image, forFile: target.path, options: []) else {
            throw Failure("macOS could not change the Aside icon. Your account needs write permission for \(target.path). Install an account-owned copy in ~/Applications, then retry. No administrator or security bypass is performed.")
        }
        do {
            try verifySignature(target)
        } catch {
            try state.original.restore(target: target)
            throw Failure("Signature verification after icon customization failed; the original icon was restored. \(error.localizedDescription)")
        }
    }

    func restore() throws {
        let state = try load()
        let target = URL(fileURLWithPath: state.target)
        guard fm.fileExists(atPath: target.path) else {
            throw Failure("Aside was moved or removed. Put it back at \(target.path), then retry uninstall. The backup was kept.")
        }
        try state.original.restore(target: target)
        try verifySignature(target)
    }
}

// Failed updates leave lastDark unchanged so the next timer tick retries.
final class ThemeTracker {
    var lastDark: Bool?
    func update(dark: Bool, force: Bool = false, apply: (Bool) throws -> Void) throws {
        if force || lastDark != dark {
            try apply(dark)
            lastDark = dark
        }
    }
}

func resources() -> URL { Bundle.main.resourceURL! }

struct WatcherReady: Codable {
    let token: String
    let pid: Int32
}

func isWatcherReady(at url: URL, token: String) -> Bool {
    guard let data = try? Data(contentsOf: url),
          let ready = try? JSONDecoder().decode(WatcherReady.self, from: data),
          ready.token == token, ready.pid > 0 else { return false }
    return kill(ready.pid, 0) == 0
}

func startAgent() throws {
    let domain = "gui/\(getuid())"
    let token = UUID().uuidString
    let readyURL = support.appendingPathComponent("watcher-ready.json")
    if fm.fileExists(atPath: readyURL.path) { try fm.removeItem(at: readyURL) }
    let executable = installedApp.appendingPathComponent("Contents/MacOS/AsideCleanLogo").path
    let plist: [String: Any] = [
        "Label": agentLabel,
        "ProgramArguments": [executable, "--watch", "--ready-token", token],
        "RunAtLoad": true,
        "KeepAlive": true,
        "ThrottleInterval": 15,
        "ProcessType": "Background",
        "LimitLoadToSessionType": "Aqua"
    ]
    try fm.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: agentURL, options: .atomic)
    try run("/bin/launchctl", ["bootstrap", domain, agentURL.path])
    let deadline = Date().addingTimeInterval(12)
    while !isWatcherReady(at: readyURL, token: token) && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.1)
    }
    guard isWatcherReady(at: readyURL, token: token) else {
        throw Failure("The login watcher did not confirm a successful initial icon update. Installation will be rolled back.")
    }
    try run("/bin/launchctl", ["print", domain + "/" + agentLabel])
}

// Preserve the working helper, agent definition, and current icon until the new
// watcher has acknowledged success. Injectable service callbacks test real file rollback.
func installTransaction(source: URL, helper: URL, agent: URL, engine: IconEngine,
                        dark: Bool, isLoaded: () throws -> Bool, stop: () throws -> Void,
                        startNew: () throws -> Void, restartPrevious: () throws -> Void) throws {
    let target = URL(fileURLWithPath: try engine.load().target)
    let previousIcon = try OriginalIcon(target: target)
    let previousAgent = fm.fileExists(atPath: agent.path) ? try Data(contentsOf: agent) : nil
    let previousLoaded = try isLoaded()
    let previousHelperExists = fm.fileExists(atPath: helper.path)
    let transaction = engine.directory.appendingPathComponent("transaction-" + UUID().uuidString)
    let staged = transaction.appendingPathComponent("staged.app")
    let previous = transaction.appendingPathComponent("previous.app")
    try fm.createDirectory(at: transaction, withIntermediateDirectories: true)
    var stoppedPrevious = false
    var replacedHelper = false
    var iconAttempted = false
    var startAttempted = false
    do {
        try fm.copyItem(at: source, to: staged)
        try verifySignature(staged)
        if previousLoaded { try stop(); stoppedPrevious = true }
        if previousHelperExists { try fm.moveItem(at: helper, to: previous) }
        // Record replacement before moving so a failed move still restores previous.app.
        replacedHelper = true
        try fm.moveItem(at: staged, to: helper)
        iconAttempted = true
        try engine.apply(dark: dark)
        startAttempted = true
        try startNew()
    } catch {
        let originalError = error
        var rollbackErrors: [String] = []
        func attempt(_ body: () throws -> Void) {
            do { try body() } catch { rollbackErrors.append(error.localizedDescription) }
        }
        // If stopping the replacement fails, do not let it overwrite a restored icon.
        var replacementStopped = true
        if startAttempted {
            do { try stop() } catch { replacementStopped = false; rollbackErrors.append(error.localizedDescription) }
        }
        if replacementStopped {
            if replacedHelper {
                attempt {
                    if fm.fileExists(atPath: helper.path) { try fm.removeItem(at: helper) }
                    if previousHelperExists { try fm.moveItem(at: previous, to: helper) }
                }
            }
            attempt {
                if let previousAgent = previousAgent {
                    try previousAgent.write(to: agent, options: .atomic)
                } else if fm.fileExists(atPath: agent.path) {
                    try fm.removeItem(at: agent)
                }
            }
            if iconAttempted { attempt { try previousIcon.restore(target: target); try verifySignature(target) } }
            if stoppedPrevious { attempt { try restartPrevious() } }
        }
        if rollbackErrors.isEmpty {
            try? fm.removeItem(at: transaction)
            throw Failure(originalError.localizedDescription + "\nThe previous helper, login-agent state, and icon were restored.")
        }
        throw Failure(originalError.localizedDescription + "\nRollback needs attention: " + rollbackErrors.joined(separator: "; ") + "\nRecovery files and original icon backup were kept at " + engine.directory.path)
    }
    // Installation is committed; cleanup failure must not roll back a ready watcher.
    try? fm.removeItem(at: transaction)
}

final class Installer: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var status: NSTextField!
    var selected: URL?
    var observation: NSKeyValueObservation?
    var timer: Timer?
    var lastTargetModified: Date?
    let tracker = ThemeTracker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--watch") { watch(); return }
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Aside Clean Logo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 410), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Aside Clean Logo"
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 26),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -26),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 25)
        ])
        let heading = NSTextField(labelWithString: "A clean Aside icon, matched to your Mac.")
        heading.font = .boldSystemFont(ofSize: 21)
        stack.addArrangedSubview(heading)
        let detail = NSTextField(wrappingLabelWithString: "Dark appearance → white icon. Light appearance → black icon.\n\nInstalls a helper for your account that starts at login. The original icon is backed up. Aside’s code and browser data are preserved.\n\nFinder/app icons switch automatically. A running or pinned Dock icon may stay cached; relaunching Aside may be necessary. Live Dock switching is not guaranteed.")
        stack.addArrangedSubview(detail)
        status = NSTextField(wrappingLabelWithString: "")
        stack.addArrangedSubview(status)
        let buttons = NSStackView()
        buttons.spacing = 12
        buttons.addArrangedSubview(NSButton(title: "Choose Aside…", target: self, action: #selector(choose)))
        let install = NSButton(title: "Install", target: self, action: #selector(install))
        install.bezelStyle = .rounded
        install.keyEquivalent = "\r"
        buttons.addArrangedSubview(install)
        buttons.addArrangedSubview(NSButton(title: "Uninstall / Restore", target: self, action: #selector(uninstall)))
        stack.addArrangedSubview(buttons)
        selected = [fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Aside.app"), URL(fileURLWithPath: "/Applications/Aside.app")].first { fm.fileExists(atPath: $0.path) }
        refreshStatus()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if CommandLine.arguments.contains("--watch") {
            // LaunchServices may route reopening the installer to the background helper.
            // Use a separate process so uninstall can stop the watcher safely.
            let process = Process()
            process.executableURL = installedApp.appendingPathComponent("Contents/MacOS/AsideCleanLogo")
            process.arguments = ["--installer"]
            do { try process.run() } catch { NSLog("Cannot open installer: %@", error.localizedDescription) }
            return false
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func refreshStatus() {
        let configured = try? IconEngine(directory: support, assets: resources()).load()
        status.stringValue = configured.map { "Icon backup / target: \($0.target)" } ?? selected.map { "Aside: \($0.path)" } ?? "Aside was not found. Choose your Aside.app to continue."
    }

    func alert(_ message: String, error: Bool = false) {
        let alert = NSAlert()
        alert.alertStyle = error ? .warning : .informational
        alert.messageText = error ? "Action needs attention" : "Aside Clean Logo"
        alert.informativeText = message
        alert.runModal()
        refreshStatus()
    }

    @objc func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["app"]
        panel.message = "Choose the installed Aside.app."
        if panel.runModal() == .OK { selected = panel.url; refreshStatus() }
    }

    @objc func install() {
        do {
            guard let target = selected, target.lastPathComponent.lowercased() == "aside.app" else {
                throw Failure("Choose the installed Aside.app first.")
            }
            let engine = IconEngine(directory: support, assets: resources())
            try engine.prepare(target)
            let service = "gui/\(getuid())/\(agentLabel)"
            let domain = "gui/\(getuid())"
            let loaded: () throws -> Bool = {
                try run("/bin/launchctl", ["print", service], allowFailure: true) == 0
            }
            let stop: () throws -> Void = {
                if try loaded() { try run("/bin/launchctl", ["bootout", service]) }
            }
            try installTransaction(source: Bundle.main.bundleURL, helper: installedApp, agent: agentURL,
                                   engine: engine, dark: systemIsDark(), isLoaded: loaded, stop: stop,
                                   startNew: { try startAgent() }, restartPrevious: {
                try run("/bin/launchctl", ["bootstrap", domain, agentURL.path])
                try run("/bin/launchctl", ["print", service])
            })
            alert("Installed. Appearance is monitored for your account. Reopen this installer to restore the original icon.\n\nIf the Dock still shows an older icon, relaunch Aside when convenient. Automatic live Dock refresh is not guaranteed.")
        } catch { alert(error.localizedDescription + "\n\nAny original-icon backup is retained for Restore.", error: true) }
    }

    @objc func uninstall() {
        do {
            let engine = IconEngine(directory: support, assets: resources())
            guard fm.fileExists(atPath: engine.stateURL.path) else { throw Failure("No installation backup was found for this account.") }
            let service = "gui/\(getuid())/\(agentLabel)"
            // Stop first; do not restore while a watcher can reapply the replacement.
            let loaded = try run("/bin/launchctl", ["print", service], allowFailure: true) == 0
            if loaded { try run("/bin/launchctl", ["bootout", service]) }
            try engine.restore()
            if fm.fileExists(atPath: agentURL.path) { try fm.removeItem(at: agentURL) }
            try fm.removeItem(at: support)
            alert("The original icon was restored. The login helper and its backup were removed. Dock refresh may require relaunching Aside.")
        } catch { alert(error.localizedDescription + "\n\nThe original-icon backup is retained until restoration succeeds.", error: true) }
    }

    func watch() {
        NSApp.setActivationPolicy(.accessory)
        let tick: () -> Void = { [weak self] in
            guard let self = self else { return }
            do {
                let engine = IconEngine(directory: support, assets: resources())
                let target = try engine.load().target
                let modified = try fm.attributesOfItem(atPath: target)[.modificationDate] as? Date
                try self.tracker.update(dark: systemIsDark(), force: modified != self.lastTargetModified) { dark in
                    try engine.apply(dark: dark)
                }
                self.lastTargetModified = try fm.attributesOfItem(atPath: target)[.modificationDate] as? Date
                if let index = CommandLine.arguments.firstIndex(of: "--ready-token"),
                   CommandLine.arguments.count > index + 1 {
                    let ready = WatcherReady(token: CommandLine.arguments[index + 1], pid: getpid())
                    try JSONEncoder().encode(ready).write(to: support.appendingPathComponent("watcher-ready.json"), options: .atomic)
                }
            } catch { NSLog("Aside Clean Logo: %@", error.localizedDescription) }
        }
        observation = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in tick() }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in tick() }
        tick()
    }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw Failure("TEST FAILED: " + message) }
}

func testInstallFailures(fixture: URL, directory: URL) throws {
    for failure in ["first-bootstrap", "upgrade-bootstrap", "upgrade-readiness", "upgrade-apply"] {
        let testDirectory = directory.appendingPathComponent(failure)
        let helper = testDirectory.appendingPathComponent(appName)
        let agent = testDirectory.appendingPathComponent("agent.plist")
        let upgrade = failure.hasPrefix("upgrade")
        let missingAssets = testDirectory.appendingPathComponent("missing-assets")
        let engine = IconEngine(directory: testDirectory, assets: failure == "upgrade-apply" ? missingAssets : resources())
        try engine.prepare(fixture)
        let backup = try Data(contentsOf: engine.stateURL)
        let icon = try OriginalIcon(target: fixture)
        let oldAgent = Data("previous launch agent".utf8)
        let oldMarker = helper.appendingPathComponent("previous-helper-marker")
        if upgrade {
            try fm.createDirectory(at: helper, withIntermediateDirectories: true)
            try Data("previous helper".utf8).write(to: oldMarker)
            try oldAgent.write(to: agent)
        }
        var loaded = upgrade
        var restarted = false
        var caughtFailure = false
        do {
            try installTransaction(source: Bundle.main.bundleURL, helper: helper, agent: agent,
                                   engine: engine, dark: false, isLoaded: { loaded },
                                   stop: { loaded = false }, startNew: {
                try Data("new launch agent".utf8).write(to: agent)
                if failure.contains("readiness") { loaded = true }
                throw Failure("Injected " + failure)
            }, restartPrevious: {
                try require(fm.fileExists(atPath: oldMarker.path), "old helper restored before agent restart")
                let restoredAgent = try Data(contentsOf: agent)
                try require(restoredAgent == oldAgent, "old plist restored before agent restart")
                loaded = true
                restarted = true
            })
        } catch {
            caughtFailure = true
        }
        try require(caughtFailure, failure + " is surfaced")
        try require(loaded == upgrade, failure + " restores prior loaded state")
        try require(restarted == upgrade, failure + " restarts prior watcher")
        try require(fm.fileExists(atPath: helper.path) == upgrade, failure + " restores prior helper presence")
        try require(fm.fileExists(atPath: agent.path) == upgrade, failure + " restores prior agent presence")
        let restored = try OriginalIcon(target: fixture)
        try require(restored == icon, failure + " restores the icon from before the attempt")
        let retainedBackup = try Data(contentsOf: engine.stateURL)
        try require(retainedBackup == backup, failure + " preserves first original backup")
        try verifySignature(fixture)
    }
    let readiness = directory.appendingPathComponent("readiness.json")
    let token = UUID().uuidString
    try require(!isWatcherReady(at: readiness, token: token), "missing acknowledgment cannot succeed")
    try JSONEncoder().encode(WatcherReady(token: "stale", pid: getpid())).write(to: readiness)
    try require(!isWatcherReady(at: readiness, token: token), "stale acknowledgment cannot succeed")
    try JSONEncoder().encode(WatcherReady(token: token, pid: -1)).write(to: readiness)
    try require(!isWatcherReady(at: readiness, token: token), "invalid watcher PID cannot succeed")
    try JSONEncoder().encode(WatcherReady(token: token, pid: getpid())).write(to: readiness)
    try require(isWatcherReady(at: readiness, token: token), "fresh live watcher acknowledgment succeeds")
    print("PASS: first-install and upgrade apply/bootstrap/readiness rollback; stale/missing readiness rejected")
}

func selfTest(fixture: URL, directory: URL) throws {
    try require(iconName(dark: true) == "white", "dark maps to white")
    try require(iconName(dark: false) == "black", "light maps to black")
    let tracker = ThemeTracker()
    var applied: [Bool] = []
    try tracker.update(dark: false) { applied.append($0) }
    try tracker.update(dark: false) { applied.append($0) }
    try tracker.update(dark: true) { applied.append($0) }
    try require(applied == [false, true], "watcher applies once initially and once per transition")
    do { try tracker.update(dark: false) { _ in throw Failure("injected failure") } } catch {}
    try require(tracker.lastDark == true, "failed apply retries")
    try tracker.update(dark: false) { applied.append($0) }
    try require(applied == [false, true, false], "retry succeeds")
    let original = try OriginalIcon(target: fixture)
    let engine = IconEngine(directory: directory, assets: resources())
    try engine.prepare(fixture)
    let backup = try Data(contentsOf: engine.stateURL)
    try engine.apply(dark: false)
    try verifySignature(fixture)
    let lightMetadata = try readAttribute(fixture, "com.apple.FinderInfo")
    try require(lightMetadata != original.finderInfo, "custom icon metadata was applied")
    let iconFile = fixture.appendingPathComponent("Icon\r")
    let lightIcon = try readAttribute(iconFile, "com.apple.ResourceFork")
    try engine.prepare(fixture)
    let repeatedBackup = try Data(contentsOf: engine.stateURL)
    try require(repeatedBackup == backup, "first backup is preserved")
    try engine.apply(dark: true)
    try verifySignature(fixture)
    let darkIcon = try readAttribute(iconFile, "com.apple.ResourceFork")
    try require(lightIcon != nil && darkIcon != nil && lightIcon != darkIcon, "dark and light apply distinct custom icon resources")
    try engine.restore()
    try verifySignature(fixture)
    let restored = try OriginalIcon(target: fixture)
    try require(restored == original, "original icon metadata is restored exactly")
    // Also preserve an existing custom icon, not only a fixture with no custom icon.
    try fm.removeItem(at: engine.stateURL)
    guard let existingImage = NSImage(contentsOf: resources().appendingPathComponent("white.png")),
          NSWorkspace.shared.setIcon(existingImage, forFile: fixture.path, options: []) else {
        throw Failure("TEST FAILED: seed existing custom icon")
    }
    let existing = try OriginalIcon(target: fixture)
    try engine.prepare(fixture)
    try engine.apply(dark: false)
    try engine.restore()
    let existingRestored = try OriginalIcon(target: fixture)
    try require(existingRestored == existing, "pre-existing custom icon is restored exactly")
    try original.restore(target: fixture)
    try verifySignature(fixture)
    try testInstallFailures(fixture: fixture, directory: directory.appendingPathComponent("transactions"))
    print("PASS: theme mapping, watcher transitions/retry, custom icon apply/restore, first-backup preservation, signed fixture integrity")
}

let app = NSApplication.shared
if let index = CommandLine.arguments.firstIndex(of: "--self-test") {
    do {
        guard CommandLine.arguments.count > index + 2 else { throw Failure("Usage: --self-test fixture.app test-state-directory") }
        try selfTest(fixture: URL(fileURLWithPath: CommandLine.arguments[index + 1]), directory: URL(fileURLWithPath: CommandLine.arguments[index + 2]))
        exit(0)
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
}
let delegate = Installer()
app.delegate = delegate
app.run()
