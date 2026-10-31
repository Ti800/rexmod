import AppKit
import CoreServices
import Foundation

enum RM {
    static let home = NSHomeDirectory()
    static let defaults = UserDefaults.standard

    static var rexmodPath: String = {
        let link = home + "/.local/bin/rexmod"
        if let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: link) {
            return dest.hasPrefix("/") ? dest : (link as NSString).deletingLastPathComponent + "/" + dest
        }
        if FileManager.default.isExecutableFile(atPath: link) { return link }
        return home + "/Library/Application Support/rexmod/bin/rexmod"
    }()

    static let env: [String: String] = {
        var e = ProcessInfo.processInfo.environment
        let extra = [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        e["PATH"] = (extra + (e["PATH"].map { [$0] } ?? [])).joined(separator: ":")
        e.removeValue(forKey: "DYLD_INSERT_LIBRARIES")
        return e
    }()

    static let cacheDir: URL = {
        let u = URL(fileURLWithPath: home + "/Library/Caches/rexmod", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    private static let logURL = URL(fileURLWithPath: home + "/Library/Logs/rexmod-panel.log")
    private static let logQueue = DispatchQueue(label: "rexmod.log")

    static func log(_ msg: @autoclosure () -> String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg())\n"
        logQueue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let h = try? FileHandle(forWritingTo: logURL) {
                h.seekToEndOfFile()
                h.write(data)
                try? h.close()
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    /// The session the Rex app shows, as the app itself records it.
    static func focusedSessionID() -> String? {
        let key = "Workspace.lastFocusedSession"
        var data = defaults.data(forKey: key)
        if data == nil, let s = defaults.string(forKey: key) { data = s.data(using: .utf8) }
        guard let d = data,
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let id = obj["sessionID"] as? String, !id.isEmpty
        else { return nil }
        return id
    }
}

/// Runs rexmod off the main thread and reports back on the main thread.
enum Shell {
    private static let queue = DispatchQueue(label: "rexmod.shell", qos: .userInitiated, attributes: .concurrent)

    static func rexmod(_ args: [String], timeout: TimeInterval = 25,
                       completion: @escaping (_ status: Int32, _ out: Data, _ err: String) -> Void) {
        run(RM.rexmodPath, args, timeout: timeout, completion: completion)
    }

    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 25,
                    completion: @escaping (_ status: Int32, _ out: Data, _ err: String) -> Void) {
        queue.async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            p.environment = RM.env
            p.currentDirectoryURL = URL(fileURLWithPath: RM.home)
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.standardInput = FileHandle.nullDevice
            var errData = Data()
            let errGroup = DispatchGroup()
            errGroup.enter()
            DispatchQueue.global().async {
                errData = err.fileHandleForReading.readDataToEndOfFile()
                errGroup.leave()
            }
            do {
                try p.run()
            } catch {
                DispatchQueue.main.async { completion(-1, Data(), "\(error)") }
                return
            }
            let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            killer.cancel()
            _ = errGroup.wait(timeout: .now() + 2)
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            let status = p.terminationStatus
            DispatchQueue.main.async { completion(status, data, errStr) }
        }
    }
}

/// Watches directories with FSEvents and reports changed paths, coalesced.
final class FSWatcher {
    private var stream: FSEventStreamRef?
    private let callback: ([String]) -> Void

    init?(paths: [String], latency: CFTimeInterval = 0.35, callback: @escaping ([String]) -> Void) {
        self.callback = callback
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
        let cb: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info = info else { return }
            let me = Unmanaged<FSWatcher>.fromOpaque(info).takeUnretainedValue()
            let arr = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray
            var paths: [String] = []
            for i in 0..<min(count, arr.count) {
                if let s = arr[i] as? String { paths.append(s) }
            }
            me.callback(paths)
        }
        guard let s = FSEventStreamCreate(kCFAllocatorDefault, cb, &ctx, paths as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        else { return nil }
        stream = s
        FSEventStreamSetDispatchQueue(s, DispatchQueue.main)
        FSEventStreamStart(s)
    }

    deinit {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
    }
}
