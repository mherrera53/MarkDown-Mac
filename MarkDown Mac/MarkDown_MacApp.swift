import SwiftUI
import PencilKit

@main
struct MarkDown_MacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow).ignoresSafeArea())
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
    }
}

