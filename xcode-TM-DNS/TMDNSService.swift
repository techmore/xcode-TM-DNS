import AppKit
import Combine
import Foundation
import SystemConfiguration

@MainActor
final class TMDNSService: ObservableObject {
    @Published private(set) var dashboard: DashboardResponse?
    @Published private(set) var blocklistPresets: [BlocklistPreset] = []
    @Published private(set) var blocklistSources: [BlocklistSource] = []
    @Published private(set) var lastBlocklistRefresh: [BlocklistRefreshResult] = []
    @Published private(set) var auditEvents: [AuditEvent] = []
    @Published private(set) var haSettings = HASettings.empty
    @Published private(set) var haStatus: HAStatus?
    @Published private(set) var haSyncResult: HASyncResult?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published var baseURLString = "http://127.0.0.1:8080"
    @Published var adminToken = ""
    @Published private(set) var selectedHostDetail: HostDetail?
    @Published private(set) var updateStatus = UpdateStatus.idle
    @Published private(set) var availableUpdate: GitHubRelease?
    @Published private(set) var detectedLANIP: String?
    @Published private(set) var installedVersionText = "Version unknown"

    private var pollingTask: Task<Void, Never>?
    private var updateCheckTask: Task<Void, Never>?
    private var lastBlocklistPollAt = Date.distantPast
    private var lastAuditPollAt = Date.distantPast
    private var lastHAPollAt = Date.distantPast
    private let releasesURL = URL(string: "https://api.github.com/repos/techmore/TM-DNS/releases/latest")!

    var isHealthy: Bool {
        dashboard != nil && errorMessage == nil
    }

    var statusText: String {
        if let errorMessage {
            return errorMessage
        }
        if let dnsAddr = dashboard?.dns.dnsAddr {
            return "Healthy on \(dnsAddr)"
        }
        return "Waiting for TM-DNS"
    }

    var baseURL: URL {
        URL(string: baseURLString) ?? URL(string: "http://127.0.0.1:8080")!
    }

    func startPolling() async {
        guard pollingTask == nil else { return }
        detectedLANIP = Self.detectLANIP()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        startUpdateChecks()
    }

    func refresh() async {
        detectedLANIP = Self.detectLANIP()
        do {
            let (data, response) = try await data(path: "/api/dashboard")
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            dashboard = try JSONDecoder.tmdns.decode(DashboardResponse.self, from: data)
            refreshInstalledVersionText()
            await refreshMetadataIfNeeded()
            lastUpdated = Date()
            errorMessage = nil
            if shouldRecheckUpdateAfterVersionLoad {
                await checkForUpdates()
            }
        } catch let error as DecodingError {
            errorMessage = "Dashboard data unreadable"
            print("TM-DNS dashboard decode failed: \(error)")
        } catch {
            errorMessage = "Service offline"
            print("TM-DNS dashboard refresh failed: \(error)")
        }
    }

