// Diagnostic only. Never included in the installer or used against a user's app.
import AppKit
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
    let base = target.appendingPathComponent("Contents")
    guard let walker = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
        throw ProbeError("Cannot enumerate signed Contents")
    }
    var files: [String: String] = [:]
    for case let url as URL in walker {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        let relative = String(url.path.dropFirst(base.path.count + 1))
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
    let defaultVerify: CommandResult
    let strictVerify: CommandResult
    let gatekeeper: CommandResult
    let signature: CommandResult
    let contentsUnchanged: Bool
    let metadata: Metadata
    let screenshot: CommandResult
    let dockWindows: [[String: String]]
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
                config.arguments = ["--user-data-dir=\(output.appendingPathComponent("isolated-profile").path)", "--no-first-run", "--no-default-browser-check", "about:blank"]
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
                self.schedule(2) { self.runPhase("00-original") { self.apply("black", phase: "01-black-natural") } }
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
                                  defaultVerify: command("/usr/bin/codesign", ["--verify", "--deep", "--verbose=4", target.path]),
                                  strictVerify: command("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=4", target.path]),
                                  gatekeeper: command("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=4", "--ignore-cache", target.path]),
                                  signature: command("/usr/bin/codesign", ["--display", "--verbose=4", target.path]),
                                  contentsUnchanged: contentsManifest(target) == originalManifest,
                                  metadata: Metadata(target), screenshot: capture, dockWindows: windows)
            phases.append(phase)
            try writeJSON(phases, output.appendingPathComponent("phases.json"))
            print("\(name): pid=\(phase.pid ?? -1) samePID=\(phase.sameRunningProcess) normal=\(phase.defaultVerify.status) strict=\(phase.strictVerify.status) spctl=\(phase.gatekeeper.status) unchangedContents=\(phase.contentsUnchanged) screenshot=\(capture.status)")
            guard phase.sameRunningProcess, phase.contentsUnchanged, phase.defaultVerify.status == 0 else {
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
                    if icon == "black" { self.apply("white", phase: "02-white-natural") }
                    else { self.refreshDockIfRequested() }
                }
            }
        } catch { fail(error) }
    }

    func refreshDockIfRequested() {
        if ProcessInfo.processInfo.environment["ASIDE_DOCK_PROBE_REFRESH"] == "1" {
            do {
                guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" else {
                    throw ProbeError("Dock refresh is allowed only in an ephemeral GitHub runner")
                }
                let refresh = try command("/usr/bin/killall", ["Dock"])
                try writeJSON(refresh, output.appendingPathComponent("dock-refresh-command.json"))
                guard refresh.status == 0 else { throw ProbeError("Dock refresh failed") }
                schedule(3) { self.runPhase("03-white-dock-refreshed") { self.finish() } }
            } catch { fail(error) }
        } else { finish() }
    }

    func fail(_ error: Error) {
        failed = true
        errors.append(error.localizedDescription)
        fputs(error.localizedDescription + "\n", stderr)
        finish()
    }

    func finish() {
        timer?.invalidate()
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
