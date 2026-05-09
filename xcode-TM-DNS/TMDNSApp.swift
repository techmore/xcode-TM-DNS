import AppKit
import SwiftUI

final class SingleInstanceLock {
    static let shared = SingleInstanceLock()

    private let lockURL = FileManager.default.temporaryDirectory.appendingPathComponent("com.techmore.tmdns.app.lock")
    private var fileDescriptor: Int32 = -1

    var hasLock: Bool {
        fileDescriptor >= 0
    }

    func acquire() -> Bool {
        fileDescriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            return false
        }
        if flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 {
            return true
        }
        close(fileDescriptor)
        fileDescriptor = -1
        return false
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard SingleInstanceLock.shared.acquire() else {
            let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.techmore.tmdns"
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            runningApps.first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
                .activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            NSApplication.shared.terminate(nil)
            return
        }
    }
}

@main
struct TMDNSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
