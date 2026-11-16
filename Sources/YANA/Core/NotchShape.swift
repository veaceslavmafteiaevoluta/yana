import SwiftUI

/// Notch-like shape: concave "ears" at the top, rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let rt = topRadius
        let rb = max(0, min(bottomRadius, rect.height - rt, (rect.width - 2 * rt) / 2))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + rt, y: rect.minY + rt), control: CGPoint(x: rect.minX + rt, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + rt, y: rect.maxY - rb))
        p.addQuadCurve(to: CGPoint(x: rect.minX + rt + rb, y: rect.maxY), control: CGPoint(x: rect.minX + rt, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - rt - rb, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - rt, y: rect.maxY - rb), control: CGPoint(x: rect.maxX - rt, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - rt, y: rect.minY + rt))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - rt, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
