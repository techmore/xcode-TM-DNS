import AppKit
import Combine
import Foundation

@MainActor
final class TMDNSService: ObservableObject {
    @Published private(set) var dashboard: DashboardResponse?
    @Published private(set) var blocklistPresets: [BlocklistPreset] = []
    @Published private(set) var blocklistSources: [BlocklistSource] = []
    @Published private(set) var lastBlocklistRefresh: [BlocklistRefreshResult] = []
    @Published private(set) var auditEvents: [AuditEvent] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published var baseURLString = "http://127.0.0.1:8080"

    private var pollingTask: Task<Void, Never>?

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
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func refresh() async {
        do {
            let url = baseURL.appending(path: "/api/dashboard")
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            dashboard = try JSONDecoder.tmdns.decode(DashboardResponse.self, from: data)
            await refreshBlocklists()
            await refreshAudit()
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Service offline"
        }
    }

    func refreshBlocklists() async {
        do {
            async let presetsData = URLSession.shared.data(from: baseURL.appending(path: "/api/blocklist-presets"))
            async let sourcesData = URLSession.shared.data(from: baseURL.appending(path: "/api/blocklist-sources"))
            let (presetResult, sourceResult) = try await (presetsData, sourcesData)
            blocklistPresets = try JSONDecoder.tmdns.decode([BlocklistPreset].self, from: presetResult.0)
            blocklistSources = try JSONDecoder.tmdns.decode([BlocklistSource].self, from: sourceResult.0)
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
            var request = URLRequest(url: baseURL.appending(path: "/api/blocklist-sources"))
            request.httpMethod = "POST"
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
            var request = URLRequest(url: baseURL.appending(path: "/api/blocklists/refresh"))
            request.httpMethod = "POST"
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
            let (data, response) = try await URLSession.shared.data(from: baseURL.appending(path: "/api/audit"))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            auditEvents = try JSONDecoder.tmdns.decode([AuditEvent].self, from: data)
        } catch {
            // Audit visibility should not mark DNS service unhealthy.
        }
    }

    private func patchEnabled(path: String, enabled: Bool) async {
        do {
            var request = URLRequest(url: baseURL.appending(path: path))
            request.httpMethod = "PATCH"
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
            var request = URLRequest(url: baseURL.appending(path: "/api/rules/block"))
            request.httpMethod = "POST"
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
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else { return self }
        return String(dropLast(suffix.count))
    }
}
