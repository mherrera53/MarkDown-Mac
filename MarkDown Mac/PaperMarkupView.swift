import SwiftUI
import PencilKit
import AppKit

// MARK: - Canvas Wrapper with Maximum Compatibility
// NOTE: We use dynamic loading (NSClassFromString) because standard PencilKit imports 
// are failing to expose PKCanvasView in this specific build target scope.
struct PaperMarkupView: NSViewRepresentable {
    @Binding var drawing: PKDrawing
    let tool: ContentView.DrawingTool
    let color: Color
    let width: CGFloat
    // Callback passes Any because PKCanvasView is not visible in compile-time scope
    var onCanvasCreated: ((Any) -> Void)? = nil

    func makeNSView(context: Context) -> NSView {
        print("🎨 [Canvas] Creating dynamic canvas view...")
        
        // 1. Create a CUSTOM container view that handles hit testing
        // Standard NSView would let clicks pass through if transparent.
        // This is CRITICAL for drawing to work!
        let containerView = TouchableContainerView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        
        // 2. Dynamic loading of PKCanvasView to bypass build errors
        let canvasClassName = "PKCanvasView"
        guard let canvasClass = NSClassFromString(canvasClassName) as? NSView.Type else {
            print("❌ [ERROR] Could not find PKCanvasView class")
            return NSView()
        }
        
        let canvasView = canvasClass.init()
        // Enable Auto Layout for constraints
        canvasView.translatesAutoresizingMaskIntoConstraints = false
                
        // 3. Add canvas to container
        containerView.addSubview(canvasView)
        // Store reference for hit testing
        containerView.canvasView = canvasView
        
        // 4. Pin canvas to edges of container using Auto Layout
        NSLayoutConstraint.activate([
            canvasView.topAnchor.constraint(equalTo: containerView.topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            canvasView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])
        
        print("📏 [Layout] Constraints activated. Container frame: \(containerView.frame), Canvas frame: \(canvasView.frame)")
        
        // 5. Configure standard properties via Key-Value Coding (KVC)
        canvasView.setValue(drawing, forKey: "drawing")
        
        // Set contentSize for scrolling (Critical for macOS)
        if canvasView.responds(to: Selector(("setContentSize:"))) {
            canvasView.setValue(CGSize(width: 5000, height: 5000), forKey: "contentSize")
        }
        
        // Ensure transparency (Modified for Debugging: Yellow tint to verify existence)
        if canvasView.responds(to: Selector(("setBackgroundColor:"))) {
            // 🟡 DEBUG: Faint yellow to confirm view frame exists. If you see this, the view is there.
            let debugColor = NSColor.systemYellow.withAlphaComponent(0.1)
            canvasView.setValue(debugColor, forKey: "backgroundColor")
        }
        
        if canvasView.responds(to: Selector(("setOpaque:"))) {
            canvasView.setValue(false, forKey: "opaque")
        }
        
        // drawingPolicy: 1 = anyInput
        // CRITICAL: Force this again
        if canvasView.responds(to: Selector(("setDrawingPolicy:"))) {
            canvasView.setValue(1, forKey: "drawingPolicy")
        }
        
        // Set delegate to coordinator
        if canvasView.responds(to: Selector(("setDelegate:"))) {
            canvasView.setValue(context.coordinator, forKey: "delegate")
        }
        
        // Disable scrollbars to look like a clean overlay
         if let scrollView = canvasView as? NSScrollView {
             scrollView.hasVerticalScroller = false
             scrollView.hasHorizontalScroller = false
             scrollView.drawsBackground = false
             
             // ⚡️ NUCLEAR OPTION: Disable magnification to prevent gesture conflicts?
             // scrollView.allowsMagnification = false
         }

        updateTool(on: canvasView)
        
        print("✅ [Canvas] Canvas created successfully via Dynamic Loading")
        
        // Notify parent and Force Focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onCanvasCreated?(canvasView)
            canvasView.window?.makeFirstResponder(canvasView)
            print("⚡️ [Focus] Requested first responder for canvas (Delayed)")
        }
        
        // Start Diagnostic Monitor
        startDiagnosticMonitor(for: canvasView)
        
        return containerView
    }

    func startDiagnosticMonitor(for canvasView: NSView) {
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            DispatchQueue.main.async {
                print("🔍 [Monitor] --- Canvas State ---")
                
                // Check Frame
                print("   - Frame: \(canvasView.frame)")
                
                // Check Document View (Size)
                if let scrollView = canvasView as? NSScrollView, let docView = scrollView.documentView {
                    print("   - DocView: \(docView.className) | Frame: \(docView.frame)")
                } else {
                    print("   - DocView: NIL (Critical Failure)")
                }
                
                // Check Tool
                if let t = canvasView.value(forKey: "tool") {
                    print("   - Tool: \(t)")
                } else {
                    print("   - Tool: NIL")
                }
                
                // Check Policy
                if let p = canvasView.value(forKey: "drawingPolicy") {
                    print("   - Policy: \(p) (Expect 1 for anyInput)")
                }
                
                print("-----------------------------")
            }
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // nsView is now the container. We need to find the canvas subview.
        guard let canvasView = nsView.subviews.first(where: { $0.className.contains("PKCanvasView") }) else {
            print("⚠️ [Canvas] Could not find embedded PKCanvasView")
            return
        }
        
        // Synchronize drawing if it changed externally
        if let currentDrawing = canvasView.value(forKeyPath: "drawing") as? PKDrawing {
            if currentDrawing.strokes.count != drawing.strokes.count {
                print("🔄 [Canvas] Drawing updated externaly: \(drawing.strokes.count) strokes")
                canvasView.setValue(drawing, forKey: "drawing")
            }
        }
        
        // CRITICAL: Ensure drawing policy persists
        if canvasView.responds(to: Selector(("setDrawingPolicy:"))) {
             canvasView.setValue(1, forKey: "drawingPolicy")
        }
        
        updateTool(on: canvasView)
    }

