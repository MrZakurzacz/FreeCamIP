import SwiftUI

@main
struct FreeCamIPApp: App {
    @StateObject private var model = FreeCamModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}
