import SwiftUI

@main
struct TMDNSApp: App {
    @StateObject private var service = TMDNSService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(service)
                .frame(minWidth: 1120, minHeight: 760)
                .task {
                    await service.startPolling()
                }
        }
        .windowStyle(.titleBar)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(service)
                .task {
                    await service.startPolling()
                }
        } label: {
            Label("TM-DNS", systemImage: service.isHealthy ? "shield.checkered" : "shield.slash")
        }
    }
}
