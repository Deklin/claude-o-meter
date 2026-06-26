import SwiftUI
import AppKit

/// Claude Code robot icon loaded from the app bundle.
struct ClaudeMark: View {
    var size: CGFloat = 14
    var color: Color = .accentColor  // unused — kept for call-site compatibility

    var body: some View {
        BundleImage(name: "claude-code-icon", size: size)
    }
}

/// Loads a PNG from the app bundle by name, falling back to an SF Symbol.
struct BundleImage: View {
    let name: String
    let size: CGFloat
    var template: Bool = false
    var fallback: String = "cpu"

    private var nsImage: NSImage? {
        let res = Bundle.main.resourceURL
        let candidates = ["\(name)@2x.png", "\(name).png"]
        for file in candidates {
            if let url = res?.appendingPathComponent(file),
               let img = NSImage(contentsOf: url) {
                img.size = NSSize(width: size, height: size)
                if template { img.isTemplate = true }
                return img
            }
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "png",
                                     subdirectory: "ClaudeCostBar_ClaudeCostBar.bundle"),
           let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: size, height: size)
            if template { img.isTemplate = true }
            return img
        }
        return nil
    }

    var body: some View {
        if let img = nsImage {
            Image(nsImage: img)
                .renderingMode(template ? .template : .original)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallback)
                .font(.system(size: size * 0.8))
        }
    }
}
