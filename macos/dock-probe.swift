// Diagnostic only. Never included in the installer or used against a user's app.
import AppKit
import ApplicationServices
import CoreServices
import CryptoKit
import Darwin

let fm = FileManager.default

struct ProbeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct CommandResult: Codable {
    let status: Int32
    let output: String
}

func command(_ executable: String, _ args: [String]) throws -> CommandResult {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: executable)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    try p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return CommandResult(status: p.terminationStatus, output: String(decoding: data, as: UTF8.self))
}

func attribute(_ target: URL, _ name: String) throws -> Data? {
    let size = getxattr(target.path, name, nil, 0, 0, 0)
    if size == -1 {
        if errno == ENOATTR { return nil }
        throw ProbeError("getxattr \(target.path) \(name): \(String(cString: strerror(errno)))")
    }
    var data = Data(count: size)
    let count = data.withUnsafeMutableBytes { getxattr(target.path, name, $0.baseAddress, size, 0, 0) }
    guard count == size else { throw ProbeError("Metadata changed while reading") }
    return data
}

func restoreAttribute(_ data: Data?, _ target: URL, _ name: String) throws {
    if let data = data {
        let status = data.withUnsafeBytes { setxattr(target.path, name, $0.baseAddress, data.count, 0, 0) }
        guard status == 0 else { throw ProbeError("setxattr restore failed: \(name)") }
    } else if removexattr(target.path, name, 0) != 0 && errno != ENOATTR {
        throw ProbeError("removexattr restore failed: \(name)")
    }
}

func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

func contentsManifest(_ target: URL) throws -> [String: String] {
    let base = target.appendingPathComponent("Contents", isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
    guard let walker = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
        throw ProbeError("Cannot enumerate signed Contents")
    }
    var files: [String: String] = [:]
    for case let url as URL in walker {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        let components = url.standardizedFileURL.pathComponents
        guard Array(components.prefix(base.pathComponents.count)) == base.pathComponents else {
            throw ProbeError("Resource path was not under the normalized Contents directory")
        }
        let relative = components.dropFirst(base.pathComponents.count).joined(separator: "/")
        if values.isSymbolicLink == true {
            files[relative] = "symlink:" + (try fm.destinationOfSymbolicLink(atPath: url.path))
        } else if values.isRegularFile == true {
            files[relative] = digest(try Data(contentsOf: url, options: .mappedIfSafe))
        }
    }
    return files
}

func writeJSON<T: Encodable>(_ value: T, _ url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: url, options: .atomic)
}

struct Metadata: Codable, Equatable {
    let rootFinderInfo: Data?
    let rootResourceFork: Data?
    let iconExists: Bool
    let iconData: Data?
    let iconFinderInfo: Data?
    let iconResourceFork: Data?

    init(_ target: URL) throws {
        rootFinderInfo = try attribute(target, "com.apple.FinderInfo")
        rootResourceFork = try attribute(target, "com.apple.ResourceFork")
        let icon = target.appendingPathComponent("Icon\r")
        iconExists = fm.fileExists(atPath: icon.path)
        iconData = iconExists ? try Data(contentsOf: icon) : nil
        iconFinderInfo = iconExists ? try attribute(icon, "com.apple.FinderInfo") : nil
        iconResourceFork = iconExists ? try attribute(icon, "com.apple.ResourceFork") : nil
    }

    func restore(_ target: URL) throws {
        let icon = target.appendingPathComponent("Icon\r")
        if iconExists {
            try (iconData ?? Data()).write(to: icon)
            try restoreAttribute(iconFinderInfo, icon, "com.apple.FinderInfo")
            try restoreAttribute(iconResourceFork, icon, "com.apple.ResourceFork")
        } else if fm.fileExists(atPath: icon.path) { try fm.removeItem(at: icon) }
        try restoreAttribute(rootFinderInfo, target, "com.apple.FinderInfo")
        try restoreAttribute(rootResourceFork, target, "com.apple.ResourceFork")
        guard try Metadata(target) == self else { throw ProbeError("Original metadata did not restore exactly") }
    }
}

