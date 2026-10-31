import SwiftUI

@main
struct BrainApp: App {
    @State private var store: ChatStore

    init() {
        SharedModels.configure()
        _store = State(initialValue: ChatStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
        }
    }
}
