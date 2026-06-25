import SwiftUI

/// A lightweight stand-in for the Claude "sunburst" mark, drawn with SwiftUI so the app has a
/// recognizable glyph with no binary asset. Replace with the official asset if you have rights.
struct ClaudeMark: View {
    var size: CGFloat = 14
    var color: Color = .primary

    var body: some View {
        Canvas { ctx, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = min(canvasSize.width, canvasSize.height) / 2
            let spokes = 12
            for i in 0..<spokes {
                let angle = (Double(i) / Double(spokes)) * 2 * .pi
                var path = Path()
                let inner = radius * 0.18
                let outer = radius * 0.95
                let p1 = CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner)
                let p2 = CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer)
                path.move(to: p1)
                path.addLine(to: p2)
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: max(1, size * 0.12), lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }
}
