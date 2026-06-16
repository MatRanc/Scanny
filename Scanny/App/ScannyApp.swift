import SwiftUI

@main
struct ScannyApp: App {
    @State private var store = DocumentStore()

    var body: some Scene {
        WindowGroup {
            DocumentListView()
                .environment(store)
                .tint(.blue)
        }
    }
}
