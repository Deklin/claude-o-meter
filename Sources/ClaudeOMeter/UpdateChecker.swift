import Foundation
import AppKit

enum UpdateChecker {
    static let releasesPageURL = URL(string: "https://github.com/Deklin/claude-o-meter/releases")!

    private static let apiURL = URL(string: "https://api.github.com/repos/Deklin/claude-o-meter/releases/latest")!

    private struct Release: Decodable {
        let tagName: String
        enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
    }

    /// Returns the latest release version string if it is newer than `current`, otherwise nil.
    static func checkForUpdate(current: String) async -> String? {
        guard !current.isEmpty, current != "dev" else { return nil }

        var request = URLRequest(url: apiURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudeOMeter/\(current)", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data) else {
            return nil
        }

        let latest = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        return latest > current ? latest : nil
    }

    static func openReleasesPage() {
        NSWorkspace.shared.open(releasesPageURL)
    }
}