    func checkForUpdates(userInitiated: Bool = false) async {
        if userInitiated {
            updateStatus = .checking
        }
        do {
            var request = URLRequest(url: releasesURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("TM-DNS", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let release = try JSONDecoder.tmdns.decode(GitHubRelease.self, from: data)
            guard let packageAsset = release.packageAsset else {
                throw UpdateError.noPackageAsset
            }
            guard let currentVersion = await currentInstalledVersion() else {
                availableUpdate = nil
                updateStatus = userInitiated ? .failed("Installed version unavailable") : .idle
                refreshInstalledVersionText()
                return
            }
            installedVersionText = "Version \(currentVersion)"
            if isRelease(release.version, newerThan: currentVersion) {
                availableUpdate = release.withPackageAsset(packageAsset)
                updateStatus = .available(release.version)
            } else {
                availableUpdate = nil
                updateStatus = .current
            }
        } catch {
            if userInitiated {
                updateStatus = .failed("Update check failed")
            }
        }
    }

    func installAvailableUpdate() async {
        guard let release = availableUpdate, let asset = release.packageAsset else {
            updateStatus = .failed("No update available")
            return
        }
        do {
            updateStatus = .downloading(release.version)
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(asset.name)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            var request = URLRequest(url: asset.browserDownloadURL)
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
            request.setValue("TM-DNS", forHTTPHeaderField: "User-Agent")
            let (downloadURL, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            try FileManager.default.moveItem(at: downloadURL, to: destination)

            updateStatus = .verifying(release.version)
            try await verifyPackage(at: destination)

            updateStatus = .installing(release.version)
            try await installPackageWithRelaunch(at: destination)
            await monitorInstallation(version: release.version)
        } catch {
            updateStatus = .failed(Self.userFacingUpdateError(error))
        }
    }

    private func request(path: String, method: String = "GET") -> URLRequest {
        let url = Self.apiURL(baseURL: baseURL, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        if !adminToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(adminToken.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    nonisolated static func apiURL(baseURL: URL, path: String) -> URL {
        URL(string: path, relativeTo: baseURL)?.absoluteURL ?? baseURL.appending(path: path)
    }

    private func data(path: String) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request(path: path))
    }

    func refreshBlocklists() async {
        do {
            async let presetsData = data(path: "/api/blocklist-presets")
            async let sourcesData = data(path: "/api/blocklist-sources")
            let (presetResult, sourceResult) = try await (presetsData, sourcesData)
            blocklistPresets = try JSONDecoder.tmdns.decode([BlocklistPreset].self, from: presetResult.0)
            blocklistSources = try JSONDecoder.tmdns.decode([BlocklistSource].self, from: sourceResult.0)
            lastBlocklistPollAt = Date()
        } catch {
            // Keep dashboard health independent from list metadata.
        }
    }

    func setPreset(_ preset: BlocklistPreset, enabled: Bool) async {
        await patchEnabled(path: "/api/blocklist-presets/\(preset.id)", enabled: enabled)
        await refreshBlocklists()
    }

    func setSource(_ source: BlocklistSource, enabled: Bool) async {
        await patchEnabled(path: "/api/blocklist-sources/\(source.id)", enabled: enabled)
        await refreshBlocklists()
    }

    func addSource(name: String, url: String, format: String) async {
        do {
            var request = request(path: "/api/blocklist-sources", method: "POST")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(BlocklistSourceCreateRequest(name: name, url: url, format: format))
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            await refreshBlocklists()
        } catch {
            errorMessage = "List source failed"
        }
    }

    func refreshEnabledBlocklists() async {
        do {
            let request = request(path: "/api/blocklists/refresh", method: "POST")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            lastBlocklistRefresh = try JSONDecoder.tmdns.decode([BlocklistRefreshResult].self, from: data)
            await refreshBlocklists()
        } catch {
            errorMessage = "List refresh failed"
        }
    }

    func refreshAudit() async {
        do {
            let (data, response) = try await data(path: "/api/audit")
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            auditEvents = try JSONDecoder.tmdns.decode([AuditEvent].self, from: data)
            lastAuditPollAt = Date()
        } catch {
            // Audit visibility should not mark DNS service unhealthy.
        }
    }

    func refreshHASettings() async {
        do {
            let (data, response) = try await data(path: "/api/ha/settings")
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            haSettings = try JSONDecoder.tmdns.decode(HASettings.self, from: data)
            lastHAPollAt = Date()
        } catch {
            // HA settings should not mark DNS service unhealthy.
        }
    }

    func saveHASettings(_ settings: HASettings) async {
        do {
            var request = request(path: "/api/ha/settings", method: "PUT")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(settings)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            haSettings = try JSONDecoder.tmdns.decode(HASettings.self, from: data)
        } catch {
            errorMessage = "HA settings failed"
        }
    }

    func testHAPeer() async {
        do {
            let request = request(path: "/api/ha/test", method: "POST")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            haStatus = try JSONDecoder.tmdns.decode(HAStatus.self, from: data)
            await refreshHASettings()
        } catch {
            errorMessage = "HA heartbeat failed"
        }
    }

    func syncHAPeer() async {
        do {
            let request = request(path: "/api/ha/sync", method: "POST")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            haSyncResult = try JSONDecoder.tmdns.decode(HASyncResult.self, from: data)
            await refreshHASettings()
        } catch {
            errorMessage = "HA sync failed"
        }
    }

    private func refreshMetadataIfNeeded() async {
        let now = Date()
        if now.timeIntervalSince(lastBlocklistPollAt) > 300 {
            await refreshBlocklists()
        }
        if now.timeIntervalSince(lastAuditPollAt) > 60 {
            await refreshAudit()
        }
        if now.timeIntervalSince(lastHAPollAt) > 60 {
            await refreshHASettings()
        }
    }

    private func patchEnabled(path: String, enabled: Bool) async {
        do {
            var request = request(path: path, method: "PATCH")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["enabled": enabled])
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
        } catch {
            errorMessage = "List update failed"
        }
    }

    func block(domain: String) async {
        let target = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().trimmingSuffix(".")
        guard !target.isEmpty else { return }
        do {
            var request = request(path: "/api/rules/block", method: "POST")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(RuleCreateRequest(target: target, note: "blocked from macOS app"))
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            await refresh()
        } catch {
            errorMessage = "Block failed"
        }
    }

    func openWebDashboard() {
        NSWorkspace.shared.open(baseURL)
    }

    func selectHost(_ id: Int, hours: Int = 24) async {
        do {
            let window = hours == 48 ? 48 : 24
            errorMessage = nil
            let (data, response) = try await data(path: "/api/hosts/\(id)?hours=\(window)")
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            selectedHostDetail = try JSONDecoder.tmdns.decode(HostDetail.self, from: data)
        } catch let error as DecodingError {
            errorMessage = "Host detail data unreadable"
            print("TM-DNS host detail decode failed: \(error)")
        } catch {
            errorMessage = "Host detail failed"
            print("TM-DNS host detail request failed: \(error)")
        }
    }

    func clearSelectedHost() {
        selectedHostDetail = nil
    }

    private var installedVersionForUpdate: String? {
        if let version = dashboard?.version?.version, isPackagedVersion(version) {
            return version
        }
        return nil
    }

    private var shouldRecheckUpdateAfterVersionLoad: Bool {
        guard installedVersionForUpdate != nil else {
            return false
        }
        switch updateStatus {
        case .idle, .checking, .available:
            return true
        case .current, .downloading, .verifying, .readyToInstall, .installing, .failed:
            return false
        }
    }

    private func startUpdateChecks() {
        guard updateCheckTask == nil else { return }
        updateCheckTask = Task { [weak self] in
            await self?.checkForUpdates()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(21_600))
                await self?.checkForUpdates()
            }
        }
    }

    private func isRelease(_ latest: String, newerThan current: String) -> Bool {
        let latestParts = versionParts(latest)
        let currentParts = versionParts(current)
        guard !latestParts.isEmpty, !currentParts.isEmpty else {
            return latest != current && current != "dev"
        }
        let width = max(latestParts.count, currentParts.count)
        for index in 0..<width {
            let left = index < latestParts.count ? latestParts[index] : 0
            let right = index < currentParts.count ? currentParts[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }

    private func isPackagedVersion(_ version: String) -> Bool {
        versionParts(version).count >= 4
    }

    private func currentInstalledVersion() async -> String? {
        if let version = installedVersionForUpdate {
            return version
        }
        if let version = await healthVersion() {
            return version
        }
        return await packageReceiptVersion()
    }

    func refreshInstalledVersionText() {
        if let version = installedVersionForUpdate {
            installedVersionText = "Version \(version)"
        }
    }

    private func healthVersion() async -> String? {
        do {
            let (data, response) = try await data(path: "/api/health")
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let health = try JSONDecoder.tmdns.decode(HealthResponse.self, from: data)
            guard let version = health.version?.version, isPackagedVersion(version) else {
                return nil
            }
            return version
        } catch {
            return nil
        }
    }

    private func packageReceiptVersion() async -> String? {
        do {
            let output = try await runForOutput("/usr/sbin/pkgutil", arguments: ["--pkg-info", "com.techmore.tmdns"])
            for line in output.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("version:") {
                    let version = trimmed
                        .replacingOccurrences(of: "version:", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return isPackagedVersion(version) ? version : nil
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private func versionParts(_ version: String) -> [Int] {
        version
            .trimmingPrefix("v")
            .split { !$0.isNumber }
            .compactMap { Int($0) }
    }

    private func verifyPackage(at url: URL) async throws {
        try await run("/usr/sbin/pkgutil", arguments: ["--check-signature", url.path], requiredOutput: "Developer ID Installer")
        try await run("/usr/sbin/spctl", arguments: ["-a", "-vvv", "-t", "install", url.path], requiredOutput: "accepted")
    }

    private func installPackageWithRelaunch(at packageURL: URL) async throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tm-dns-update-\(UUID().uuidString).zsh")
        let packagePath = packageURL.path.shellQuoted
        let scriptPath = scriptURL.path.shellQuoted
        let script = """
        #!/bin/zsh
        set -u
        log="/tmp/tm-dns-update.log"
        {
          echo "TM-DNS update started $(date)"
          sleep 1
          /usr/sbin/installer -pkg \(packagePath) -target /
          status=$?
          echo "installer exited ${status} $(date)"
          if [[ ${status} -eq 0 ]]; then
            console_user="$(stat -f '%Su' /dev/console 2>/dev/null || true)"
            if [[ -n "${console_user}" && "${console_user}" != "root" ]]; then
              user_uid="$(id -u "${console_user}" 2>/dev/null || true)"
              if [[ -n "${user_uid}" ]]; then
                /bin/launchctl asuser "${user_uid}" /usr/bin/open -a "/Applications/TM-DNS.app" || true
              fi
            else
              /usr/bin/open -a "/Applications/TM-DNS.app" || true
            fi
          fi
          /bin/rm -f \(scriptPath)
          exit ${status}
        } >> "${log}" 2>&1
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        let command = "(/bin/zsh \(scriptURL.path.shellQuoted) >/tmp/tm-dns-update-launch.log 2>&1 &)"
        let appleScript = "do shell script \(command.appleScriptQuoted) with administrator privileges"
        _ = try await runForOutput("/usr/bin/osascript", arguments: ["-e", appleScript])
    }

    private func monitorInstallation(version: String) async {
        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(2))
            let receiptVersion = await packageReceiptVersion()
            let serviceVersion = await healthVersion()
            if receiptVersion == version || serviceVersion == version {
                installedVersionText = "Version \(version)"
                availableUpdate = nil
                updateStatus = .current
                await refresh()
                return
            }
        }
        updateStatus = .readyToInstall(version)
    }

    private func run(_ launchPath: String, arguments: [String], requiredOutput: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 && output.localizedCaseInsensitiveContains(requiredOutput) {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError.verificationFailed(output))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func runForOutput(_ launchPath: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: UpdateError.commandFailed(output))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    nonisolated static func userFacingUpdateError(_ error: Error) -> String {
        if let updateError = error as? UpdateError {
            return updateError.errorDescription ?? "Update failed"
        }
        return "Update failed: \(error.localizedDescription)"
    }

    private static func detectLANIP() -> String? {
        var addresses: [InterfaceAddress] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else {
            return nil
        }
        defer { freeifaddrs(pointer) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else {
                continue
            }
            guard let address = current.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }
            let name = String(cString: current.pointee.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else {
                continue
            }
            let ip = String(cString: host)
            guard !ip.hasPrefix("127."), !ip.hasPrefix("169.254.") else {
                continue
            }
            addresses.append(InterfaceAddress(name: name, ip: ip, score: scoreInterface(name)))
        }
        return addresses.sorted { left, right in
            if left.score == right.score {
                return left.name < right.name
            }
            return left.score > right.score
        }.first?.ip
    }

    private static func scoreInterface(_ name: String) -> Int {
        let displayName = displayName(forInterface: name).lowercased()
        let combined = "\(name.lowercased()) \(displayName)"
        if combined.contains("ethernet") || combined.contains("usb") || combined.contains("thunderbolt") || combined.contains("lan") {
            return 100
        }
        if combined.contains("wi-fi") || combined.contains("wifi") || combined.contains("airport") {
            return 50
        }
        if name.hasPrefix("en") {
            return 40
        }
        return 10
    }

    private static func displayName(forInterface name: String) -> String {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else {
            return ""
        }
        for interface in interfaces {
            if SCNetworkInterfaceGetBSDName(interface) as String? == name {
                return (SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?) ?? ""
            }
        }
        return ""
    }
}

private struct InterfaceAddress {
    let name: String
    let ip: String
    let score: Int
}

enum UpdateStatus: Equatable {
    case idle
    case checking
    case current
    case available(String)
    case downloading(String)
    case verifying(String)
    case readyToInstall(String)
    case installing(String)
    case failed(String)

    var message: String {
        switch self {
        case .idle: "Updates not checked yet"
        case .checking: "Checking for updates"
        case .current: "TM-DNS is up to date"
        case .available(let version): "Update available: \(version)"
        case .downloading(let version): "Downloading \(version)"
        case .verifying(let version): "Verifying \(version)"
        case .readyToInstall(let version): "Installer started for \(version); waiting for macOS to finish"
        case .installing(let version): "Installing \(version); keep this app open"
        case .failed(let message): message
        }
    }

    var canInstall: Bool {
        if case .available = self { return true }
        return false
    }

    var isWorking: Bool {
        switch self {
        case .checking, .downloading, .verifying, .installing:
            return true
        case .idle, .current, .available, .readyToInstall, .failed:
            return false
        }
    }
}

private extension String {
    var shellQuoted: String {
        "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    var appleScriptQuoted: String {
        "\"\(replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}

struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case assets
    }

    var version: String {
        tagName.trimmingPrefix("v")
    }

    var packageAsset: GitHubReleaseAsset? {
        assets.first { $0.name.hasSuffix(".pkg") && $0.name.hasPrefix("TM-DNS-") }
    }

    func withPackageAsset(_ asset: GitHubReleaseAsset) -> GitHubRelease {
        GitHubRelease(tagName: tagName, name: name, htmlURL: htmlURL, assets: [asset])
    }
}

struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

enum UpdateError: Error {
    case noPackageAsset
    case verificationFailed(String)
    case commandFailed(String)
}

extension UpdateError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noPackageAsset:
            return "No TM-DNS package was attached to the latest release"
        case .verificationFailed(let output):
            return "Package verification failed: \(output.trimmedForStatus)"
        case .commandFailed(let output):
            return "Installer command failed: \(output.trimmedForStatus)"
        }
    }
}

private extension String {
    var trimmedForStatus: String {
        let compact = trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > 180 else { return compact.isEmpty ? "no output" : compact }
        return String(compact.prefix(180)) + "..."
    }

    func trimmingSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else { return self }
        return String(dropLast(suffix.count))
    }

    func trimmingPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else { return self }
        return String(dropFirst(prefix.count))
    }
}
