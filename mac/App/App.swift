import SwiftUI

@main
struct BrainMacApp: App {
    var body: some Scene {
        WindowGroup(Notes.appName) {
            RootView().frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 1100, height: 760)
    }
}
