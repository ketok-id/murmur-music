import AppKit
import Foundation

/// In-app updater. Downloads a release's `Murmur.zip`, unpacks it, strips the
/// Gatekeeper quarantine flag (Murmur is ad-hoc signed, not notarized — the
/// download would otherwise be refused on relaunch), then hands off to a tiny
/// detached `/bin/sh` helper that waits for this process to quit, swaps the
/// bundle in place (with rollback), and relaunches.
///
/// Why a helper: a running `.app` can't overwrite its own bundle, so the swap
/// has to happen after we terminate. The orphaned shell is reparented to
/// launchd and keeps running once Murmur exits.
enum SelfUpdateError: LocalizedError {
    case notBundled
    case translocated
    case notWritable
    case http(Int)
    case toolFailed(String)
    case appNotFound

    var errorDescription: String? {
        switch self {
        case .notBundled:   return "Self-update only works in the packaged app."
        case .translocated: return "Move Murmur into Applications, then update."
        case .notWritable:  return "Can't write to Murmur's folder — move it to Applications."
        case .http(let c):  return "Download failed (HTTP \(c))."
        case .toolFailed(let m): return "Couldn't unpack the update: \(m)"
        case .appNotFound:  return "The update didn't contain Murmur.app."
        }
    }
}

enum SelfUpdater {
    /// Performs the full update. On success it terminates the app (the helper
    /// finishes the swap + relaunch), so this normally does not return; any
    /// failure throws before the app is touched on disk.
    @MainActor
    static func downloadAndInstall(zipURL: URL) async throws {
        let fm = FileManager.default
        let bundlePath = Bundle.main.bundlePath

        // Preconditions: must be a real, in-place, writable .app (not the
        // `swift run` binary and not a Gatekeeper-translocated read-only copy).
        guard bundlePath.hasSuffix(".app") else { throw SelfUpdateError.notBundled }
        guard !bundlePath.contains("/AppTranslocation/") else { throw SelfUpdateError.translocated }
        let parent = (bundlePath as NSString).deletingLastPathComponent
        guard fm.isWritableFile(atPath: parent) else { throw SelfUpdateError.notWritable }

        // Scratch workspace under the temp dir, cleaned up by the helper.
        let work = fm.temporaryDirectory.appendingPathComponent("MurmurUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        // 1. Download the zip.
        var req = URLRequest(url: zipURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (downloaded, response) = try await URLSession.shared.download(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SelfUpdateError.http(http.statusCode)
        }
        let zip = work.appendingPathComponent("Murmur.zip")
        try fm.moveItem(at: downloaded, to: zip)

        // 2. Unpack with ditto (handles the ditto-produced zip from build-app.sh).
        let unpacked = work.appendingPathComponent("unpacked")
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try runTool("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])

        // 3. Locate the new Murmur.app.
        guard let newApp = firstApp(in: unpacked, fm: fm) else { throw SelfUpdateError.appNotFound }

        // 4. Strip quarantine so the de-notarized ad-hoc build relaunches without
        //    Gatekeeper refusing it. Best-effort — ignore if the attr is absent.
        try? runTool("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

        // 5. Write + launch the detached swap/relaunch helper, then quit.
        let scriptURL = work.appendingPathComponent("install.sh")
        let pid = ProcessInfo.processInfo.processIdentifier
        try swapScript(pid: pid, newApp: newApp.path, dest: bundlePath, work: work.path)
            .write(to: scriptURL, atomically: true, encoding: .utf8)

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [scriptURL.path]
        try helper.run()   // orphaned on terminate; reparented to launchd

        NSApp.terminate(nil)
    }

    private static func firstApp(in dir: URL, fm: FileManager) -> URL? {
        let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return items.first { $0.pathExtension == "app" }
    }

    private static func runTool(_ launchPath: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw SelfUpdateError.toolFailed(msg.isEmpty ? "exit \(p.terminationStatus)" : msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Wait for the app (by pid) to exit, swap the bundle with rollback on
    /// failure, relaunch, then remove the scratch dir.
    private static func swapScript(pid: Int32, newApp: String, dest: String, work: String) -> String {
        """
        #!/bin/sh
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        sleep 0.3
        BACKUP="\(dest).bak"
        rm -rf "$BACKUP"
        if mv "\(dest)" "$BACKUP"; then
          if mv "\(newApp)" "\(dest)"; then
            rm -rf "$BACKUP"
          else
            rm -rf "\(dest)"
            mv "$BACKUP" "\(dest)"
          fi
        fi
        open "\(dest)"
        rm -rf "\(work)"
        """
    }
}
