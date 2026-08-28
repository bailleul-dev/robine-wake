import SwiftUI

@main
struct RobineWakeApp: App {
    @StateObject private var bluetooth = BluetoothAlarmClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetooth)
        }
    }
}
