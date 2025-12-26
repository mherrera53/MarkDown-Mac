import SwiftUI
import PencilKit

// MARK: - Shape Tool for Drawing Geometric Shapes
// This adds Minimal.app-style shape drawing capabilities

enum ShapeType: String, CaseIterable {
    case rectangle = "Rectangle"
    case circle = "Circle"
    case triangle = "Triangle"
    case arrow = "Arrow"
    case line = "Line"
    case star = "Star"
    
    var icon: String {
        switch self {
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .triangle: return "triangle"
        case .arrow: return "arrow.right"
        case .line: return "line.diagonal"
        case .star: return "star"
        }
    }
}

struct ShapeDrawingOverlay: View {
    @Binding var drawing: PKDrawing
    @Binding var isActive: Bool
    let selectedShape: ShapeType
    let color: Color
    let lineWidth: CGFloat
    
    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?
    @State private var isDragging = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent hit area
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if startPoint == nil {
                                    startPoint = value.startLocation
                                }
                                currentPoint = value.location
                                isDragging = true
                            }
                            .onEnded { value in
                                if let start = startPoint, let end = currentPoint {
                                    addShapeToDrawing(from: start, to: end)
                                }
                                startPoint = nil
                                currentPoint = nil
                                isDragging = false
                            }
                    )
                
                // Preview of shape while dragging
                if isDragging, let start = startPoint, let current = currentPoint {
                    shapePreview(from: start, to: current)
                }
            }
        }
    }
    
    @ViewBuilder
    private func shapePreview(from start: CGPoint, to end: CGPoint) -> some View {
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        
        let shapeColor = Color(nsColor: NSColor(color))
        
        switch selectedShape {
        case .rectangle:
            Rectangle()
                .path(in: rect)
                .stroke(shapeColor, lineWidth: lineWidth)
        case .circle:
            Ellipse()
                .path(in: rect)
                .stroke(shapeColor, lineWidth: lineWidth)
        case .triangle:
            TriangleShape()
                .path(in: rect)
                .stroke(shapeColor, lineWidth: lineWidth)
        case .arrow:
            ArrowShape()
                .path(in: rect)
                .stroke(shapeColor, lineWidth: lineWidth)
        case .line:
            LineShape(start: start, end: end)
                .stroke(shapeColor, lineWidth: lineWidth)
        case .star:
            StarShape()
                .path(in: rect)
                .stroke(shapeColor, lineWidth: lineWidth)
        }
    }
    
    private func addShapeToDrawing(from start: CGPoint, to end: CGPoint) {
        // Convert SwiftUI shape to PKDrawing strokes
        let path = createBezierPath(from: start, to: end)
        let ink = PKInk(.pen, color: NSColor(color))
        
        // Create stroke from path
        var points: [PKStrokePoint] = []
        _ = path.currentPoint
        
        // Sample points along the path
        let steps = 100
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            if let point = path.point(at: t) {
                let pkPoint = PKStrokePoint(
                    location: point,
                    timeOffset: TimeInterval(i) * 0.01,
                    size: CGSize(width: lineWidth, height: lineWidth),
                    opacity: 1.0,
                    force: 1.0,
                    azimuth: 0,
                    altitude: 0
                )
                points.append(pkPoint)
            }
        }
        
        if !points.isEmpty {
            let stroke = PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: Date()))
            
            // Add stroke to drawing
            var newStrokes = drawing.strokes
            newStrokes.append(stroke)
            drawing = PKDrawing(strokes: newStrokes)
        }
    }
    
    private func createBezierPath(from start: CGPoint, to end: CGPoint) -> NSBezierPath {
        let path = NSBezierPath()
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        
        switch selectedShape {
        case .rectangle:
            path.appendRect(rect)
        case .circle:
            path.appendOval(in: rect)
        case .triangle:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.line(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.line(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.close()
        case .arrow:
            // Arrow body
            path.move(to: start)
            path.line(to: end)
            // Arrow head
            let angle = atan2(end.y - start.y, end.x - start.x)
            let arrowLength: CGFloat = 20
            let arrowAngle: CGFloat = .pi / 6
            
            let point1 = CGPoint(
                x: end.x - arrowLength * cos(angle - arrowAngle),
                y: end.y - arrowLength * sin(angle - arrowAngle)
            )
            let point2 = CGPoint(
                x: end.x - arrowLength * cos(angle + arrowAngle),
                y: end.y - arrowLength * sin(angle + arrowAngle)
            )
            
            path.move(to: end)
            path.line(to: point1)
            path.move(to: end)
            path.line(to: point2)
        case .line:
            path.move(to: start)
            path.line(to: end)
        case .star:
            let points = starPoints(in: rect)
            if let first = points.first {
                path.move(to: first)
                for point in points.dropFirst() {
                    path.line(to: point)
                }
                path.close()
            }
        }
        
        return path
    }
    
    private func starPoints(in rect: CGRect) -> [CGPoint] {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.4
        let points = 5
        
        var result: [CGPoint] = []
        for i in 0..<points * 2 {
            let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            result.append(point)
        }
        return result
    }
}

// MARK: - Custom Shapes

struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let start = CGPoint(x: rect.minX, y: rect.midY)
        let end = CGPoint(x: rect.maxX, y: rect.midY)
        
        // Arrow body
        path.move(to: start)
        path.addLine(to: end)
        
        // Arrow head
        let headLength: CGFloat = min(rect.width * 0.2, 30)
        let headWidth: CGFloat = headLength * 0.6
        
        path.move(to: end)
        path.addLine(to: CGPoint(x: end.x - headLength, y: end.y - headWidth))
        path.move(to: end)
        path.addLine(to: CGPoint(x: end.x - headLength, y: end.y + headWidth))
        
        return path
    }
}

