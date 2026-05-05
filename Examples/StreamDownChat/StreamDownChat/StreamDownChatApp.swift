import SwiftUI

@main
struct StreamDownChatApp: App {
    @StateObject private var store = ChatStore()

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environmentObject(store)
        }
    }
}
