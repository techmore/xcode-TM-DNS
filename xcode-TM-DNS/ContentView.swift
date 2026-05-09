import SwiftUI
import WebKit

enum TMDNSTheme {
    static let olive50 = Color(red: 0.969, green: 0.973, blue: 0.957)
    static let olive100 = Color(red: 0.933, green: 0.941, blue: 0.902)
    static let olive200 = Color(red: 0.867, green: 0.882, blue: 0.816)
    static let olive300 = Color(red: 0.769, green: 0.788, blue: 0.690)
    static let olive400 = Color(red: 0.655, green: 0.682, blue: 0.545)
    static let olive700 = Color(red: 0.341, green: 0.365, blue: 0.239)
    static let olive800 = Color(red: 0.275, green: 0.290, blue: 0.204)
    static let olive950 = Color(red: 0.122, green: 0.129, blue: 0.090)
    static let stone500 = Color(red: 0.471, green: 0.443, blue: 0.424)
    static let stone900 = Color(red: 0.110, green: 0.098, blue: 0.090)
    static let red = Color(red: 0.753, green: 0.224, blue: 0.169)
    static let green = Color(red: 0.353, green: 0.541, blue: 0.369)
    static let blue = Color(red: 0.306, green: 0.553, blue: 0.639)
}

struct ContentView: View {
    @EnvironmentObject private var service: TMDNSService
    @State private var selection: AppSection = .overview

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .scrollContentBackground(.hidden)
            .background(TMDNSTheme.olive200)
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
            .background(TMDNSTheme.olive300)
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
        .tint(TMDNSTheme.olive700)
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
                    .fill(service.isHealthy ? TMDNSTheme.green : TMDNSTheme.red)
                    .frame(width: 9, height: 9)
                Text(service.isHealthy ? "Online" : "Offline")
                    .font(.caption.weight(.semibold))
            }
            Text(service.statusText)
                .font(.caption)
                .foregroundStyle(TMDNSTheme.stone500)
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
        .background(TMDNSTheme.olive300)
    }
}

struct HeaderCard: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 12) {
                    Text("DNS")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(TMDNSTheme.olive950)
                        .frame(width: 42, height: 34)
                        .background(TMDNSTheme.olive100, in: RoundedRectangle(cornerRadius: 7))
                    Label("DNS Firewall", systemImage: service.isHealthy ? "shield.checkered" : "shield.slash")
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                }
                Spacer()
                Text(service.statusText)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(service.isHealthy ? TMDNSTheme.olive300 : TMDNSTheme.red)
            }
            Text("Native control shell for the local TM-DNS resolver, policy dashboard, and school network visibility.")
                .foregroundStyle(TMDNSTheme.olive300)
        }
        .padding(20)
        .foregroundStyle(TMDNSTheme.olive50)
        .background(TMDNSTheme.olive950, in: RoundedRectangle(cornerRadius: 8))
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
                .foregroundStyle(TMDNSTheme.stone500)
            Text(value)
                .font(.system(size: 31, weight: .semibold, design: .serif))
                .foregroundStyle(TMDNSTheme.stone900)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(TMDNSTheme.olive200, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(TMDNSTheme.olive400, lineWidth: 1))
    }
}

struct RecentActivityCard: View {
    let events: [QueryEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Realtime Activity")
                .font(.system(size: 24, weight: .semibold, design: .serif))
            ForEach(events) { event in
                EventRow(event: event)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(TMDNSTheme.olive200, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(TMDNSTheme.olive400, lineWidth: 1))
    }
}

struct TopDomainsCard: View {
    let rows: [TopRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top Domains")
                .font(.system(size: 24, weight: .semibold, design: .serif))
            TopDomainsList(rows: rows)
        }
        .frame(width: 360, alignment: .topLeading)
        .padding(14)
        .background(TMDNSTheme.olive200, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(TMDNSTheme.olive400, lineWidth: 1))
    }
}

struct ActivityView: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        List(service.dashboard?.dashboard.recent ?? []) { event in
            EventRow(event: event)
                .padding(.vertical, 4)
                .listRowBackground(TMDNSTheme.olive200)
        }
        .scrollContentBackground(.hidden)
        .background(TMDNSTheme.olive300)
    }
}

struct EventRow: View {
    let event: QueryEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.queryName)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(TMDNSTheme.stone900)
                    .lineLimit(1)
                Spacer()
                Text(event.action.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(event.action == "blocked" ? TMDNSTheme.red : TMDNSTheme.green)
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
            .foregroundStyle(TMDNSTheme.stone500)
        }
        .padding(8)
        .background(TMDNSTheme.olive100, in: RoundedRectangle(cornerRadius: 7))
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
                        .foregroundStyle(TMDNSTheme.olive700)
                }
                Text(host.hostname.isEmpty ? "hostname not learned yet" : host.hostname)
                    .font(.caption)
                    .foregroundStyle(TMDNSTheme.stone500)
                Text(host.sourceIP)
                    .font(.caption.monospaced())
                    .foregroundStyle(TMDNSTheme.stone500)
            }
            .padding(.vertical, 6)
            .listRowBackground(TMDNSTheme.olive200)
        }
        .scrollContentBackground(.hidden)
        .background(TMDNSTheme.olive300)
    }
}

struct DomainsView: View {
    @EnvironmentObject private var service: TMDNSService

    var body: some View {
        TopDomainsList(rows: service.dashboard?.dashboard.topDomains ?? [])
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(TMDNSTheme.olive300)
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
                        .foregroundStyle(TMDNSTheme.stone900)
                        .lineLimit(1)
                    Spacer()
                    Text("\(row.count)")
                        .monospacedDigit()
                        .foregroundStyle(TMDNSTheme.stone500)
                    Button("Block") {
                        Task { await service.block(domain: row.key) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(TMDNSTheme.red)
                }
                Divider().overlay(TMDNSTheme.olive400.opacity(0.55))
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
                .foregroundStyle(TMDNSTheme.stone500)
        }
        .padding(24)
        .scrollContentBackground(.hidden)
        .background(TMDNSTheme.olive300)
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
                .foregroundStyle(TMDNSTheme.stone500)
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
        .background(TMDNSTheme.olive100)
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
