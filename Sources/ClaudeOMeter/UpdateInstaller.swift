import Foundation
import AppKit

enum UpdateInstaller {
    enum InstallError: Error {
        case downloadFailed
        case unzipFailed
        case appNotFound
    }

    /// Downloads the zip, replaces /Applications/ClaudeOMeter.app via a helper script, then quits.
    static func install(from downloadURL: URL) async throws {
        // 1. Download zip
        var request = URLRequest(url: downloadURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("ClaudeOMeter", forHTTPHeaderField: "User-Agent")
        guard let (zipTemp, response) = try? await URLSession.shared.download(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw InstallError.downloadFailed
        }

        // Move zip to a stable temp path before URLSession cleans it up
        let zipPath = NSTemporaryDirectory() + "ClaudeOMeter_update.zip"
        try? FileManager.default.removeItem(atPath: zipPath)
        try FileManager.default.moveItem(at: zipTemp, to: URL(fileURLWithPath: zipPath))

        // 2. Unzip
        let destDir = NSTemporaryDirectory() + "ClaudeOMeter_update"
        try? FileManager.default.removeItem(atPath: destDir)
        try await runProcess("/usr/bin/unzip", args: ["-q", zipPath, "-d", destDir])

        let newAppPath = destDir + "/ClaudeOMeter.app"
        guard FileManager.default.fileExists(atPath: newAppPath) else {
            throw InstallError.appNotFound
        }

        // 3. Write a helper script that waits for us to exit, replaces the app, and relaunches
        let scriptPath = NSTemporaryDirectory() + "claudeometer_update.sh"
        let script = """
        #!/bin/bash
        sleep 2
        rm -rf "/Applications/ClaudeOMeter.app"
        cp -R "\(newAppPath)" "/Applications/ClaudeOMeter.app"
        xattr -dr com.apple.quarantine "/Applications/ClaudeOMeter.app" 2>/dev/null
        open "/Applications/ClaudeOMeter.app"
        rm -rf "\(destDir)"
        rm -f "\(zipPath)"
        rm -- "$0"
        """
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

        // 4. Launch the script detached, then quit so it can replace us
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptPath]
        try task.run()

        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    private static func runProcess(_ executable: String, args: [String]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            do {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: executable)
                p.arguments = args
                p.terminationHandler = { process in
                    if process.terminationStatus == 0 {
                        cont.resume()
                    } else {
                        cont.resume(throwing: NSError(domain: "UpdateInstaller",
                                                      code: Int(process.terminationStatus)))
                    }
                }
                try p.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
