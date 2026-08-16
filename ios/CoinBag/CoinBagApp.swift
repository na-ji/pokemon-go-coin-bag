import SwiftUI

@main
struct CoinBagApp: App {
    @StateObject private var client = BleClient()

    var body: some Scene {
        WindowGroup {
            StatusView(client: client)
        }
    }
}
