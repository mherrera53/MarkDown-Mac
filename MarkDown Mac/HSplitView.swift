import SwiftUI
import AppKit

struct HSplitView<Left: View, Right: View>: NSViewRepresentable {
    let left: Left
    let right: Right
    
    init(@ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self.left = left()
        self.right = right()
    }
    
    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        
        // Add arranged subviews from hosting controllers in coordinator
        splitView.addArrangedSubview(context.coordinator.leftHosting.view)
        splitView.addArrangedSubview(context.coordinator.rightHosting.view)
        
        // Set equal widths initially
        DispatchQueue.main.async {
            splitView.setPosition(splitView.bounds.width / 2, ofDividerAt: 0)
        }
        
        return splitView
    }
    
    func updateNSView(_ splitView: NSSplitView, context: Context) {
        context.coordinator.leftHosting.rootView = left
        context.coordinator.rightHosting.rootView = right
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(left: left, right: right)
    }
    
    class Coordinator {
        var leftHosting: NSHostingController<Left>
        var rightHosting: NSHostingController<Right>
        
        init(left: Left, right: Right) {
            self.leftHosting = NSHostingController(rootView: left)
            self.rightHosting = NSHostingController(rootView: right)
            
            // Basic setup
            leftHosting.view.translatesAutoresizingMaskIntoConstraints = false
            rightHosting.view.translatesAutoresizingMaskIntoConstraints = false
        }
    }
}