struct Phase: Codable {
    let name: String
    let pid: Int32?
    let sameRunningProcess: Bool
    let targetBundleURL: String
    let runningBundleURL: String?
    let runningExecutableURL: String?
    let runningTargetMatches: Bool
    let processCommand: CommandResult
    let dockPreferences: CommandResult
    let dockAccessibility: [[String: String]]
    let defaultVerify: CommandResult
    let strictVerify: CommandResult
    let gatekeeper: CommandResult
    let signature: CommandResult
    let contentsUnchanged: Bool
    let metadata: Metadata
    let screenshot: CommandResult
    let dockWindows: [[String: String]]
}

func dockAccessibility() -> [[String: String]] {
    guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [["error": "Dock is not running"]] }
    var result: [[String: String]] = [["trusted": String(AXIsProcessTrusted()), "dockPID": String(dock.processIdentifier)]]
    func inspect(_ element: AXUIElement, depth: Int) {
        guard depth < 5, result.count < 300 else { return }
        var values: [String: String] = [:]
        var names: CFArray?
        let status = AXUIElementCopyAttributeNames(element, &names)
        if status != .success { result.append(["error": "AX attribute inspection: \(status.rawValue)"]); return }
        let attributes = names as? [String] ?? []
        for name in attributes where name != "AXChildren" && name != "AXParent" && name != "AXTopLevelUIElement" {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value = value {
                values[name] = String(describing: value)
            }
        }
        values["availableAttributes"] = attributes.joined(separator: ",")
        if depth > 1 || values["AXSubrole"]?.contains("DockItem") == true { result.append(values) }
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let array = children as? [AXUIElement] {
            for child in array { inspect(child, depth: depth + 1) }
        }
    }
    inspect(AXUIElementCreateApplication(dock.processIdentifier), depth: 0)
    return result
}

final class DockProbe: NSObject, NSApplicationDelegate {
    let target: URL
    let assets: URL
    let output: URL
    let actualAside: Bool
    var app: NSRunningApplication?
    var originalMetadata: Metadata?
    var originalManifest: [String: String] = [:]
    var phases: [Phase] = []
    var baselineCDHash: String?
    var originalPID: Int32?
    var failed = false
    var errors: [String] = []
    var timer: Timer?
    var fixtureWindow: NSWindow?
    var socket: URLSessionWebSocketTask?
    var commandID = 0
    var usesCDP: Bool { actualAside && ProcessInfo.processInfo.environment["ASIDE_PROBE_CDP_ONLY"] == "1" }

