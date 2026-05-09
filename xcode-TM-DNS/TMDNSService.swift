import AppKit
import Combine
import Foundation

@MainActor
final class TMDNSService: ObservableObject {
    @Published private(set) var dashboard: DashboardResponse?
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
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Service offline"
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
