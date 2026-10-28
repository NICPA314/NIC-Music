import SwiftUI

// Simulator-only fixture host: exposes an independent Documents container to
// Files. Never a dependency of NICMusic and never included in the device IPA.
@main struct FixtureProviderApp: App {
    var body: some Scene {
        WindowGroup { Text("NIC Import Fixtures") }
    }
}