    private func updateTool(on canvasView: NSView) {
        let nsColor = NSColor(color)
        var pkTool: Any? // Use Any? to hold the bridged NSObject
        
        // Dynamic instantiation for ALL tools
        // KEY FIX: PKInkingTool is a Swift Struct. We must bridge it to AnyObject/NSObject for KVC to work!
        switch tool {
        case .pen:
            pkTool = PKInkingTool(.pen, color: nsColor, width: width) as? NSObject
        case .pencil:
            pkTool = PKInkingTool(.pencil, color: nsColor, width: width) as? NSObject
        case .marker:
            pkTool = PKInkingTool(.marker, color: nsColor, width: width) as? NSObject
        case .eraser:
             pkTool = PKEraserTool(.vector) as? NSObject
        case .lasso:
             pkTool = PKLassoTool() as? NSObject
        case .ruler:
             pkTool = PKInkingTool(.pen, color: nsColor, width: width) as? NSObject
        }
        
        // FALLBACK: If tool somehow failed, force a pen (bridged)
        if pkTool == nil {
            print("⚠️ [Tool] Tool init failed, forcing Fallback Pen (Bridged)")
            pkTool = PKInkingTool(.pen, color: .black, width: 1.0) as? NSObject
        }
        
        if let tool = pkTool, canvasView.responds(to: Selector(("setTool:"))) {
            canvasView.setValue(tool, forKey: "tool")
            print("🖌️ [Tool] Set tool to: \(tool)")
            
            // Verify if it stuck? (Read back)
            if let activeTool = canvasView.value(forKey: "tool") {
                print("   -> [Verify] Canvas active tool: \(activeTool)")
            }
        } else {
            print("❌ [ERROR] Failed to set tool via KVC (Tool: \(String(describing: pkTool)))")
        }
        
        // Handle Ruler Toggle (dynamic KVC)
        if canvasView.responds(to: Selector(("setRulerActive:"))) {
            canvasView.setValue(tool == .ruler, forKey: "rulerActive")
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: PaperMarkupView

        init(_ parent: PaperMarkupView) {
            self.parent = parent
        }
        
        // Matches PKCanvasViewDelegate: func canvasViewDrawingDidChange(_ canvasView: PKCanvasView)
        @objc func canvasViewDrawingDidChange(_ canvasView: NSView) {
            if let newDrawing = canvasView.value(forKey: "drawing") as? PKDrawing {
                DispatchQueue.main.async {
                    if self.parent.drawing.strokes.count != newDrawing.strokes.count {
                        print("✏️ [Canvas] Drawing changed: \(self.parent.drawing.strokes.count) -> \(newDrawing.strokes.count)")
                        self.parent.drawing = newDrawing
                    }
                }
            }
        }
    }
}

// Custom container that forces hit testing to succeed even on transparent areas.
// STRATEGY CHANGE: We capture the event OURSELVES and forward it to the canvas.
// This prevents the canvas from rejecting it due to internal hit-test logic.
class TouchableContainerView: NSView {
    weak var canvasView: NSView?
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // NUCLEAR HIT TEST V2:
        // Return the internal Document View directly.
        // This ensures the event goes to the actual drawing surface, not just the scroll wrapper.
        
        let convertedPoint = self.convert(point, from: superview)
        if self.bounds.contains(convertedPoint) {
           
            if let scrollView = canvasView as? NSScrollView, let docView = scrollView.documentView {
                // print("🎯 [HitTest] Returning DocumentView: \(docView.className)")
                return docView
            }
            
            // Fallback
            return canvasView ?? self
        }
        return nil
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    // REMOVED: Manual Event Forwarding. logic is now handled by returning the correct view in hitTest.
    /*
    override func mouseDown(with event: NSEvent) {
        // print("👇 [Container] Forwarding mouseDown")
        canvasView?.mouseDown(with: event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        // print("〰️ [Container] Forwarding mouseDragged")
        canvasView?.mouseDragged(with: event)
    }
    
    override func mouseUp(with event: NSEvent) {
        // print("👆 [Container] Forwarding mouseUp")
        canvasView?.mouseUp(with: event)
    }
    */
}

// Helper to wrap the view with robust layout and hit-testing
struct RobustPaperCanvas: View {
    @Binding var drawing: PKDrawing
    let tool: ContentView.DrawingTool
    let color: Color
    let width: CGFloat
    var onCanvasCreated: ((Any) -> Void)? = nil
    
    var body: some View {
        PaperMarkupView(
            drawing: $drawing,
            tool: tool,
            color: color,
            width: width,
            onCanvasCreated: onCanvasCreated
        )
        // Ensure SwiftUI gives it space
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 🟢 DEBUG LAYOUT: Green Border to confirm frame size
        .border(Color.green, width: 2)
        .onAppear {
            print("🌟 [Canvas] RobustPaperCanvas appeared (Dynamic - Nuclear Mode)")
        }
    }
}
