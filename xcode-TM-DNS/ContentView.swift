import SwiftUI
import WebKit

struct ContentView: View {
    @EnvironmentObject private var service: TMDNSService
    @State private var selection: AppSection = .overview

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("TM-DNS")
            .safeAreaInset(edge: .bottom) {
                StatusFooter()
                    .padding(12)
            }
        } detail: {
            Group {
                switch selection {
                case .overview:
                    OverviewView()
                case .activity:
                    ActivityView()
                case .hosts:
                    HostsView()
                case .domains:
                    DomainsView()
                case .web:
                    WebDashboardView(url: service.baseURL)
                case .settings:
                    SettingsView()
                }
            }
            .navigationTitle(selection.title)
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        Task { await service.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    Button {
                        service.openWebDashboard()
                    } label: {
                        Label("Open Web", systemImage: "safari")
                    }
                }
            }
        }
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case activity
    case hosts
    case domains
    case web
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .activity: "Realtime"
        case .hosts: "Hosts"
        case .domains: "Top Domains"
        case .web: "Web Dashboard"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .activity: "waveform.path.ecg"
        case .hosts: "desktopcomputer"
        case .domains: "network"
        case .web: "globe"
        case .settings: "gearshape"
        }
    }
}

struct StatusFooter: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(service.isHealthy ? Color.green : Color.red)
                    .frame(width: 9, height: 9)
                Text(service.isHealthy ? "Online" : "Offline")
                    .font(.caption.weight(.semibold))
            }
            Text(service.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OverviewView: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HeaderCard()
                MetricGrid()
                HStack(alignment: .top, spacing: 16) {
                    RecentActivityCard(events: Array(service.dashboard?.dashboard.recent.prefix(8) ?? []))
                    TopDomainsCard(rows: service.dashboard?.dashboard.topDomains ?? [])
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct HeaderCard: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("DNS Firewall", systemImage: service.isHealthy ? "shield.checkered" : "shield.slash")
                    .font(.title.weight(.semibold))
                Spacer()
                Text(service.statusText)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(service.isHealthy ? .green : .red)
            }
            Text("Native control shell for the local TM-DNS resolver, policy dashboard, and school network visibility.")
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MetricGrid: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        let dashboard = service.dashboard?.dashboard
        let dns = service.dashboard?.dns
        let system = service.dashboard?.system
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            MetricCard(title: "Queries Today", value: "\(dashboard?.queriesToday ?? 0)")
            MetricCard(title: "Blocked Today", value: "\(dashboard?.blockedToday ?? 0)")
            MetricCard(title: "Unique Hosts", value: "\(dashboard?.uniqueHosts ?? 0)")
            MetricCard(title: "Runtime Queries", value: "\(dns?.queries ?? 0)")
            MetricCard(title: "CPU", value: percent(system?.cpuPercent))
            MetricCard(title: "Memory", value: mb(system?.residentMB))
            MetricCard(title: "App Storage", value: mb(system?.appStorageMB))
            MetricCard(title: "Disk Used", value: percent(system?.diskUsedPercent))
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct RecentActivityCard: View {
    let events: [QueryEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Realtime Activity")
                .font(.headline)
            ForEach(events) { event in
                EventRow(event: event)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct TopDomainsCard: View {
    let rows: [TopRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top Domains")
                .font(.headline)
            TopDomainsList(rows: rows)
        }
        .frame(width: 360, alignment: .topLeading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ActivityView: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        List(service.dashboard?.dashboard.recent ?? []) { event in
            EventRow(event: event)
                .padding(.vertical, 4)
        }
    }
}

struct EventRow: View {
    let event: QueryEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.queryName)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                Text(event.action.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(event.action == "blocked" ? .red : .green)
            }
            HStack {
                Text(event.hostLabel)
                Text(event.sourceIP)
                Text(event.queryType)
                Text("\(event.latencyMS)ms")
                Spacer()
                Text(event.answerSummary.isEmpty ? event.responseCode : event.answerSummary)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct HostsView: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        List(service.dashboard?.dashboard.topHosts ?? []) { host in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(host.label.isEmpty ? (host.hostname.isEmpty ? host.sourceIP : host.hostname) : host.label)
                        .font(.headline)
                    Spacer()
                    Text("\(host.count)")
                        .monospacedDigit()
                }
                Text(host.hostname.isEmpty ? "hostname not learned yet" : host.hostname)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(host.sourceIP)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }
}

struct DomainsView: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        TopDomainsList(rows: service.dashboard?.dashboard.topDomains ?? [])
            .padding(20)
    }
}

struct TopDomainsList: View {
    @EnvironmentObject private var service: TMDNSService
    let rows: [TopRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                HStack {
                    Text(row.key)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Text("\(row.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button("Block") {
                        Task { await service.block(domain: row.key) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Divider()
            }
        }
    }
}

struct WebDashboardView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url?.absoluteString != url.absoluteString {
            nsView.load(URLRequest(url: url))
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        Form {
            TextField("Local API URL", text: $service.baseURLString)
            Button("Refresh Connection") {
                Task { await service.refresh() }
            }
            Divider()
            Text("Daemon installation, launchd management, and privileged helper controls belong in the next packaging phase.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(service.isHealthy ? "TM-DNS Online" : "TM-DNS Offline", systemImage: service.isHealthy ? "shield.checkered" : "shield.slash")
                .font(.headline)
            Text(service.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Button("Open Dashboard") {
                service.openWebDashboard()
            }
            Button("Refresh") {
                Task { await service.refresh() }
            }
            Button("Quit TM-DNS App") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 260)
    }
}

private func percent(_ value: Double?) -> String {
    guard let value else { return "0%" }
    return "\(Int(value.rounded()))%"
}

private func mb(_ value: Double?) -> String {
    guard let value else { return "0 MB" }
    return "\(Int(value.rounded())) MB"
}

#Preview {
    ContentView()
        .environmentObject(TMDNSService())
}