struct LineShape: Shape {
    let start: CGPoint
    let end: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }
}

struct StarShape: Shape {
    var points: Int = 5
    var innerRadius: CGFloat = 0.4
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let actualInnerRadius = outerRadius * innerRadius
        
        for i in 0..<points * 2 {
            let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let radius = i % 2 == 0 ? outerRadius : actualInnerRadius
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

// Extension to get point along NSBezierPath
extension NSBezierPath {
    func point(at t: CGFloat) -> CGPoint? {
        guard elementCount > 0 else { return nil }
        
        var totalLength: CGFloat = 0
        var lengths: [CGFloat] = []
        
        // Calculate total length
        for i in 0..<elementCount {
            var points = [NSPoint](repeating: .zero, count: 3)
            let type = element(at: i, associatedPoints: &points)
            
            switch type {
            case .lineTo:
                if i > 0 {
                    var prevPoints = [NSPoint](repeating: .zero, count: 3)
                    _ = element(at: i - 1, associatedPoints: &prevPoints)
                    let length = hypot(points[0].x - prevPoints[0].x, points[0].y - prevPoints[0].y)
                    lengths.append(length)
                    totalLength += length
                }
            default:
                break
            }
        }
        
        let targetLength = totalLength * t
        var accumulatedLength: CGFloat = 0
        
        for i in 0..<elementCount {
            var points = [NSPoint](repeating: .zero, count: 3)
            let type = element(at: i, associatedPoints: &points)
            
            if type == .lineTo && i > 0 {
                let segmentLength = lengths[min(i - 1, lengths.count - 1)]
                if accumulatedLength + segmentLength >= targetLength {
                    // Interpolate within this segment
                    var prevPoints = [NSPoint](repeating: .zero, count: 3)
                    _ = element(at: i - 1, associatedPoints: &prevPoints)
                    
                    let segmentT = (targetLength - accumulatedLength) / segmentLength
                    return CGPoint(
                        x: prevPoints[0].x + (points[0].x - prevPoints[0].x) * segmentT,
                        y: prevPoints[0].y + (points[0].y - prevPoints[0].y) * segmentT
                    )
                }
                accumulatedLength += segmentLength
            }
        }
        
        return currentPoint
    }
}