    init(target: URL, assets: URL, output: URL, actualAside: Bool) {
        self.target = target; self.assets = assets; self.output = output; self.actualAside = actualAside
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do {
            try fm.createDirectory(at: output, withIntermediateDirectories: true)
            originalMetadata = try Metadata(target)
            originalManifest = try contentsManifest(target)
            try writeJSON(originalManifest, output.appendingPathComponent("contents-before.json"))
            try writeJSON(originalMetadata, output.appendingPathComponent("metadata-before.json"))
            let baseline = try command("/usr/bin/codesign", ["--verify", "--deep", target.path])
            guard baseline.status == 0 else { throw ProbeError("Baseline normal signature verification failed: \(baseline.output)") }
            let policy = try command("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=4", "--ignore-cache", target.path])
            try writeJSON(policy, output.appendingPathComponent("gatekeeper-baseline.json"))
            if actualAside && policy.status != 0 {
                throw ProbeError("Official Aside baseline Gatekeeper assessment was not accepted; experiment is inconclusive: \(policy.output)")
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            config.createsNewApplicationInstance = true
            if actualAside {
                guard let profile = ProcessInfo.processInfo.environment["ASIDE_PROBE_PROFILE"] else {
                    throw ProbeError("ASIDE_PROBE_PROFILE must point outside uploaded artifacts")
                }
                config.arguments = ["--user-data-dir=\(profile)", "--no-first-run", "--no-default-browser-check", "about:blank"]
                if usesCDP { config.arguments += ["--remote-debugging-port=0", "--remote-debugging-address=127.0.0.1"] }
            } else { config.arguments = ["--fixture-window"] }
            NSWorkspace.shared.openApplication(at: target, configuration: config) { [weak self] application, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let error = error { self.fail(error); return }
                    guard let application = application else { self.fail(ProbeError("No running app returned")); return }
                    self.app = application
                    self.originalPID = application.processIdentifier
                    self.waitForLaunch()
                }
            }
        } catch { fail(error) }
    }

    func waitForLaunch() {
        let deadline = Date().addingTimeInterval(40)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self = self, let app = self.app else { timer.invalidate(); return }
            if app.isTerminated { timer.invalidate(); self.fail(ProbeError("App exited before launch completed")); return }
            if app.isFinishedLaunching {
                timer.invalidate()
                self.schedule(2) {
                    self.runPhase("00-original") {
                        if self.usesCDP { self.connectDebugger() }
                        else { self.apply("black", phase: "01-black-natural") }
                    }
                }
            } else if Date() > deadline {
                timer.invalidate(); self.fail(ProbeError("Application launch did not complete"))
            }
        }
    }

    func schedule(_ seconds: Double, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
    }

    func runPhase(_ name: String, next: @escaping () -> Void) {
        do {
            let capture = try command("/usr/sbin/screencapture", ["-x", output.appendingPathComponent(name + "-screen.png").path])
            let workspaceImage = NSWorkspace.shared.icon(forFile: target.path)
            if let data = workspaceImage.tiffRepresentation { try data.write(to: output.appendingPathComponent(name + "-workspace-icon.tiff")) }
            if let data = app?.icon?.tiffRepresentation { try data.write(to: output.appendingPathComponent(name + "-running-icon.tiff")) }
            let windows = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []).filter {
                ($0[kCGWindowOwnerName as String] as? String) == "Dock"
            }.map { window in window.mapValues { String(describing: $0) } }
            let phase = try Phase(name: name, pid: app?.processIdentifier,
                                  sameRunningProcess: app?.processIdentifier == originalPID && app?.isTerminated == false,
                                  targetBundleURL: target.standardizedFileURL.resolvingSymlinksInPath().path,
                                  runningBundleURL: app?.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path,
                                  runningExecutableURL: app?.executableURL?.standardizedFileURL.resolvingSymlinksInPath().path,
                                  runningTargetMatches: app?.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path == target.standardizedFileURL.resolvingSymlinksInPath().path,
                                  processCommand: command("/bin/ps", ["-p", String(app?.processIdentifier ?? -1), "-o", "pid=,comm=,args="]),
                                  dockPreferences: command("/usr/bin/defaults", ["export", "com.apple.dock", "-"]),
                                  dockAccessibility: dockAccessibility(),
                                  defaultVerify: command("/usr/bin/codesign", ["--verify", "--deep", "--verbose=4", target.path]),
                                  strictVerify: command("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=4", target.path]),
                                  gatekeeper: command("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=4", "--ignore-cache", target.path]),
                                  signature: command("/usr/bin/codesign", ["--display", "--verbose=4", target.path]),
                                  contentsUnchanged: contentsManifest(target) == originalManifest,
                                  metadata: Metadata(target), screenshot: capture, dockWindows: windows)
            phases.append(phase)
            try writeJSON(phases, output.appendingPathComponent("phases.json"))
            print("\(name): pid=\(phase.pid ?? -1) samePID=\(phase.sameRunningProcess) normal=\(phase.defaultVerify.status) strict=\(phase.strictVerify.status) spctl=\(phase.gatekeeper.status) unchangedContents=\(phase.contentsUnchanged) screenshot=\(capture.status)")
            guard phase.sameRunningProcess, phase.runningTargetMatches, phase.contentsUnchanged, phase.defaultVerify.status == 0 else {
                throw ProbeError("\(name): process/content/normal-signature invariant failed")
            }
            let cdhash = phase.signature.output.split(separator: "\n").filter { $0.hasPrefix("CDHash=") }.joined(separator: "\n")
            if let before = baselineCDHash {
                guard cdhash == before else { throw ProbeError("Original code directory hash changed") }
            } else { baselineCDHash = cdhash }
            if actualAside && phase.gatekeeper.status != 0 {
                throw ProbeError("\(name): actual notarized Aside no longer passes uncached Gatekeeper assessment")
            }
            if capture.status != 0 {
                failed = true
                errors.append("\(name): screen capture unavailable; visual Dock behavior remains unverified")
            }
            next()
        } catch { fail(error) }
    }

    func apply(_ icon: String, phase: String) {
        do {
            guard let image = NSImage(contentsOf: assets.appendingPathComponent(icon + ".png")),
                  NSWorkspace.shared.setIcon(image, forFile: target.path, options: []) else {
                throw ProbeError("NSWorkspace.setIcon refused approved \(icon) icon")
            }
            // These delays only schedule observation of Dock repaint; they never
            // suppress a failed assertion or substitute for metadata correctness.
            schedule(3) {
                self.runPhase(phase) {
                    if icon == "black" {
                        self.refreshDockIfRequested(phase: "02-black-dock-refreshed") {
                            self.apply("white", phase: "03-white-natural")
                        }
                    } else {
                        self.refreshDockIfRequested(phase: "04-white-dock-refreshed") { self.finish() }
                    }
                }
            }
        } catch { fail(error) }
    }

    func connectDebugger() {
        let deadline = Date().addingTimeInterval(25)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self = self, let profile = ProcessInfo.processInfo.environment["ASIDE_PROBE_PROFILE"] else { timer.invalidate(); return }
            let portFile = URL(fileURLWithPath: profile).appendingPathComponent("DevToolsActivePort")
            if let data = try? String(contentsOf: portFile, encoding: .utf8) {
                let lines = data.split(separator: "\n")
                if lines.count >= 2, let port = Int(lines[0]), (1...65535).contains(port), lines[1].hasPrefix("/devtools/browser/"),
                   let endpoint = URL(string: "ws://127.0.0.1:\(port)\(lines[1])") {
                    timer.invalidate()
                    self.socket = URLSession.shared.webSocketTask(with: endpoint)
                    self.socket?.resume()
                    self.applyCDP("black", phase: "01-black-cdp")
                    return
                }
            }
            if Date() > deadline { timer.invalidate(); self.fail(ProbeError("The isolated profile did not publish DevToolsActivePort")) }
        }
    }

    func applyCDP(_ color: String, phase: String) {
        do {
            guard let socket = socket else { throw ProbeError("No isolated browser CDP socket") }
            commandID += 1
            let id = commandID
            let png = try Data(contentsOf: assets.appendingPathComponent(color + ".png"))
            let request: [String: Any] = ["id": id, "method": "Browser.setDockTile", "params": ["image": png.base64EncodedString()]]
            let message = try JSONSerialization.data(withJSONObject: request)
            socket.send(.string(String(decoding: message, as: UTF8.self))) { [weak self] error in
                guard let self = self else { return }
                if let error = error { DispatchQueue.main.async { self.fail(error) }; return }
                self.receiveCDP(id: id, color: color, phase: phase)
            }
        } catch { fail(error) }
    }

    func receiveCDP(id: Int, color: String, phase: String) {
        socket?.receive { [weak self] result in
            guard let self = self else { return }
            do {
                let message = try result.get()
                let data: Data
                switch message {
                case .string(let string): data = Data(string.utf8)
                case .data(let value): data = value
                @unknown default: throw ProbeError("Unknown CDP transport message")
                }
                guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProbeError("Malformed CDP response") }
                if response["id"] as? Int != id { self.receiveCDP(id: id, color: color, phase: phase); return }
                try data.write(to: self.output.appendingPathComponent(phase + "-cdp-response.json"))
                if let error = response["error"] { throw ProbeError("Browser.setDockTile rejected: \(error)") }
                DispatchQueue.main.async {
                    self.schedule(3) {
                        self.runPhase(phase) {
                            if color == "black" { self.applyCDP("white", phase: "02-white-cdp") }
                            else { self.finish() }
                        }
                    }
                }
            } catch { DispatchQueue.main.async { self.fail(error) } }
        }
    }

    func refreshDockIfRequested(phase: String, next: @escaping () -> Void) {
        if ProcessInfo.processInfo.environment["ASIDE_DOCK_PROBE_REFRESH"] == "1" {
            do {
                guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" else {
                    throw ProbeError("Dock refresh is allowed only in an ephemeral GitHub runner")
                }
                NSWorkspace.shared.noteFileSystemChanged(target.path)
                let registration = LSRegisterURL(target as CFURL, true)
                try writeJSON(CommandResult(status: registration, output: "NSWorkspace.noteFileSystemChanged + LSRegisterURL(update:true)"), output.appendingPathComponent(phase + "-platform-cache-command.json"))
                guard registration == 0 else { throw ProbeError("LaunchServices registration refresh failed") }
                schedule(2) {
                    self.runPhase(phase.replacingOccurrences(of: "dock-refreshed", with: "platform-notified")) {
                        do {
                            let refresh = try command("/usr/bin/killall", ["Dock"])
                            try writeJSON(refresh, self.output.appendingPathComponent(phase + "-dock-command.json"))
                            guard refresh.status == 0 else { throw ProbeError("Dock refresh failed") }
                            self.schedule(3) { self.runPhase(phase, next: next) }
                        } catch { self.fail(error) }
                    }
                }
            } catch { fail(error) }
        } else { next() }
    }

    func fail(_ error: Error) {
        failed = true
        errors.append(error.localizedDescription)
        fputs(error.localizedDescription + "\n", stderr)
        finish()
    }

    func finish() {
        timer?.invalidate()
        socket?.cancel(with: .normalClosure, reason: nil)
        do {
            if let originalMetadata = originalMetadata { try originalMetadata.restore(target) }
            let after = try contentsManifest(target)
            try writeJSON(after, output.appendingPathComponent("contents-restored.json"))
            guard after == originalManifest else { throw ProbeError("Signed Contents changed after restore") }
            let restored = try command("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=4", target.path])
            try writeJSON(restored, output.appendingPathComponent("strict-restored.json"))
            guard restored.status == 0 else { throw ProbeError("Restored strict signature did not pass: " + restored.output) }
        } catch { failed = true; errors.append(error.localizedDescription) }
        try? writeJSON(errors, output.appendingPathComponent("errors.json"))
        // This PID belongs only to the explicitly launched isolated diagnostic app.
        if let app = app, !app.isTerminated { _ = app.terminate() }
        print("Diagnostic \(failed ? "FAILED" : "completed"). Screenshots require human review; no automatic Dock appearance success claim is made.")
        schedule(1) { exit(self.failed ? 1 : 0) }
    }
}

final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 570, height: 170), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Disposable Aside Dock Probe Fixture"
        let label = NSTextField(wrappingLabelWithString: "This signed fixture stays running while NSWorkspace customizes its file icon. Inspect its real Dock tile in captured screenshots.")
        label.frame = NSRect(x: 30, y: 45, width: 510, height: 80)
        window.contentView?.addSubview(label)
        window.center(); window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
}

let application = NSApplication.shared
if CommandLine.arguments.contains("--fixture-window") {
    let delegate = FixtureDelegate()
    application.delegate = delegate
    application.run()
} else {
    guard CommandLine.arguments.count == 5 else {
        fputs("Usage: dock-probe target.app assets-directory output-directory fixture|aside\n", stderr)
        exit(2)
    }
    let delegate = DockProbe(target: URL(fileURLWithPath: CommandLine.arguments[1]),
                             assets: URL(fileURLWithPath: CommandLine.arguments[2]),
                             output: URL(fileURLWithPath: CommandLine.arguments[3]),
                             actualAside: CommandLine.arguments[4] == "aside")
    application.delegate = delegate
    application.run()
}
